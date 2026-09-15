import XCTest
@testable import SongbirdLib

@MainActor
final class PlaybackEngineTests: XCTestCase {
    func testQueueAddAndNext() {
        let queue = PlaybackQueue()
        let t1 = Track(path: "/fake/1.mp3", title: "One")
        let t2 = Track(path: "/fake/2.mp3", title: "Two")
        queue.enqueue([t1, t2])
        XCTAssertEqual(queue.upcomingTracks.count, 2)
        let next = queue.next()
        XCTAssertEqual(next?.title, "One")
        XCTAssertEqual(queue.upcomingTracks.count, 1)
    }

    func testQueueNextReturnsNilWhenEmpty() {
        let queue = PlaybackQueue()
        XCTAssertNil(queue.next())
    }

    func testQueuePrevious() {
        let queue = PlaybackQueue()
        let t1 = Track(path: "/fake/1.mp3", title: "One")
        let t2 = Track(path: "/fake/2.mp3", title: "Two")
        queue.enqueue([t1, t2])
        _ = queue.next()
        _ = queue.next()
        let prev = queue.previous()
        XCTAssertEqual(prev?.title, "One")
    }

    func testQueueClear() {
        let queue = PlaybackQueue()
        let t1 = Track(path: "/fake/1.mp3", title: "One")
        queue.enqueue([t1])
        _ = queue.next()
        queue.clear()
        XCTAssertNil(queue.currentTrack)
        XCTAssertTrue(queue.upcomingTracks.isEmpty)
    }

    func testPlaybackUsesFilesystemReturnedUnicodeSpelling() async {
        let stored = "/Volumes/music/Yelle/Pop Up/02 A cause des gar\u{00E7}ons.m4a"
        let actual = "/Volumes/music/Yelle/Pop Up/02 A cause des garc\u{0327}ons.m4a"
        let resolver = resolver(storedPaths: [stored: actual])
        let backend = PathRecordingBackend()
        let engine = PlaybackEngine(
            queue: PlaybackQueue(),
            backend: backend,
            pathResolver: resolver
        )

        guard case .success = await engine.playResolving(Track(path: stored)) else {
            return XCTFail("Expected playback to start")
        }
        XCTAssertEqual(backend.playedSource?.fileURL?.path, actual)
    }

    func testUnavailableVolumeDoesNotMutateQueueOrReachBackend() async {
        let stored = "/Volumes/music/Yuja Wang/Fantasia/17 Poeme.m4a"
        let backend = PathRecordingBackend()
        let resolver = FilesystemPathResolver(
            probe: { path in
                path == stored
                    ? .unavailable(.volumeNotMounted("/Volumes/music"))
                    : .missing
            },
            directoryContents: { _ in .success([]) }
        )
        let queue = PlaybackQueue()
        let original = Track(path: "/tmp/original.m4a")
        queue.setCurrentTrack(original)
        let engine = PlaybackEngine(queue: queue, backend: backend, pathResolver: resolver)

        guard case .failure(let error) = await engine.playResolving(Track(path: stored)) else {
            return XCTFail("Expected an unavailable-volume error")
        }
        XCTAssertEqual(
            error,
            .volumeUnavailable("Library volume is unavailable: /Volumes/music")
        )
        XCTAssertEqual(queue.currentTrack?.id, original.id)
        XCTAssertNil(backend.playedSource)
    }

    func testAsyncPlaybackCancelsAStaleResolutionBeforeQueueCommit() async {
        let firstPath = "/Volumes/music/first.m4a"
        let secondPath = "/Volumes/music/second.m4a"
        let probe = BlockingPlaybackProbe(blockedPath: firstPath)
        let resolver = FilesystemPathResolver(
            probe: { probe.resolve($0) },
            directoryContents: { _ in .success([]) }
        )
        let backend = PathRecordingBackend()
        let queue = PlaybackQueue()
        let engine = PlaybackEngine(queue: queue, backend: backend, pathResolver: resolver)
        let first = Track(path: firstPath)
        let second = Track(path: secondPath)
        let firstTask = Task {
            await engine.playResolving(first) { queue.setCurrentTrack(first) }
        }
        for _ in 0..<100 where !probe.didStart {
            await Task.yield()
        }
        XCTAssertTrue(probe.didStart)

        guard case .success = await engine.playResolving(second, committing: {
            queue.setCurrentTrack(second)
        }) else {
            probe.release()
            return XCTFail("Expected the newer request to start")
        }
        probe.release()
        guard case .failure(let firstError) = await firstTask.value else {
            return XCTFail("Expected the stale request to be cancelled")
        }

        XCTAssertEqual(firstError, .cancelled)
        XCTAssertEqual(queue.currentTrack?.id, second.id)
        XCTAssertEqual(backend.playedSource?.fileURL?.path, secondPath)
    }

    func testResumePrefersStableTrackIDAfterPathRename() async {
        let defaults = UserDefaults.standard
        let previousResume = defaults.object(forKey: PlaybackSettings.resumeOnLaunchKey)
        let previousID = defaults.object(forKey: PlaybackSettings.lastTrackIDKey)
        let previousPath = defaults.object(forKey: PlaybackSettings.lastTrackPathKey)
        defer {
            restore(previousResume, key: PlaybackSettings.resumeOnLaunchKey)
            restore(previousID, key: PlaybackSettings.lastTrackIDKey)
            restore(previousPath, key: PlaybackSettings.lastTrackPathKey)
        }
        let renamed = Track(path: "/Volumes/music/Album/Renamed.m4a")
        defaults.set(true, forKey: PlaybackSettings.resumeOnLaunchKey)
        defaults.set(renamed.id.uuidString, forKey: PlaybackSettings.lastTrackIDKey)
        defaults.set("/Volumes/music/Album/Old Name.m4a", forKey: PlaybackSettings.lastTrackPathKey)
        let resolver = FilesystemPathResolver(
            probe: { _ in .exists },
            directoryContents: { _ in .success([]) }
        )
        let backend = PathRecordingBackend()
        let engine = PlaybackEngine(
            queue: PlaybackQueue(),
            backend: backend,
            pathResolver: resolver
        )

        engine.resumeLastTrackIfNeeded(from: [renamed])
        for _ in 0..<50 where backend.playedSource == nil {
            await Task.yield()
        }

        XCTAssertEqual(engine.queue.currentTrack?.id, renamed.id)
        XCTAssertEqual(backend.playedSource?.fileURL?.path, renamed.path)
    }

    func testGaplessPreloadRetainsResolvedFilesystemSource() async {
        let firstStored = "/Volumes/music/Album/01 Caf\u{00E9}.m4a"
        let firstActual = "/Volumes/music/Album/01 Cafe\u{0301}.m4a"
        let nextStored = "/Volumes/music/Album/02 Po\u{00E8}me.m4a"
        let nextActual = "/Volumes/music/Album/02 Poe\u{0300}me.m4a"
        let resolver = resolver(storedPaths: [
            firstStored: firstActual,
            nextStored: nextActual,
        ])
        let backend = PathRecordingBackend()
        let queue = PlaybackQueue()
        let engine = PlaybackEngine(queue: queue, backend: backend, pathResolver: resolver)
        let first = Track(path: firstStored)
        let next = Track(path: nextStored)

        guard case .success = engine.play(first, committing: {
            _ = queue.replace(with: [first, next])
        }) else {
            return XCTFail("Expected playback to start")
        }
        for _ in 0..<50 where backend.nextSource == nil {
            await Task.yield()
        }
        XCTAssertEqual(backend.nextSource?.fileURL?.path, nextActual)

        backend.onTrackBegan?(backend.playedSource)
        await Task.yield()
        backend.onTrackBegan?(backend.nextSource)
        await Task.yield()
        XCTAssertEqual(queue.currentTrack?.id, next.id)
    }

    private func resolver(storedPaths: [String: String]) -> FilesystemPathResolver {
        let actualPaths = Set(storedPaths.values)
        return FilesystemPathResolver(
            probe: { path in
                if actualPaths.contains(path) { return .exists }
                if path == "/" || path == "/Volumes" || path == "/Volumes/music" || path == "/Volumes/music/Album" || path == "/Volumes/music/Yelle" || path == "/Volumes/music/Yelle/Pop Up" {
                    return .exists
                }
                return .missing
            },
            directoryContents: { directory in
                let entries = storedPaths.values
                    .map(URL.init(fileURLWithPath:))
                    .filter { $0.deletingLastPathComponent().path == directory.path }
                return .success(entries)
            }
        )
    }

    private func restore(_ value: Any?, key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

@MainActor
private final class PathRecordingBackend: PlayerBackend {
    var position: TimeInterval = 0
    var duration: TimeInterval = 1
    var isPlaying = false
    var isPaused = false
    var volume: Double = 1
    var onTrackBegan: ((AudioSource?) -> Void)?
    var onTrackFinished: (() -> Void)?
    var onError: ((String) -> Void)?
    var playedSource: AudioSource?
    var nextSource: AudioSource?

    func prepare() throws {}
    func shutdown() {}
    func play(_ source: AudioSource, durationHint: TimeInterval) throws {
        playedSource = source
        isPlaying = true
    }
    func pause() { isPaused = true }
    func resume() { isPaused = false }
    func stop() { isPlaying = false }
    func seek(to time: TimeInterval) { position = time }
    func setNextSource(_ source: AudioSource?, crossfadeDuration: TimeInterval) {
        nextSource = source
    }
}

private final class BlockingPlaybackProbe: @unchecked Sendable {
    private let condition = NSCondition()
    private let blockedPath: String
    private var started = false
    private var released = false

    init(blockedPath: String) {
        self.blockedPath = blockedPath
    }

    var didStart: Bool {
        condition.lock()
        defer { condition.unlock() }
        return started
    }

    func resolve(_ path: String) -> FilesystemPathResolver.ProbeResult {
        guard path == blockedPath else { return .exists }
        condition.lock()
        started = true
        condition.broadcast()
        while !released { condition.wait() }
        condition.unlock()
        return .exists
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}
