import XCTest
@testable import SongbirdLib

@MainActor
final class PlaybackQueueShuffleTests: XCTestCase {
    func testPeekNextMatchesNextUnderShuffle() {
        let queue = PlaybackQueue()
        let tracks = (0..<20).map { Track(path: "/fake/\($0).mp3", title: "T\($0)") }
        queue.enqueue(tracks)
        queue.shuffleEnabled = true

        let peeked = queue.peekNext()
        XCTAssertNotNil(peeked)
        let next = queue.next()
        XCTAssertEqual(peeked?.id, next?.id)
    }

    func testPeekStableAcrossCallsUntilNext() {
        let queue = PlaybackQueue()
        queue.enqueue((0..<15).map { Track(path: "/fake/\($0).mp3", title: "T\($0)") })
        queue.shuffleEnabled = true
        let a = queue.peekNext()?.id
        let b = queue.peekNext()?.id
        XCTAssertEqual(a, b)
    }

    func testEnqueueNextPutsTrackAtFrontOfShuffle() {
        let queue = PlaybackQueue()
        let t1 = Track(path: "/fake/1.mp3", title: "One")
        let t2 = Track(path: "/fake/2.mp3", title: "Two")
        let t3 = Track(path: "/fake/3.mp3", title: "Three")
        queue.enqueue([t1, t2])
        queue.shuffleEnabled = true
        queue.enqueueNext(t3)
        XCTAssertEqual(queue.peekNext()?.id, t3.id)
        XCTAssertEqual(queue.next()?.id, t3.id)
    }

    func testEnqueueNextAlbumPreservesOrderWithShuffleOff() {
        let queue = PlaybackQueue()
        let existing = Track(path: "/fake/existing.mp3", title: "Existing")
        let album = (1...3).map { Track(path: "/fake/album-\($0).mp3", title: "Track \($0)") }
        queue.enqueue([existing])

        queue.enqueueNext(album)

        XCTAssertEqual(queue.upcomingTracks.map(\.id), album.map(\.id) + [existing.id])
        XCTAssertEqual((0..<3).compactMap { _ in queue.next()?.id }, album.map(\.id))
    }

    func testEnqueueNextAlbumPreservesOrderWithShuffleOn() {
        let queue = PlaybackQueue()
        let existing = Track(path: "/fake/existing.mp3", title: "Existing")
        let album = (1...3).map { Track(path: "/fake/shuffled-album-\($0).mp3", title: "Track \($0)") }
        queue.enqueue([existing])
        queue.shuffleEnabled = true

        queue.enqueueNext(album)

        XCTAssertTrue(queue.shuffleEnabled)
        XCTAssertEqual((0..<3).compactMap { _ in queue.next()?.id }, album.map(\.id))
    }

    func testPromoteRemovesFromUpcoming() {
        let queue = PlaybackQueue()
        let t1 = Track(path: "/fake/1.mp3", title: "One")
        let t2 = Track(path: "/fake/2.mp3", title: "Two")
        queue.enqueue([t1, t2])
        queue.shuffleEnabled = true
        _ = queue.promote(t2)
        XCTAssertEqual(queue.currentTrack?.id, t2.id)
        XCTAssertFalse(queue.upcomingTracks.contains(where: { $0.id == t2.id }))
        XCTAssertEqual(queue.peekNext()?.id, t1.id)
    }
}
