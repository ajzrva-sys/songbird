import Foundation
import Combine

@MainActor
public final class PlaybackEngine: ObservableObject {
    public private(set) var status: PlaybackStatus = .stopped {
        didSet {
            activity.update(status)
            presentation.update(status: status)
        }
    }
    public private(set) var position: TimeInterval = 0 {
        didSet { clock.update(position: position) }
    }
    public private(set) var duration: TimeInterval = 0 {
        didSet {
            guard duration != oldValue else { return }
            clock.update(duration: duration)
        }
    }
    public private(set) var volume: Double = 1.0 {
        didSet { volumeState.update(volume) }
    }
    @Published public var sleepTimerEndsAt: Date?
    @Published public private(set) var sleepTimerMinutes: Int?
    @Published public var lastError: String?

    public let activity = PlaybackActivity()
    public let clock = PlaybackClock()
    public let volumeState = PlaybackVolumeState()
    public let presentation = PlaybackPresentationState()

    public let queue: PlaybackQueue
    public let backend: any PlayerBackend
    private let nowPlaying = NowPlayingCommandCenter()
    private var positionTimer: Timer?
    private var sleepTimer: Timer?
    private var didBindCallbacks = false
    /// Exact track handed to backend as gapless/crossfade next (must match on didBegin / advance).
    private var pendingNextTrack: Track?
    private var pendingNextSource: AudioSource?
    /// The exact source currently accepted by the backend. Persisted paths can use a
    /// canonically equivalent spelling, so handoff comparisons must not rebuild it.
    private var activeSource: AudioSource?
    /// Skip queue advance on the didBegin that follows an explicit `play(_:)`.
    private var suppressBeganHandoff = false
    private var playQualification = PlayQualificationTracker()
    private var positionTick = 0
    private var cancellables = Set<AnyCancellable>()
    private var scrobbleStartedAt: Date?
    private var didScrobbleCurrent = false
    private var userVolume: Double = 1.0
    private let pathResolver: FilesystemPathResolver
    private var playRequestGeneration = 0
    private var preloadRequestGeneration = 0
    private var preloadTask: Task<Void, Never>?

    public init(
        queue: PlaybackQueue,
        backend: any PlayerBackend,
        pathResolver: FilesystemPathResolver = FilesystemPathResolver()
    ) {
        self.queue = queue
        self.backend = backend
        self.pathResolver = pathResolver
        bindBackendCallbacks()
        observeQueueChanges()
        nowPlaying.attach(engine: self)
        do {
            try backend.prepare()
        } catch {
            reportError("Backend prepare failed: \(error.localizedDescription)")
        }
        applyVolumeLimit(PlaybackSettings.volumeLimit)
    }

    isolated deinit {
        positionTimer?.invalidate()
        sleepTimer?.invalidate()
    }

    public convenience init() {
        self.init(queue: PlaybackQueue(), backend: NativeAudioBackend())
    }

    public var supportsAudioDiagnostics: Bool {
        backend is any AudioDiagnosticsProviding
    }

    public func audioDiagnosticsSnapshot() -> AudioDiagnosticsSnapshot {
        (backend as? any AudioDiagnosticsProviding)?.audioDiagnosticsSnapshot() ?? .zero
    }

    public func resetAudioDiagnostics() {
        (backend as? any AudioDiagnosticsProviding)?.resetAudioDiagnostics()
    }

    private func bindBackendCallbacks() {
        guard !didBindCallbacks else { return }
        didBindCallbacks = true
        backend.onTrackFinished = { [weak self] in
            Task { @MainActor in
                self?.handlePlaybackFinished()
            }
        }
        backend.onTrackBegan = { [weak self] userInfo in
            Task { @MainActor in
                self?.handleTrackBegan(userInfo)
            }
        }
        backend.onError = { [weak self] message in
            Task { @MainActor in
                self?.reportError(message)
                self?.status = .stopped
                self?.stopPositionTimer()
                self?.position = 0
                self?.nowPlaying.updateNowPlaying()
            }
        }
    }

    private func observeQueueChanges() {
        queue.$upcomingEntries
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshGaplessNext()
            }
            .store(in: &cancellables)

        queue.$currentEntry
            .receive(on: RunLoop.main)
            .sink { [weak self] entry in
                guard let self else { return }
                if let entry {
                    self.presentation.update(currentTrack: entry.track)
                } else {
                    self.presentation.update(clearsTrack: true)
                }
            }
            .store(in: &cancellables)

        queue.$shuffleEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.pendingNextTrack = nil
                self?.pendingNextSource = nil
                self?.refreshGaplessNext()
            }
            .store(in: &cancellables)

        queue.$effectiveOrderRevision
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.pendingNextTrack = nil
                self?.pendingNextSource = nil
                self?.refreshGaplessNext()
            }
            .store(in: &cancellables)

        queue.$repeatMode
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshGaplessNext()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .audioDiscRemoved)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self else { return }
                let removed = Set(
                    (notification.userInfo?["discIDs"] as? [String] ?? []).map(DiscIdentifier.init)
                )
                self.removeAudioCDTracks(for: removed, reportRemoval: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .audioDiscWillEject)
            .sink { [weak self] notification in
                guard let self,
                      let rawID = notification.userInfo?["discID"] as? String else { return }
                self.removeAudioCDTracks(
                    for: [DiscIdentifier(rawID)],
                    reportRemoval: false
                )
            }
            .store(in: &cancellables)
    }

    @discardableResult
    public func play(
        _ track: Track,
        startAt: TimeInterval? = nil,
        committing queueCommit: (() -> Void)? = nil
    ) -> Result<Void, PlaybackStartError> {
        playRequestGeneration &+= 1
        let source: AudioSource
        switch resolvedAudioSource(for: track) {
        case .success(let value):
            source = value
        case .failure(let error):
            reportError(error.localizedDescription)
            return .failure(error)
        }

        return startPlayback(
            track,
            source: source,
            startAt: startAt,
            committing: queueCommit
        )
    }

    /// Resolves persisted file paths away from the main actor, then commits
    /// only if no newer playback request superseded this one.
    @discardableResult
    public func playResolving(
        _ track: Track,
        startAt: TimeInterval? = nil,
        committing queueCommit: (() -> Void)? = nil
    ) async -> Result<Void, PlaybackStartError> {
        playRequestGeneration &+= 1
        let generation = playRequestGeneration
        let source: AudioSource
        if let audioCDSource = track.audioCDSource {
            source = .audioCD(audioCDSource)
        } else {
            let storedPath = track.path
            let resolver = pathResolver
            let resolution = await Task.detached(priority: .userInitiated) {
                resolver.resolve(storedPath)
            }.value
            guard !Task.isCancelled, generation == playRequestGeneration else {
                return .failure(.cancelled)
            }
            switch resolution {
            case .available(let url):
                source = .file(url)
            case .missing:
                let error = PlaybackStartError.fileNotFound(storedPath)
                reportError(error.localizedDescription)
                return .failure(error)
            case .unavailable(let reason):
                let error = PlaybackStartError.volumeUnavailable(reason.message)
                reportError(error.localizedDescription)
                return .failure(error)
            }
        }
        guard !Task.isCancelled, generation == playRequestGeneration else {
            return .failure(.cancelled)
        }
        var prepared: (any PreparedAudioSource)?
        if let preparingBackend = backend as? any SourcePreparingPlayerBackend {
            do {
                prepared = try await preparingBackend.prepareSource(source, startAt: startAt ?? 0)
            } catch {
                guard !Task.isCancelled, generation == playRequestGeneration,
                      !(error is CancellationError) else { return .failure(.cancelled) }
                let failure = PlaybackStartError.backendRejected(error.localizedDescription)
                reportError(failure.localizedDescription)
                return .failure(failure)
            }
            guard !Task.isCancelled, generation == playRequestGeneration else {
                return .failure(.cancelled)
            }
        }
        return startPlayback(
            track,
            source: source,
            startAt: startAt,
            prepared: prepared,
            committing: queueCommit
        )
    }

    private func startPlayback(
        _ track: Track,
        source: AudioSource,
        startAt: TimeInterval?,
        prepared: (any PreparedAudioSource)? = nil,
        committing queueCommit: (() -> Void)?
    ) -> Result<Void, PlaybackStartError> {
        do {
            if let prepared, let preparingBackend = backend as? any SourcePreparingPlayerBackend {
                try preparingBackend.playPrepared(prepared, durationHint: track.duration)
            } else {
                try backend.play(source, durationHint: track.duration)
            }
        } catch {
            let failure = PlaybackStartError.backendRejected(error.localizedDescription)
            reportError(failure.localizedDescription)
            return .failure(failure)
        }

        queueCommit?()
        activeSource = source

        lastError = nil
        LibraryStatus.shared.clearPlaybackError()

        if let startAt, startAt > 0 {
            if prepared == nil { backend.seek(to: startAt) }
            position = startAt
        } else {
            position = 0
        }

        queue.setCurrentTrack(track)
        pendingNextTrack = nil
        pendingNextSource = nil
        suppressBeganHandoff = true
        status = .playing
        duration = backend.duration > 0 ? backend.duration : track.duration
        if track.isAudioCDTrack {
            playQualification.reset()
        } else {
            playQualification.begin(
                trackID: track.id,
                duration: duration,
                uptime: ProcessInfo.processInfo.systemUptime
            )
        }
        applyVolumeLimit(PlaybackSettings.volumeLimit)
        startPositionTimer()
        scrobbleStartedAt = Date()
        didScrobbleCurrent = false
        persistLastTrack()
        refreshGaplessNext()
        nowPlaying.updateNowPlaying(forceArtwork: true)
        if !track.isAudioCDTrack {
            LastFMClient.shared.updateNowPlaying(
                artist: track.artist,
                track: track.title,
                album: track.album.isEmpty ? nil : track.album
            )
        }
        return .success(())
    }

    @discardableResult
    public func play(_ track: Track) -> Result<Void, PlaybackStartError> {
        play(track, startAt: nil)
    }

    public func pause() {
        playRequestGeneration &+= 1
        backend.pause()
        status = .paused
        persistLastTrack()
        playQualification.pause(uptime: ProcessInfo.processInfo.systemUptime)
        stopPositionTimer()
        nowPlaying.updateNowPlaying()
    }

    public func resume() {
        backend.resume()
        status = .playing
        playQualification.resume(uptime: ProcessInfo.processInfo.systemUptime)
        startPositionTimer()
        nowPlaying.updateNowPlaying()
    }

    public func playIfPossible() {
        switch status {
        case .playing:
            return
        case .paused:
            resume()
        case .stopped, .loading:
            if let track = queue.currentTrack {
                if track.isAudioCDTrack {
                    _ = play(track)
                } else {
                    Task { [weak self] in _ = await self?.playResolving(track) }
                }
            } else if let next = queue.peekNextEntry() {
                if next.track.isAudioCDTrack {
                    _ = play(next.track) { [queue] in
                        _ = queue.advanceToNext(entryID: next.id)
                    }
                } else {
                    Task { [weak self, queue] in
                        _ = await self?.playResolving(next.track) {
                            _ = queue.advanceToNext(entryID: next.id)
                        }
                    }
                }
            }
        }
    }

    public func pauseIfPlaying() {
        guard status == .playing else { return }
        pause()
    }

    public func stop() {
        playRequestGeneration &+= 1
        preloadRequestGeneration &+= 1
        preloadTask?.cancel()
        persistLastTrack()
        backend.stop()
        status = .stopped
        position = 0
        pendingNextTrack = nil
        pendingNextSource = nil
        activeSource = nil
        playQualification.reset()
        stopPositionTimer()
        nowPlaying.updateNowPlaying()
    }

    public func togglePlayPause() {
        switch status {
        case .playing: pause()
        case .paused, .stopped, .loading: playIfPossible()
        }
    }

    public func seekTo(_ time: TimeInterval) {
        guard let preparingBackend = backend as? any SourcePreparingPlayerBackend,
              let source = activeSource else {
            backend.seek(to: time)
            didSeek(to: time)
            return
        }
        playRequestGeneration &+= 1
        let generation = playRequestGeneration
        Task { [weak self] in
            do {
                let prepared = try await preparingBackend.prepareSource(source, startAt: time)
                guard let self, generation == self.playRequestGeneration,
                      self.activeSource == source else { return }
                try preparingBackend.seekPrepared(prepared)
                self.didSeek(to: time)
            } catch {
                guard let self, generation == self.playRequestGeneration,
                      !(error is CancellationError) else { return }
                self.reportError("Could not seek: \(error.localizedDescription)")
            }
        }
    }

    private func didSeek(to time: TimeInterval) {
        position = time
        nowPlaying.updateNowPlaying()
        persistLastTrack()
    }

    public func setVolume(_ v: Double) {
        userVolume = min(max(v, 0), 1)
        applyVolumeLimit(PlaybackSettings.volumeLimit)
    }

    public func applyVolumeLimit(_ limit: Double) {
        let capped = min(max(limit, 0.5), 1.0)
        let effective = min(userVolume, capped)
        volume = effective
        backend.volume = effective
    }

    public func playNext() {
        if let next = queue.peekNextEntry() {
            Task { [weak self, queue] in
                _ = await self?.playResolving(next.track) {
                    _ = queue.advanceToNext(entryID: next.id)
                }
            }
        } else {
            stop()
        }
    }

    public func playPrevious() {
        if position > 3 {
            seekTo(0)
            return
        }
        if let previous = queue.peekPreviousEntry() {
            Task { [weak self, queue] in
                _ = await self?.playResolving(previous.track) {
                    _ = queue.advanceToPrevious(entryID: previous.id)
                }
            }
        } else {
            seekTo(0)
        }
    }

    public func cycleRepeatMode() {
        switch queue.repeatMode {
        case .off: queue.repeatMode = .all
        case .all: queue.repeatMode = .one
        case .one: queue.repeatMode = .off
        }
    }

    // MARK: - Sleep timer

    public func setSleepTimer(minutes: Int) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        guard minutes > 0 else {
            sleepTimerEndsAt = nil
            sleepTimerMinutes = nil
            return
        }
        sleepTimerMinutes = minutes
        let ends = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerEndsAt = ends
        sleepTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.sleepTimerEndsAt = nil
                self?.sleepTimerMinutes = nil
                self?.stop()
            }
        }
    }

    public func clearSleepTimer() {
        setSleepTimer(minutes: 0)
    }

    public func prepareForTermination() {
        persistLastTrack()
    }

    public var stopAfterCurrent: Bool {
        get { PlaybackSettings.stopAfterCurrent }
        set {
            PlaybackSettings.stopAfterCurrent = newValue
            refreshGaplessNext()
        }
    }

    // MARK: - Resume

    public func resumeLastTrackIfNeeded(from tracks: [Track]) {
        guard PlaybackSettings.resumeOnLaunch else { return }
        let storedID = UserDefaults.standard
            .string(forKey: PlaybackSettings.lastTrackIDKey)
            .flatMap(UUID.init(uuidString:))
        let trackByID = storedID.flatMap { id in
            tracks.first(where: { $0.id == id })
        }
        let storedPath = UserDefaults.standard.string(forKey: PlaybackSettings.lastTrackPathKey)
        guard let track = trackByID ?? storedPath.flatMap({ path in
            guard path.isEmpty == false else { return nil }
            return tracks.first(where: { $0.path == path })
        }) else { return }
        let saved = UserDefaults.standard.double(forKey: PlaybackSettings.lastTrackPositionKey)
        let start: TimeInterval? = PlaybackSettings.rememberPosition && saved > 1 ? saved : nil
        Task { [weak self, queue] in
            await self?.playResolving(track, startAt: start) {
                queue.setCurrentTrack(track)
            }
        }
    }

    /// Call after enqueue / shuffle changes so backend's next stream stays current.
    public func refreshGaplessNext() {
        guard status == .playing || status == .paused else {
            preloadRequestGeneration &+= 1
            preloadTask?.cancel()
            backend.setNextURL(nil, crossfadeDuration: 0)
            pendingNextTrack = nil
            pendingNextSource = nil
            return
        }
        guard !PlaybackSettings.stopAfterCurrent else {
            preloadRequestGeneration &+= 1
            preloadTask?.cancel()
            backend.setNextURL(nil, crossfadeDuration: 0)
            pendingNextTrack = nil
            pendingNextSource = nil
            return
        }

        let crossfade = queue.currentTrack?.isAudioCDTrack == true
            ? 0
            : PlaybackSettings.crossfadeSeconds

        switch queue.repeatMode {
        case .one:
            if let current = queue.currentTrack {
                preload(current, crossfadeDuration: crossfade)
            } else {
                preloadRequestGeneration &+= 1
                preloadTask?.cancel()
                backend.setNextURL(nil, crossfadeDuration: 0)
                pendingNextTrack = nil
                pendingNextSource = nil
            }
        case .off, .all:
            if let pending = pendingNextTrack,
               let pendingNextSource,
               upcomingContains(pending) {
                if let preparingBackend = backend as? any SourcePreparingPlayerBackend,
                   !preparingBackend.hasPreparedNext(pendingNextSource) {
                    preload(pending, crossfadeDuration: pending.isAudioCDTrack ? 0 : crossfade)
                    return
                }
                backend.setNextSource(
                    pendingNextSource,
                    crossfadeDuration: pending.isAudioCDTrack ? 0 : crossfade
                )
                return
            }
            if let peek = queue.peekNext() {
                preload(peek, crossfadeDuration: peek.isAudioCDTrack ? 0 : crossfade)
            } else {
                preloadRequestGeneration &+= 1
                preloadTask?.cancel()
                backend.setNextURL(nil, crossfadeDuration: 0)
                pendingNextTrack = nil
                pendingNextSource = nil
            }
        }
    }

    private func preload(_ track: Track, crossfadeDuration: TimeInterval) {
        // An obsolete pending stream must not begin while its replacement loads.
        backend.setNextSource(nil, crossfadeDuration: 0)
        pendingNextTrack = nil
        pendingNextSource = nil
        preloadRequestGeneration &+= 1
        let generation = preloadRequestGeneration
        preloadTask?.cancel()
        if let audioCDSource = track.audioCDSource {
            let source = AudioSource.audioCD(audioCDSource)
            backend.setNextSource(source, crossfadeDuration: crossfadeDuration)
            pendingNextTrack = track
            pendingNextSource = source
            return
        }
        let resolver = pathResolver
        let storedPath = track.path
        preloadTask = Task { [weak self] in
            let resolved: Result<AudioSource, PlaybackStartError>
            let resolution = await Task.detached(priority: .utility) {
                resolver.resolve(storedPath)
            }.value
            switch resolution {
            case .available(let url): resolved = .success(.file(url))
            case .missing: resolved = .failure(.fileNotFound(storedPath))
            case .unavailable(let reason):
                resolved = .failure(.volumeUnavailable(reason.message))
            }
            guard let self,
                  !Task.isCancelled,
                  generation == self.preloadRequestGeneration else { return }
            switch resolved {
            case .success(let source):
                do {
                    if let preparingBackend = self.backend as? any SourcePreparingPlayerBackend {
                        let prepared = try await preparingBackend.prepareSource(source, startAt: 0)
                        guard !Task.isCancelled, generation == self.preloadRequestGeneration else { return }
                        try preparingBackend.setNextPrepared(prepared, crossfadeDuration: crossfadeDuration)
                    } else {
                        self.backend.setNextSource(source, crossfadeDuration: crossfadeDuration)
                    }
                    self.pendingNextTrack = track
                    self.pendingNextSource = source
                } catch {
                    guard !Task.isCancelled, generation == self.preloadRequestGeneration else { return }
                    self.backend.setNextSource(nil, crossfadeDuration: 0)
                    self.pendingNextTrack = nil
                    self.pendingNextSource = nil
                }
            case .failure:
                self.backend.setNextURL(nil, crossfadeDuration: 0)
                self.pendingNextTrack = nil
                self.pendingNextSource = nil
            }
        }
    }

    private func upcomingContains(_ track: Track?) -> Bool {
        guard let track else { return false }
        return queue.upcomingTracks.contains(where: { $0.id == track.id })
    }

    /// Sticky next for crossfade / gapless — same source as `peekNext()`.
    private func pinnedNextTrack() -> Track? {
        switch queue.repeatMode {
        case .one: return queue.currentTrack
        case .off, .all:
            return queue.peekNext() ?? (queue.repeatMode == .all ? queue.currentTrack : nil)
        }
    }

    private func handleTrackBegan(_ userInfo: Any?) {
        status = .playing
        startPositionTimer()
        duration = backend.duration > 0 ? backend.duration : (queue.currentTrack?.duration ?? duration)

        let begunSource = userInfo as? AudioSource
        let skipHandoff = suppressBeganHandoff
        suppressBeganHandoff = false

        if skipHandoff {
            refreshGaplessNext()
            nowPlaying.updateNowPlaying(forceArtwork: true)
            return
        }

        if queue.repeatMode == .one {
            if let current = queue.currentTrack, begunSource == nil || begunSource == activeSource {
                beginPlayQualification(for: current)
                scrobbleStartedAt = Date()
                didScrobbleCurrent = false
            }
            refreshGaplessNext()
            nowPlaying.updateNowPlaying(forceArtwork: true)
            return
        }

        if let pending = pendingNextTrack,
           begunSource == pendingNextSource,
           queue.currentTrack?.id != pending.id {
            queue.promote(pending)
            activeSource = pendingNextSource
            beginPlayQualification(for: pending)
            scrobbleStartedAt = Date()
            didScrobbleCurrent = false
            if !pending.isAudioCDTrack {
                LastFMClient.shared.updateNowPlaying(
                    artist: pending.artist,
                    track: pending.title,
                    album: pending.album.isEmpty ? nil : pending.album
                )
            }
        }

        pendingNextTrack = nil
        pendingNextSource = nil
        refreshGaplessNext()
        nowPlaying.updateNowPlaying(forceArtwork: true)
    }

    private func recordPlay(for track: Track) {
        let previousCount = track.playCount
        let previousDate = track.lastPlayed
        track.playCount += 1
        track.lastPlayed = Date()
        do {
            try track.modelContext?.save()
        } catch {
            track.playCount = previousCount
            track.lastPlayed = previousDate
            LibraryStatus.shared.showNotice(
                "Playback continued, but play history could not be saved: \(error.localizedDescription)",
                severity: .warning
            )
        }
    }

    private func beginPlayQualification(for track: Track) {
        guard !track.isAudioCDTrack else {
            playQualification.reset()
            return
        }
        let resolvedDuration = backend.duration > 0 ? backend.duration : track.duration
        playQualification.begin(
            trackID: track.id,
            duration: resolvedDuration,
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private func checkPlayQualification() {
        guard playQualification.advance(uptime: ProcessInfo.processInfo.systemUptime),
              let track = queue.currentTrack,
              playQualification.trackID == track.id else { return }
        recordPlay(for: track)
    }

    private func handlePlaybackFinished() {
        pendingNextTrack = nil
        pendingNextSource = nil
        activeSource = nil
        if PlaybackSettings.stopAfterCurrent {
            PlaybackSettings.stopAfterCurrent = false
            stop()
            return
        }

        switch queue.repeatMode {
        case .one:
            if let track = queue.currentTrack {
                Task { [weak self] in _ = await self?.playResolving(track) }
            }
        case .all:
            if let next = queue.peekNextEntry() {
                Task { [weak self, queue] in
                    _ = await self?.playResolving(next.track) {
                        _ = queue.advanceToNext(entryID: next.id)
                    }
                }
            } else if let current = queue.currentTrack {
                let replay = queue.history + [current]
                if let first = replay.first {
                    Task { [weak self, queue] in
                        _ = await self?.playResolving(first) {
                            _ = queue.replace(with: replay)
                        }
                    }
                } else {
                    stop()
                }
            } else {
                stop()
            }
        case .off:
            if let next = queue.peekNextEntry() {
                Task { [weak self, queue] in
                    _ = await self?.playResolving(next.track) {
                        _ = queue.advanceToNext(entryID: next.id)
                    }
                }
            } else {
                stop()
            }
        }
    }

    private func startPositionTimer() {
        stopPositionTimer()
        positionTick = 0
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.position = self.backend.position
                let backendDuration = self.backend.duration
                if backendDuration > 0 {
                    self.duration = backendDuration
                }
                self.positionTick += 1
                if self.positionTick % 50 == 0 {
                    self.persistLastTrack()
                }
                self.checkPlayQualification()
                self.checkScrobble()
            }
        }
    }

    private func stopPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func persistLastTrack() {
        guard let track = queue.currentTrack else { return }
        guard !track.isAudioCDTrack else { return }
        UserDefaults.standard.set(track.path, forKey: PlaybackSettings.lastTrackPathKey)
        UserDefaults.standard.set(track.id.uuidString, forKey: PlaybackSettings.lastTrackIDKey)
        if PlaybackSettings.rememberPosition {
            UserDefaults.standard.set(position, forKey: PlaybackSettings.lastTrackPositionKey)
        }
    }

    private func checkScrobble() {
        guard !didScrobbleCurrent,
              let track = queue.currentTrack,
              !track.isAudioCDTrack,
              let started = scrobbleStartedAt,
              duration > 0 else { return }
        let threshold = min(duration * 0.5, 240)
        guard position >= threshold else { return }
        didScrobbleCurrent = true
        LastFMClient.shared.scrobble(
            artist: track.artist,
            track: track.title,
            album: track.album.isEmpty ? nil : track.album,
            startedAt: started
        )
    }

    private func reportError(_ msg: String) {
        lastError = msg
        LibraryStatus.shared.showNotice(msg, severity: .error, source: .playback)
    }

    func removeAudioCDTracks(for discIDs: Set<DiscIdentifier>, reportRemoval: Bool) {
        guard !discIDs.isEmpty else { return }
        let wasPlayingDisc = queue.removeEntries { track in
            track.audioDiscID.map(discIDs.contains) == true
        }
        if wasPlayingDisc {
            stopImmediatelyForMediaRemoval()
            if reportRemoval { reportError("The audio CD was removed.") }
        }
    }

    private func stopImmediatelyForMediaRemoval() {
        persistLastTrack()
        backend.stopImmediately()
        status = .stopped
        position = 0
        pendingNextTrack = nil
        pendingNextSource = nil
        activeSource = nil
        playQualification.reset()
        stopPositionTimer()
        nowPlaying.updateNowPlaying()
    }

    private func resolvedAudioSource(
        for track: Track
    ) -> Result<AudioSource, PlaybackStartError> {
        if let source = track.audioCDSource { return .success(.audioCD(source)) }
        switch pathResolver.resolve(track.path) {
        case .available(let url):
            return .success(.file(url))
        case .missing:
            return .failure(.fileNotFound(track.path))
        case .unavailable(let reason):
            return .failure(.volumeUnavailable(reason.message))
        }
    }
}
