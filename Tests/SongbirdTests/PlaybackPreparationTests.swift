import Foundation
import XCTest
@testable import SongbirdLib

@MainActor
final class PlaybackPreparationTests: XCTestCase {
    func testSlowPreparationDoesNotDelayMainActorHeartbeat() async throws {
        let source = AudioSource.file(URL(fileURLWithPath: "/synthetic/slow.wav"))
        let start = ContinuousClock.now
        let heartbeat = Task { @MainActor in
            start.duration(to: .now)
        }
        let prepared = try await NativeStreamPreparation.prepare(
            source, sampleRate: 48_000, startAt: 0,
            factory: { source, _, _ in
                Thread.sleep(forTimeInterval: 0.25)
                return RenderStream(session: PreparationFixtureSource(source: source))
            }
        )
        let delay = await heartbeat.value
        let milliseconds = Double(delay.components.seconds) * 1000
            + Double(delay.components.attoseconds) / 1e15
        print("PERFORMANCE: 250ms simulated storage read; main-actor heartbeat \(milliseconds)ms")
        XCTAssertLessThan(milliseconds, 100)
        XCTAssertEqual(prepared.source, source)
    }
    func testNewerPlayWinsAfterOlderPreparationFinishes() async {
        let (engine, backend) = makeEngine()
        defer { engine.stop() }
        let first = Track(path: "/synthetic/first.wav")
        let second = Track(path: "/synthetic/second.wav")
        backend.blockedSource = .file(URL(fileURLWithPath: first.path))
        var staleCommitted = false
        let task = Task { await engine.playResolving(first) { staleCommitted = true } }
        await waitUntil { backend.waiter != nil }
        guard case .success = await engine.playResolving(second) else {
            backend.release()
            return XCTFail("Newer request should start")
        }
        backend.release()
        guard case .failure(.cancelled) = await task.value else { return XCTFail("Stale play accepted") }
        XCTAssertFalse(staleCommitted)
        XCTAssertEqual(engine.queue.currentTrack?.id, second.id)
        XCTAssertEqual(backend.played, [.file(URL(fileURLWithPath: second.path))])
    }

    func testStopCancelsPendingPreparationBeforeQueueCommit() async {
        let (engine, backend) = makeEngine()
        let track = Track(path: "/synthetic/blocked.wav")
        backend.blockedSource = .file(URL(fileURLWithPath: track.path))
        var committed = false
        let task = Task { await engine.playResolving(track) { committed = true } }
        await waitUntil { backend.waiter != nil }
        engine.stop()
        backend.release()
        guard case .failure(.cancelled) = await task.value else { return XCTFail("Stopped play accepted") }
        XCTAssertFalse(committed)
        XCTAssertTrue(backend.played.isEmpty)
        XCTAssertEqual(engine.status, .stopped)
    }

    func testFailedPreparationPreservesPlayingTrackAndQueue() async {
        let (engine, backend) = makeEngine()
        defer { engine.stop() }
        let first = Track(path: "/synthetic/first.wav")
        _ = await engine.playResolving(first)
        backend.failPreparation = true
        var committed = false
        guard case .failure(.backendRejected) = await engine.playResolving(
            Track(path: "/synthetic/broken.wav"), committing: { committed = true }
        ) else { return XCTFail("Expected preparation failure") }
        XCTAssertFalse(committed)
        XCTAssertEqual(engine.queue.currentTrack?.id, first.id)
        XCTAssertTrue(backend.isPlaying)
        XCTAssertEqual(backend.stops, 0)
    }

    func testPreloadFailureLeavesActiveAudioPlaying() async {
        let (engine, backend) = makeEngine()
        defer { engine.stop() }
        let first = Track(path: "/synthetic/first.wav")
        let next = Track(path: "/synthetic/next.wav")
        backend.blockedSource = .file(URL(fileURLWithPath: next.path))
        _ = await engine.playResolving(first) { _ = engine.queue.replace(with: [first, next]) }
        await waitUntil { backend.waiter != nil }
        XCTAssertEqual(engine.queue.currentTrack?.id, first.id)
        XCTAssertTrue(backend.isPlaying)
        backend.failPreparation = true
        let clears = backend.clearNextCount
        backend.release()
        await waitUntil { backend.clearNextCount > clears }
        XCTAssertEqual(backend.stops, 0)
        XCTAssertTrue(backend.isPlaying)
        XCTAssertNil(backend.nextSource)
    }

    func testStoppedPreloadCannotInstallItsLateResult() async {
        let (engine, backend) = makeEngine()
        let first = Track(path: "/synthetic/first.wav")
        let next = Track(path: "/synthetic/next.wav")
        backend.blockedSource = .file(URL(fileURLWithPath: next.path))
        _ = await engine.playResolving(first) { _ = engine.queue.replace(with: [first, next]) }
        await waitUntil { backend.waiter != nil }
        engine.stop()
        backend.release()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(backend.nextSource)
        XCTAssertEqual(engine.status, .stopped)
    }

    func testSeekPreservesPauseAndDoesNotResurrectAfterStop() async {
        let (engine, backend) = makeEngine()
        let track = Track(path: "/synthetic/first.wav")
        _ = await engine.playResolving(track)
        engine.pause()
        engine.seekTo(12)
        await waitUntil { backend.seekPositions == [12] }
        XCTAssertEqual(engine.status, .paused)
        XCTAssertTrue(backend.isPaused)
        backend.blockedSource = .file(URL(fileURLWithPath: track.path))
        engine.seekTo(30)
        await waitUntil { backend.waiter != nil }
        engine.stop()
        backend.release()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(backend.seekPositions, [12])
        XCTAssertEqual(engine.status, .stopped)
    }

    func testResumeStartPositionIsPreparedWithoutASecondSynchronousSeek() async {
        let (engine, backend) = makeEngine()
        defer { engine.stop() }
        _ = await engine.playResolving(Track(path: "/synthetic/resume.wav"), startAt: 25)
        XCTAssertEqual(backend.preparedPositions, [25])
        XCTAssertEqual(engine.position, 25)
        XCTAssertTrue(backend.seekPositions.isEmpty)
    }

    func testCancelledPreparationCleansUpOffMainActor() async throws {
        let source = AudioSource.file(URL(fileURLWithPath: "/synthetic/abandoned.wav"))
        let started = expectation(description: "factory started")
        let retired = expectation(description: "unused stream stopped off main")
        let gate = DispatchSemaphore(value: 0)
        let task = Task {
            try await NativeStreamPreparation.prepare(source, sampleRate: 48_000, startAt: 0) { source, _, _ in
                started.fulfill()
                gate.wait()
                return RenderStream(session: PreparationFixtureSource(source: source, onStop: {
                    XCTAssertFalse(Thread.isMainThread)
                    retired.fulfill()
                }))
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        gate.signal()
        do { _ = try await task.value; XCTFail("Cancelled preparation returned") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        await fulfillment(of: [retired], timeout: 2)
    }

    func testRetiredSlowDecoderDoesNotBlockMainActor() async {
        let retired = expectation(description: "slow stop completed")
        let source = PreparationFixtureSource(source: .file(URL(fileURLWithPath: "/synthetic/retired.wav")), onStop: {
            XCTAssertFalse(Thread.isMainThread)
            Thread.sleep(forTimeInterval: 0.25)
            retired.fulfill()
        })
        let start = ContinuousClock.now
        NativeStreamCleanup.retire(RenderStream(session: source))
        let delay = start.duration(to: .now)
        XCTAssertLessThan(delay, .milliseconds(100))
        await fulfillment(of: [retired], timeout: 2)
    }

    func testNativePreparationPrimesAndSeeksCommittedFixtures() async throws {
        for name in ["metadata-artwork-seek.flac", "tone-44100-mono-16.wav"] {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Fixtures/Generated/" + name)
            let prepared = try await NativeStreamPreparation.prepare(.file(url), sampleRate: 48_000, startAt: 0.01)
            let stream = try prepared.consume()
            XCTAssertEqual(stream.session.source, .file(url))
            XCTAssertGreaterThan(stream.session.ringBuffer.availableFrames, 0)
            XCTAssertEqual(prepared.startAt, 0.01)
            XCTAssertThrowsError(try prepared.consume())
            NativeStreamCleanup.retire(stream)
        }
    }

    func testNativeDecoderCanRetireImmediatelyAfterStartingItsWorker() async throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Generated")
        try await Task.detached {
            for name in ["tone-192000-stereo-24.flac", "tone-192000-mono-16.wav"] {
                for _ in 0..<20 {
                    let session = try NativeDecoderSession(url: fixtures.appendingPathComponent(name), sampleRate: 48_000)
                    session.start()
                    session.stop()
                    // A second stop must remain safe after the worker and handles retire.
                    session.stop()
                }
            }
        }.value
    }

    private func makeEngine() -> (PlaybackEngine, PreparingFixtureBackend) {
        let backend = PreparingFixtureBackend()
        let resolver = FilesystemPathResolver(probe: { _ in .exists }, directoryContents: { _ in .success([]) })
        return (PlaybackEngine(queue: PlaybackQueue(), backend: backend, pathResolver: resolver), backend)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for playback transition")
    }

}

private final class PreparationFixtureSource: RenderPCMSource {
    let source: AudioSource
    let ringBuffer = RingBuffer(channels: 2, seconds: 1, sampleRate: 48_000)
    let totalOutputFrames: Int64 = 48_000
    let minimumPlaybackFrames = 0
    let duration: TimeInterval = 1
    var state: PCMSourceState { .idle }
    var decodeError: String? { nil }
    var decodeLatency: AudioLatencyStatistics { .zero }
    var conversionLatency: AudioLatencyStatistics { .zero }
    private let onStop: @Sendable () -> Void
    init(source: AudioSource, onStop: @escaping @Sendable () -> Void = {}) {
        self.source = source
        self.onStop = onStop
    }
    func prime(minimumFrames: Int) throws {}
    func start() {}
    func stop() { onStop() }
    func seek(to seconds: TimeInterval) throws {}
    func resetDiagnostics() {}
}

private struct FixturePreparedSource: PreparedAudioSource {
    let source: AudioSource
    let position: TimeInterval
}

@MainActor
private final class PreparingFixtureBackend: SourcePreparingPlayerBackend {
    var position: TimeInterval = 0
    var duration: TimeInterval = 120
    var isPlaying = false
    var isPaused = false
    var volume: Double = 1
    var onTrackBegan: ((AudioSource?) -> Void)?
    var onTrackFinished: (() -> Void)?
    var onError: ((String) -> Void)?
    var blockedSource: AudioSource?
    var waiter: CheckedContinuation<Void, Never>?
    var failPreparation = false
    var played: [AudioSource] = []
    var preparedPositions: [TimeInterval] = []
    var seekPositions: [TimeInterval] = []
    var nextSource: AudioSource?
    var stops = 0
    var clearNextCount = 0

    func prepare() throws {}
    func shutdown() {}
    func prepareSource(_ source: AudioSource, startAt: TimeInterval) async throws -> any PreparedAudioSource {
        preparedPositions.append(startAt)
        if source == blockedSource { await withCheckedContinuation { waiter = $0 } }
        if failPreparation { throw NativeAudioError.closed }
        return FixturePreparedSource(source: source, position: startAt)
    }
    func release() { blockedSource = nil; waiter?.resume(); waiter = nil }
    func playPrepared(_ source: any PreparedAudioSource, durationHint: TimeInterval) throws {
        played.append(source.source)
        isPlaying = true
        isPaused = false
    }
    func seekPrepared(_ source: any PreparedAudioSource) throws {
        seekPositions.append((source as! FixturePreparedSource).position)
    }
    func hasPreparedNext(_ source: AudioSource) -> Bool { nextSource == source }
    func setNextPrepared(_ source: any PreparedAudioSource, crossfadeDuration: TimeInterval) throws {
        nextSource = source.source
    }
    func play(_ source: AudioSource, durationHint: TimeInterval) throws { XCTFail("Used synchronous play") }
    func seek(to time: TimeInterval) { XCTFail("Used synchronous seek") }
    func setNextSource(_ source: AudioSource?, crossfadeDuration: TimeInterval) {
        if source == nil { clearNextCount += 1 }
        nextSource = source
    }
    func pause() { isPaused = true }
    func resume() { isPaused = false }
    func stop() { stops += 1; isPlaying = false; isPaused = false }
}
