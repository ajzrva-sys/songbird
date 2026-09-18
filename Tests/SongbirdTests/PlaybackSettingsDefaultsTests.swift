import XCTest
@testable import SongbirdLib

@MainActor
final class PlaybackSettingsDefaultsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: PlaybackSettings.resumeOnLaunchKey)
        defaults.removeObject(forKey: PlaybackSettings.rememberPositionKey)
        defaults.removeObject(forKey: PlaybackSettings.lastTrackPositionKey)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: PlaybackSettings.resumeOnLaunchKey)
        defaults.removeObject(forKey: PlaybackSettings.rememberPositionKey)
        defaults.removeObject(forKey: PlaybackSettings.lastTrackPositionKey)
        super.tearDown()
    }

    func testResumeAndRememberPositionDefaultOn() {
        XCTAssertTrue(PlaybackSettings.resumeOnLaunch)
        XCTAssertTrue(PlaybackSettings.rememberPosition)
    }

    func testExplicitFalseOverridesDefault() {
        PlaybackSettings.resumeOnLaunch = false
        PlaybackSettings.rememberPosition = false
        XCTAssertFalse(PlaybackSettings.resumeOnLaunch)
        XCTAssertFalse(PlaybackSettings.rememberPosition)
    }

    func testResumeUsesSavedMidTrackPosition() async {
        let defaults = UserDefaults.standard
        let track = Track(path: "/Volumes/music/Album/01 浴佛偈.m4a", title: "01. 浴佛偈")
        defaults.set(true, forKey: PlaybackSettings.resumeOnLaunchKey)
        defaults.set(true, forKey: PlaybackSettings.rememberPositionKey)
        defaults.set(track.id.uuidString, forKey: PlaybackSettings.lastTrackIDKey)
        defaults.set(track.path, forKey: PlaybackSettings.lastTrackPathKey)
        defaults.set(33 * 60 + 14, forKey: PlaybackSettings.lastTrackPositionKey)

        let backend = PositionProbeBackend()
        let engine = PlaybackEngine(
            queue: PlaybackQueue(),
            backend: backend,
            pathResolver: FilesystemPathResolver(
                probe: { _ in .exists },
                directoryContents: { _ in .success([]) }
            )
        )

        engine.resumeLastTrackIfNeeded(from: [track])
        for _ in 0..<50 where backend.playedSource == nil {
            await Task.yield()
        }

        XCTAssertEqual(engine.queue.currentTrack?.id, track.id)
        XCTAssertNotNil(backend.playedSource)
        XCTAssertEqual(engine.position, 33 * 60 + 14, accuracy: 1)
        XCTAssertEqual(backend.lastStartAt ?? -1, 33 * 60 + 14, accuracy: 1)
    }
}

@MainActor
private final class PositionProbeBackend: PlayerBackend {
    var position: TimeInterval = 0
    var duration: TimeInterval = 56 * 60 + 47
    var isPlaying = false
    var isPaused = false
    var volume: Double = 1
    var onTrackBegan: ((AudioSource?) -> Void)?
    var onTrackFinished: (() -> Void)?
    var onError: ((String) -> Void)?
    var playedSource: AudioSource?
    var nextSource: AudioSource?
    var lastStartAt: TimeInterval?

    func prepare() throws {}
    func shutdown() {}
    func play(_ source: AudioSource, durationHint: TimeInterval) throws {
        playedSource = source
        isPlaying = true
        onTrackBegan?(source)
    }
    func pause() { isPaused = true }
    func resume() { isPaused = false }
    func stop() { isPlaying = false }
    func seek(to time: TimeInterval) {
        position = time
        lastStartAt = time
    }
    func setNextSource(_ source: AudioSource?, crossfadeDuration: TimeInterval) {
        nextSource = source
    }
}
