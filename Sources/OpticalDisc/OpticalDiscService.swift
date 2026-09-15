import AppKit
import CryptoKit
import DiskArbitration
import Foundation
import OpticalDiscBridge

public enum OpticalDiscError: Error, LocalizedError, Equatable, Sendable {
    case enumerationFailed(Int32)
    case tocReadFailed(deviceID: String, code: Int32)
    case noAudioTracks(deviceID: String)
    case metadataLookupFailed(String)
    case ejectFailed(String)
    case sandboxDenied

    public var errorDescription: String? {
        switch self {
        case .enumerationFailed(let code): "Could not enumerate optical drives (error \(code))."
        case .tocReadFailed(let device, let code): "Could not read the CD in \(device) (error \(code))."
        case .noAudioTracks: "The inserted disc has no playable audio tracks."
        case .metadataLookupFailed(let message): "CD metadata lookup failed: \(message)"
        case .ejectFailed(let message): "Could not eject the disc: \(message)"
        case .sandboxDenied: "This build is not permitted to read audio CD sectors."
        }
    }
}

public struct OpticalDiscDescriptor: Sendable, Equatable {
    public let deviceID: String
    public let registryID: UInt64
    public let entries: [AudioCDTOCParser.Entry]
    public let leadOutSector: Int64
    public let cdText: AudioCDText
}

public protocol OpticalDiscAccessing: Sendable {
    func discover() async throws -> [OpticalDiscDescriptor]
}

public protocol OpticalDiscEjecting: Sendable {
    func eject(deviceID: String) async throws
}

public struct DiskArbitrationDiscEjector: OpticalDiscEjecting {
    public init() {}

    public func eject(deviceID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let session = DASessionCreate(kCFAllocatorDefault),
                  let mediaDisk = deviceID.withCString({
                      DADiskCreateFromBSDName(kCFAllocatorDefault, session, $0)
                  }) else {
                continuation.resume(throwing: OpticalDiscError.ejectFailed("Drive is unavailable."))
                return
            }
            let disk = DADiskCopyWholeDisk(mediaDisk) ?? mediaDisk
            let context = DiscEjectContext(session: session, disk: disk, continuation: continuation)
            DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            DADiskUnmount(
                disk,
                DADiskUnmountOptions(kDADiskUnmountOptionWhole),
                songbirdDiscUnmounted,
                Unmanaged.passRetained(context).toOpaque()
            )
        }
    }
}

private final class DiscEjectContext: @unchecked Sendable {
    let session: DASession
    let disk: DADisk
    let continuation: CheckedContinuation<Void, Error>

    init(session: DASession, disk: DADisk, continuation: CheckedContinuation<Void, Error>) {
        self.session = session
        self.disk = disk
        self.continuation = continuation
    }
}

private func songbirdDiscUnmounted(
    _ disk: DADisk,
    _ dissenter: DADissenter?,
    _ rawContext: UnsafeMutableRawPointer?
) {
    guard let rawContext else { return }
    if let dissenter, DADissenterGetStatus(dissenter) != kDAReturnNotMounted {
        let context = Unmanaged<DiscEjectContext>.fromOpaque(rawContext).takeRetainedValue()
        finishDiscOperation(
            context,
            error: ejectError(from: dissenter, fallback: "The disc could not be unmounted.")
        )
        return
    }

    DADiskEject(
        disk,
        DADiskEjectOptions(kDADiskEjectOptionDefault),
        songbirdDiscEjected,
        rawContext
    )
}

private func songbirdDiscEjected(_ disk: DADisk, _ dissenter: DADissenter?, _ rawContext: UnsafeMutableRawPointer?) {
    guard let rawContext else { return }
    let context = Unmanaged<DiscEjectContext>.fromOpaque(rawContext).takeRetainedValue()
    finishDiscOperation(
        context,
        error: dissenter.map {
            ejectError(from: $0, fallback: "The drive refused to eject.")
        }
    )
}

private func finishDiscOperation(_ context: DiscEjectContext, error: OpticalDiscError?) {
    DASessionUnscheduleFromRunLoop(
        context.session,
        CFRunLoopGetMain(),
        CFRunLoopMode.defaultMode.rawValue
    )
    if let error {
        context.continuation.resume(throwing: error)
    } else {
        context.continuation.resume()
    }
}

private func ejectError(from dissenter: DADissenter, fallback: String) -> OpticalDiscError {
    let message = (DADissenterGetStatusString(dissenter) as String?) ?? fallback
    return .ejectFailed(message)
}

public actor SystemOpticalDiscAccess: OpticalDiscAccessing {
    public init() {}

    public func discover() throws -> [OpticalDiscDescriptor] {
        var count: Int32 = 0
        var status = SBOpticalDiscCopyDevices(nil, 0, &count)
        guard status == 0 else { throw OpticalDiscError.enumerationFailed(status) }
        guard count > 0 else { return [] }

        var devices = [SBOpticalDiscDevice](
            repeating: SBOpticalDiscDevice(),
            count: Int(count)
        )
        status = SBOpticalDiscCopyDevices(&devices, count, &count)
        guard status == 0 else { throw OpticalDiscError.enumerationFailed(status) }

        return try devices.prefix(Int(count)).map { device in
            let deviceID = withUnsafeBytes(of: device.bsdName) { rawBuffer in
                let bytes = rawBuffer.bindMemory(to: CChar.self)
                return String(cString: bytes.baseAddress!)
            }
            var entryCount: Int32 = 0
            var leadOut: Int64 = 0
            status = deviceID.withCString {
                SBOpticalDiscReadTOC($0, nil, 0, &entryCount, &leadOut)
            }
            guard status == 0 else {
                throw OpticalDiscError.tocReadFailed(deviceID: deviceID, code: status)
            }
            var rawEntries = [SBOpticalTOCEntry](
                repeating: SBOpticalTOCEntry(),
                count: Int(entryCount)
            )
            status = deviceID.withCString {
                SBOpticalDiscReadTOC($0, &rawEntries, entryCount, &entryCount, &leadOut)
            }
            guard status == 0 else {
                throw OpticalDiscError.tocReadFailed(deviceID: deviceID, code: status)
            }
            let entries = rawEntries.prefix(Int(entryCount)).map {
                AudioCDTOCParser.Entry(
                    number: Int($0.point),
                    startSector: $0.startSector,
                    isData: ($0.control & 0x04) != 0
                )
            }
            return OpticalDiscDescriptor(
                deviceID: deviceID,
                registryID: device.registryID,
                entries: entries,
                leadOutSector: leadOut,
                cdText: Self.readCDText(deviceID: deviceID)
            )
        }
    }

    private static func readCDText(deviceID: String) -> AudioCDText {
        var buffer = Data(count: 64 * 1024)
        let capacity = buffer.count
        var bytesRead: Int32 = 0
        let status = buffer.withUnsafeMutableBytes { rawBuffer in
            deviceID.withCString {
                SBOpticalDiscReadCDText(
                    $0,
                    rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                    Int32(capacity),
                    &bytesRead
                )
            }
        }
        guard status == 0, bytesRead > 4 else { return .empty }
        buffer.count = Int(bytesRead)
        return AudioCDTextParser.parse(buffer)
    }
}

@MainActor
public protocol OpticalDiscProviding: AnyObject {
    var discs: [AudioDisc] { get }
    var isRefreshing: Bool { get }
    var lastError: OpticalDiscError? { get }
    func refresh() async
    func eject(_ disc: AudioDisc) async
}

@MainActor
public final class OpticalDiscService: ObservableObject, OpticalDiscProviding {
    @Published public private(set) var discs: [AudioDisc] = []
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastError: OpticalDiscError?
    @Published public private(set) var metadataCandidates: [DiscIdentifier: [AudioCDMetadataCandidate]] = [:]

    private let access: any OpticalDiscAccessing
    private let ejector: any OpticalDiscEjecting
    private let metadataProvider: any AudioCDMetadataProviding
    private let clock: @Sendable () -> DiscogsFetchStamp?
    private let expirySleep: @Sendable (TimeInterval) async throws -> Void
    private let workspaceNotifications: NotificationCenter
    private let applicationNotifications: NotificationCenter
    private var session: DASession?
    private let arbitrationQueue = DispatchQueue(label: "Songbird optical disc arbitration")
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lifecycleObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var metadataExpiryTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0
    private var importingDiscIDs: Set<DiscIdentifier> = []
    private var originalMetadataByDisc: [DiscIdentifier: AudioDiscOriginalMetadata] = [:]

    public init(
        access: any OpticalDiscAccessing = SystemOpticalDiscAccess(),
        ejector: any OpticalDiscEjecting = DiskArbitrationDiscEjector(),
        metadataProvider: (any AudioCDMetadataProviding)? = nil,
        startsObserving: Bool = true,
        clock: @escaping @Sendable () -> DiscogsFetchStamp? = { DiscogsClock.sample() },
        expirySleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(for: .seconds($0))
        },
        workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
        applicationNotifications: NotificationCenter = .default
    ) {
        self.access = access
        self.ejector = ejector
        self.metadataProvider = metadataProvider ?? Self.defaultMetadataProvider()
        self.clock = clock
        self.expirySleep = expirySleep
        self.workspaceNotifications = workspaceNotifications
        self.applicationNotifications = applicationNotifications
        observeMetadataLifecycle()
        if startsObserving {
            startObserving()
            scheduleRefresh()
        }
    }

    isolated deinit {
        refreshTask?.cancel()
        metadataExpiryTask?.cancel()
        lifecycleObservers.forEach { $0.0.removeObserver($0.1) }
        workspaceObservers.forEach(workspaceNotifications.removeObserver)
        if let session { DASessionSetDispatchQueue(session, nil) }
    }

    public func refresh() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        isRefreshing = true
        defer { if generation == refreshGeneration { isRefreshing = false } }
        do {
            let descriptors = try await access.discover()
            try Task.checkCancellation()
            guard generation == refreshGeneration else { return }
            let found = descriptors.compactMap(makeDisc).map { disc in
                var snapshot = disc
                if importingDiscIDs.contains(disc.id) { snapshot.status = .importing }
                return snapshot
            }
            let removedIDs = Set(discs.map(\.id)).subtracting(found.map(\.id))
            importingDiscIDs.subtract(removedIDs)
            originalMetadataByDisc = Dictionary(found.map { ($0.id, $0.originalMetadata) },
                                                uniquingKeysWith: { first, _ in first })
            discs = found
            metadataCandidates.removeAll()
            revalidateMetadata()
            lastError = nil
            postRemoval(ids: removedIDs)
            await loadMetadata(for: found, generation: generation)
        } catch is CancellationError {
            return
        } catch let error as OpticalDiscError {
            guard generation == refreshGeneration else { return }
            lastError = error
        } catch {
            guard generation == refreshGeneration else { return }
            lastError = .enumerationFailed(-1)
        }
    }

    public func eject(_ disc: AudioDisc) async {
        guard let index = discs.firstIndex(where: { $0.id == disc.id }) else { return }
        guard discs[index].status != .importing else {
            lastError = .ejectFailed("Cancel the CD import before ejecting the disc.")
            return
        }
        discs[index].status = .ejecting
        NotificationCenter.default.post(
            name: .audioDiscWillEject,
            object: nil,
            userInfo: ["discID": disc.id.rawValue]
        )
        do {
            guard let deviceID = disc.tracks.first?.source.deviceID else { return }
            try await ejectWithRetry(deviceID: deviceID)
            await refresh()
        } catch let error as OpticalDiscError {
            lastError = error
            if let index = discs.firstIndex(where: { $0.id == disc.id }) {
                discs[index].status = .ready
            }
        } catch {
            lastError = .ejectFailed(error.localizedDescription)
            if let index = discs.firstIndex(where: { $0.id == disc.id }) {
                discs[index].status = .ready
            }
        }
    }

    public func clearError() { lastError = nil }

    /// Called by the service's lifecycle/timer owner, never by row rendering or audio callbacks.
    public func revalidateMetadata() {
        let now = clock()
        for (id, candidates) in metadataCandidates {
            let usable = candidates.filter { isUsable($0, at: now) }
            metadataCandidates[id] = usable.isEmpty ? nil : usable
        }
        for index in discs.indices {
            if let evidence = discs[index].discogsEvidence, !evidence.isFresh(at: now) {
                discs[index] = discs[index].restoringOriginalMetadata()
            }
        }
        scheduleMetadataExpiry(at: now)
    }

    private func scheduleMetadataExpiry(at now: DiscogsFetchStamp?) {
        metadataExpiryTask?.cancel()
        metadataExpiryTask = nil
        let evidence = discs.compactMap(\.discogsEvidence)
            + metadataCandidates.values.flatMap { $0.compactMap(\.discogsEvidence) }
        guard let now, !evidence.isEmpty else { return }
        // Use both clocks and cap the wait to notice wall changes even without a wake event.
        let remaining = evidence.flatMap(\.fetches).map {
            DiscogsFreshness.maximumAge - max(now.wall.timeIntervalSince($0.wall),
                                               now.continuousSeconds - $0.continuousSeconds)
        }.min() ?? 0
        let delay = max(0.001, min(60, remaining))
        metadataExpiryTask = Task { [weak self, expirySleep] in
            do { try await expirySleep(delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.revalidateMetadata()
        }
    }

    private func observeMetadataLifecycle() {
        for (center, name) in [
            (workspaceNotifications, NSWorkspace.didWakeNotification),
            (applicationNotifications, NSApplication.didBecomeActiveNotification),
        ] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.revalidateMetadata() }
            }
            lifecycleObservers.append((center, observer))
        }
    }

    private func ejectWithRetry(deviceID: String) async throws {
        var lastError: Error = OpticalDiscError.ejectFailed("The drive refused to eject.")
        for attempt in 0..<3 {
            if attempt > 0 {
                try await Task.sleep(for: .milliseconds(250 * attempt))
            }
            do {
                try await ejector.eject(deviceID: deviceID)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    public func setImporting(_ importing: Bool, discID: DiscIdentifier) {
        if importing {
            importingDiscIDs.insert(discID)
        } else {
            importingDiscIDs.remove(discID)
        }
        guard let index = discs.firstIndex(where: { $0.id == discID }) else { return }
        discs[index].status = importing ? .importing : .ready
    }

    public func selectMetadata(_ candidate: AudioCDMetadataCandidate, for discID: DiscIdentifier) {
        revalidateMetadata()
        applyMetadata(candidate, to: discID)
        revalidateMetadata()
    }

    private func makeDisc(_ descriptor: OpticalDiscDescriptor) -> AudioDisc? {
        let parsed = AudioCDTOCParser.parse(
            entries: descriptor.entries,
            leadOutSector: descriptor.leadOutSector
        )
        guard !parsed.isEmpty else { return nil }
        let rawID = MusicBrainzDiscID.calculate(
            entries: descriptor.entries,
            leadOutSector: descriptor.leadOutSector
        )
        let discID = DiscIdentifier(rawID)
        let albumTitle = descriptor.cdText.albumTitle ?? "Audio CD"
        let tracks = parsed.map { parsedTrack in
            let source = AudioCDSource(
                discID: discID,
                deviceID: descriptor.deviceID,
                trackNumber: parsedTrack.number,
                startSector: parsedTrack.startSector,
                endSector: parsedTrack.endSector
            )
            return AudioDiscTrack(
                discID: discID,
                number: parsedTrack.number,
                title: descriptor.cdText.trackTitles[parsedTrack.number]
                    ?? String(format: "Track %02d", parsedTrack.number),
                artist: descriptor.cdText.trackArtists[parsedTrack.number]
                    ?? descriptor.cdText.albumArtist
                    ?? "Unknown Artist",
                duration: parsedTrack.duration,
                startSector: parsedTrack.startSector,
                endSector: parsedTrack.endSector,
                source: source
            )
        }
        return AudioDisc(
            id: discID,
            title: albumTitle,
            albumArtist: descriptor.cdText.albumArtist,
            volumeURL: URL(fileURLWithPath: "/Volumes/\(descriptor.deviceID)"),
            tracks: tracks,
            originalMetadata: originalMetadataByDisc[discID]
        )
    }

    private func scheduleRefresh() {
        refreshGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func startObserving() {
        if let created = DASessionCreate(kCFAllocatorDefault) {
            session = created
            let context = Unmanaged.passUnretained(self).toOpaque()
            DARegisterDiskAppearedCallback(created, nil, songbirdDiskChanged, context)
            DARegisterDiskDisappearedCallback(created, nil, songbirdDiskChanged, context)
            DASessionSetDispatchQueue(created, arbitrationQueue)
        }
        let center = workspaceNotifications
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            workspaceObservers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            })
        }
    }

    private func postRemoval(ids: Set<DiscIdentifier>) {
        guard !ids.isEmpty else { return }
        NotificationCenter.default.post(
            name: .audioDiscRemoved,
            object: nil,
            userInfo: ["discIDs": ids.map(\.rawValue)]
        )
    }

    fileprivate func diskChanged() { scheduleRefresh() }

    private func loadMetadata(for discovered: [AudioDisc], generation: UInt64) async {
        for disc in discovered {
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            do {
                let candidates = try await metadataProvider.candidates(
                    for: metadataQuery(for: disc)
                )
                guard !Task.isCancelled, generation == refreshGeneration,
                      discs.contains(where: { $0.id == disc.id }) else { return }
                let now = clock()
                let usable = candidates.filter { isUsable($0, at: now) }
                metadataCandidates[disc.id] = usable.isEmpty ? nil : usable
                if let best = usable.first { applyMetadata(best, to: disc.id) }
                revalidateMetadata()
            } catch MusicBrainzError.disabled {
                return
            } catch {
                guard !Task.isCancelled, generation == refreshGeneration else { return }
                metadataCandidates[disc.id] = nil
                lastError = .metadataLookupFailed(error.localizedDescription)
                continue
            }
        }
    }

    private func metadataQuery(for disc: AudioDisc) -> AudioCDMetadataQuery {
        let knownArtists = Set(disc.tracks.map(\.artist).filter {
            !$0.isEmpty && $0.caseInsensitiveCompare("Unknown Artist") != .orderedSame
        })
        return AudioCDMetadataQuery(
            discID: disc.id.rawValue,
            albumTitle: disc.title,
            albumArtist: knownArtists.count == 1 ? knownArtists.first : nil,
            tracks: disc.tracks.map {
                .init(number: $0.number, duration: $0.duration)
            }
        )
    }

    private func isUsable(_ candidate: AudioCDMetadataCandidate, at now: DiscogsFetchStamp?) -> Bool {
        if let evidence = candidate.discogsEvidence { return evidence.isFresh(at: now) }
        return !candidate.id.hasPrefix("discogs:")
    }

    private func applyMetadata(_ candidate: AudioCDMetadataCandidate, to discID: DiscIdentifier) {
        guard isUsable(candidate, at: clock()) else { return }
        guard let index = discs.firstIndex(where: { $0.id == discID }) else { return }
        let old = discs[index]
        let metadataByNumber = Dictionary(uniqueKeysWithValues: candidate.tracks.map { ($0.number, $0) })
        // Fill gaps from original CD-Text/defaults, never from a prior provider acquisition.
        let tracks = old.restoringOriginalMetadata().tracks.map { track in
            guard let metadata = metadataByNumber[track.number] else { return track }
            return AudioDiscTrack(
                discID: track.discID,
                number: track.number,
                title: metadata.title,
                artist: metadata.artist,
                duration: track.duration,
                startSector: track.startSector,
                endSector: track.endSector,
                source: track.source,
                fileURL: track.fileURL
            )
        }
        discs[index] = AudioDisc(
            id: old.id,
            title: candidate.title,
            albumArtist: candidate.artist,
            year: candidate.date.flatMap { Self.releaseYear(from: $0) },
            volumeURL: old.volumeURL,
            tracks: tracks,
            artworkURL: candidate.artworkURL,
            status: old.status,
            discogsEvidence: candidate.discogsEvidence,
            originalMetadata: originalMetadataByDisc[discID] ?? old.originalMetadata
        )
    }

    private static func releaseYear(from date: String) -> Int? {
        let prefix = date.prefix(4)
        guard prefix.count == 4, let year = Int(prefix), year > 0 else { return nil }
        return year
    }

    private static func defaultMetadataProvider() -> any AudioCDMetadataProviding {
        let contact = (Bundle.main.object(forInfoDictionaryKey: "SongbirdMetadataContactURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let musicBrainz = MusicBrainzCDMetadataClient(contact: contact)
        let discogs = DiscogsAudioCDMetadataProvider(
            client: DiscogsClient(tokenProvider: { try await DiscogsKeychain.load() })
        )
        return MusicBrainzDiscogsMetadataProvider(
            musicBrainz: musicBrainz,
            discogs: discogs
        )
    }
}

private func songbirdDiskChanged(_ disk: DADisk, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let service = Unmanaged<OpticalDiscService>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in service.diskChanged() }
}

public extension Notification.Name {
    static let audioDiscRemoved = Notification.Name("SongbirdAudioDiscRemoved")
    static let audioDiscWillEject = Notification.Name("SongbirdAudioDiscWillEject")
}
