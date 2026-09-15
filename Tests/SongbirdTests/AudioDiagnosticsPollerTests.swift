import XCTest
@testable import SongbirdLib

@MainActor
final class AudioDiagnosticsPollerTests: XCTestCase {
    func testPollerStartsImmediatelyAndStopsCleanly() async throws {
        let poller = AudioDiagnosticsPoller()
        var suppliedFrames: UInt64 = 0
        poller.start(interval: 0.01) {
            suppliedFrames += 1
            var snapshot = AudioDiagnosticsSnapshot.zero
            snapshot.renderedFrames = suppliedFrames
            return snapshot
        }

        XCTAssertTrue(poller.isPolling)
        XCTAssertEqual(poller.snapshot.renderedFrames, 1)
        try await Task.sleep(for: .milliseconds(45))
        XCTAssertGreaterThan(poller.pollCount, 1)

        poller.stop()
        let stoppedCount = poller.pollCount
        XCTAssertFalse(poller.isPolling)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(poller.pollCount, stoppedCount)
    }
}
