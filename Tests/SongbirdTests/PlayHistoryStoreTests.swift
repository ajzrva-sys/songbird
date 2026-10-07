import XCTest
@testable import SongbirdLib

@MainActor
final class PlayHistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "PlayHistoryStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removeObject(forKey: PlayHistoryStore.storageKey)
    }

    override func tearDown() {
        defaults.removeObject(forKey: PlayHistoryStore.storageKey)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRecordInsertsNewestFirstAndPersists() {
        let store = PlayHistoryStore(defaults: defaults)
        let older = Track(path: "/music/a.mp3", title: "Older", artist: "A", album: "Album A")
        let newer = Track(path: "/music/b.mp3", title: "Newer", artist: "B", album: "Album B")
        older.duration = 120
        newer.duration = 200

        store.record(track: older, playedAt: Date(timeIntervalSince1970: 1_000))
        store.record(track: newer, playedAt: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(store.items.map(\.title), ["Newer", "Older"])
        XCTAssertEqual(store.recentTrackIDs, [newer.id, older.id])

        let reloaded = PlayHistoryStore(defaults: defaults)
        XCTAssertEqual(reloaded.items.map(\.title), ["Newer", "Older"])
        XCTAssertEqual(reloaded.items.first?.trackID, newer.id)
    }

    func testClearAndRemove() {
        let store = PlayHistoryStore(defaults: defaults)
        let track = Track(path: "/music/c.mp3", title: "Keep", artist: "C", album: "Album C")
        store.record(track: track)
        let id = try? XCTUnwrap(store.items.first?.id)
        store.remove(id: id ?? UUID())
        XCTAssertTrue(store.items.isEmpty)

        store.record(track: track)
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(PlayHistoryStore(defaults: defaults).items.isEmpty)
    }

    func testCapKeepsNewestItems() {
        let store = PlayHistoryStore(defaults: defaults)
        for index in 0..<(PlayHistoryStore.maxItems + 5) {
            let track = Track(path: "/music/\(index).mp3", title: "T\(index)")
            store.record(track: track, playedAt: Date(timeIntervalSince1970: TimeInterval(index)))
        }
        XCTAssertEqual(store.items.count, PlayHistoryStore.maxItems)
        XCTAssertEqual(store.items.first?.title, "T\(PlayHistoryStore.maxItems + 4)")
    }

    func testSeedFromLibraryUsesLastPlayedWhenStoreEmpty() {
        let store = PlayHistoryStore(defaults: defaults)
        let seeded = PlayHistorySeed(
            trackID: UUID(),
            title: "Seeded",
            artist: "S",
            album: "Seed",
            lastPlayed: Date(timeIntervalSince1970: 5_000),
            duration: 180
        )
        let unplayed = PlayHistorySeed(
            trackID: UUID(),
            title: "Never",
            artist: "N",
            album: "None",
            lastPlayed: nil,
            duration: 100
        )

        store.seedFromLibraryIfNeeded([unplayed, seeded])
        XCTAssertEqual(store.items.map(\.title), ["Seeded"])

        let other = PlayHistorySeed(
            trackID: UUID(),
            title: "Other",
            artist: "O",
            album: "Other",
            lastPlayed: Date(timeIntervalSince1970: 9_000),
            duration: 90
        )
        store.seedFromLibraryIfNeeded([other])
        XCTAssertEqual(store.items.map(\.title), ["Seeded"], "Seed must not overwrite an existing log")
    }

    func testAudioCDTracksAreNotRecorded() {
        let store = PlayHistoryStore(defaults: defaults)
        let track = Track(path: "/dev/disk1", title: "CD Track")
        track.audioCDSource = AudioCDSource(
            discID: DiscIdentifier("disc"),
            deviceID: "disk1",
            trackNumber: 1,
            startSector: 0,
            endSector: 100
        )
        store.record(track: track)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testDestinationEncodingIncludesPlayHistory() {
        XCTAssertEqual(
            LibraryViewState.decodeDestination(LibraryViewState.encode(.playHistory)),
            .playHistory
        )
        XCTAssertEqual(LibraryViewState.encode(.playHistory), "playHistory")
    }
}
