import Foundation
import Testing
@testable import SongbirdLib

@Suite("Play qualification")
struct PlayQualificationTrackerTests {
    @Test("Thresholds follow long, short, and unknown duration policy")
    func thresholds() {
        #expect(PlayQualificationTracker.threshold(for: 120) == 30)
        #expect(PlayQualificationTracker.threshold(for: 30) == 15)
        #expect(PlayQualificationTracker.threshold(for: 0) == 30)
        #expect(PlayQualificationTracker.threshold(for: .nan) == 30)
    }

    @Test("Only accumulated unpaused monotonic time qualifies once")
    func accumulatedPlayback() {
        let id = UUID()
        var tracker = PlayQualificationTracker()
        tracker.begin(trackID: id, duration: 30, uptime: 100)

        let beforePause = tracker.advance(uptime: 109)
        #expect(!beforePause)
        tracker.pause(uptime: 110)
        let whilePaused = tracker.advance(uptime: 1_000)
        #expect(!whilePaused)
        tracker.resume(uptime: 2_000)
        let almost = tracker.advance(uptime: 2_004.9)
        let qualified = tracker.advance(uptime: 2_005)
        let repeated = tracker.advance(uptime: 3_000)
        #expect(!almost)
        #expect(qualified)
        #expect(!repeated)
        #expect(tracker.accumulatedPlayback == 15)
    }

    @Test("A new playback attempt resets qualification")
    func attemptsReset() {
        var tracker = PlayQualificationTracker()
        tracker.begin(trackID: UUID(), duration: 10, uptime: 0)
        let firstQualified = tracker.advance(uptime: 5)
        #expect(firstQualified)

        let next = UUID()
        tracker.begin(trackID: next, duration: 120, uptime: 10)
        #expect(tracker.trackID == next)
        #expect(!tracker.hasQualified)
        let almost = tracker.advance(uptime: 39.9)
        let qualified = tracker.advance(uptime: 40)
        #expect(!almost)
        #expect(qualified)
    }
}
