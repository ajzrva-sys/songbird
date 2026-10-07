import XCTest
@testable import SongbirdLib

@MainActor
final class QueueClearUndoTests: XCTestCase {
    func testClearPreservesCurrentAndRestoresDuplicateOccurrencesAndShuffleOrder() {
        let queue = PlaybackQueue()
        let current = Track(path: "/fixture/current.flac", title: "Current")
        let repeated = Track(path: "/fixture/repeated.flac", title: "Repeated")
        _ = queue.replace(with: [current, repeated, repeated, Track(path: "/fixture/end.flac")])
        queue.shuffleEnabled = true
        let before = queue.identitySnapshot()
        queue.clearUpcomingWithUndo()
        XCTAssertEqual(queue.currentEntry?.id, before.current?.entryID)
        XCTAssertTrue(queue.upcomingEntries.isEmpty)
        XCTAssertTrue(queue.canUndoClearUpcoming)
        XCTAssertTrue(queue.undoClearUpcoming())
        XCTAssertEqual(queue.identitySnapshot(), before)
        XCTAssertFalse(queue.undoClearUpcoming())
    }

    func testNewEntriesCannotBeOverwrittenByUndo() {
        let queue = PlaybackQueue()
        queue.enqueue([Track(path: "/fixture/old.flac")])
        queue.clearUpcomingWithUndo()
        let added = queue.enqueue([Track(path: "/fixture/new.flac")])
        XCTAssertFalse(queue.canUndoClearUpcoming)
        XCTAssertFalse(queue.undoClearUpcoming())
        XCTAssertEqual(queue.upcomingEntries.map(\.id), added.map(\.id))
    }

    func testPreferenceAndPlaybackChangesInvalidateUndo() {
        let queue = PlaybackQueue()
        for change in [0, 1, 2] {
            queue.enqueue([Track(path: "/fixture/\(change).flac")])
            queue.clearUpcomingWithUndo()
            switch change {
            case 0: queue.shuffleEnabled.toggle()
            case 1: queue.repeatMode = .all
            default: queue.invalidateClearUpcomingUndo()
            }
            XCTAssertFalse(queue.undoClearUpcoming())
        }
    }

    func testReadableMainHeightDoesNotRequireChangingStoredMiniHeight() {
        XCTAssertEqual(MainPlayerReadability.resolvedHeight(36), 72)
        XCTAssertEqual(MainPlayerReadability.resolvedHeight(96), 96)
        XCTAssertEqual(MainPlayerReadability.resolvedHeight(.nan), 72)
        XCTAssertEqual(NowPlayingLayoutSettings.defaultFaceplateHeight, 48)
        XCTAssertEqual(MainPlayerReadability.savedHeight(main: 0, legacy: 60), 60)
        XCTAssertEqual(MainPlayerReadability.savedHeight(main: 96, legacy: 60), 96)
        XCTAssertNotEqual(MainPlayerReadability.heightKey, NowPlayingLayoutSettings.faceplateHeightKey)
    }
}
