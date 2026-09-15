import XCTest

@testable import SongbirdLib

final class DiscogsArtworkSearchCacheTests: XCTestCase {
    func testLegacyDateOnlyCacheJSONIsRejected() async throws {
        let fixture = try DiscogsHTTPFixture()
        let file = fixture.directory.appendingPathComponent("search.cache")
        try Data(#"{"artist\u001falbum\u001f0":{"savedAt":0,"candidates":[]}}"#.utf8).write(
            to: file)
        let clock = TestDiscogsClock()
        let cache = DiscogsArtworkSearchCache(fileURL: file, clock: { clock.sample() })
        let hit = await cache.candidates(for: .init(albumTitle: "Album", albumArtist: "Artist"))
        XCTAssertNil(hit)
        let envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(envelope["version"] as? Int, 2)
    }

    func testNewEnvelopeStampCannotMaskOldCandidateAcquisition() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock()
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() }, tokenProvider: { "synthetic" })
        let query = DiscogsArtworkSearchQuery(albumTitle: "Album", albumArtist: "Artist")
        let page = try await client.search(query, page: 1)
        clock.set(TestDiscogsClock.stamp(18_000))
        let cache = DiscogsArtworkSearchCache(
            fileURL: fixture.directory.appendingPathComponent("cache"), clock: { clock.sample() })
        let accepted = await cache.store(
            page.candidates, for: query, fetches: [TestDiscogsClock.stamp(18_000)])
        XCTAssertFalse(accepted)
        let hit = await cache.candidates(for: query)
        XCTAssertNil(hit)
    }

    func testAcquiredPagesRoundTripWithoutRenewalAndFailedRefreshStaysMissing() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock()
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() }, tokenProvider: { "synthetic" })
        let url = fixture.directory.appendingPathComponent("search.cache")
        let cache = DiscogsArtworkSearchCache(
            fileURL: url, maximumAge: 60, clock: { clock.sample() })
        for title in ["Album", "empty"] {
            let query = DiscogsArtworkSearchQuery(albumTitle: title, albumArtist: "Artist")
            let page = try await client.search(query, page: 1)
            clock.set(TestDiscogsClock.stamp(30))
            await cache.store(
                Array(page.candidates.prefix(5)), for: query, fetches: [page.fetchedAt])
            let restored = DiscogsArtworkSearchCache(
                fileURL: url, maximumAge: 60, clock: { clock.sample() })
            let hit = await restored.candidates(for: query)
            XCTAssertEqual(hit?.fetches, [page.fetchedAt])
            XCTAssertEqual(hit?.value, Array(page.candidates.prefix(5)))
            clock.set(TestDiscogsClock.stamp(18_000))
            let expired = await restored.candidates(for: query)
            XCTAssertNil(expired)
            do {
                _ = try await client.search(
                    .init(albumTitle: "status-503", albumArtist: ""), page: 1)
                XCTFail("Expected server error")
            } catch DiscogsError.serverUnavailable {}
            let afterFailure = await restored.candidates(for: query)
            XCTAssertNil(afterFailure)
            clock.set(TestDiscogsClock.stamp())
        }
    }

    func testConfiguredTTLIsCapped() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = TestDiscogsClock()
        let cache = DiscogsArtworkSearchCache(
            fileURL: url, maximumAge: 30 * 24 * 60 * 60, clock: { clock.sample() })
        let query = DiscogsArtworkSearchQuery(albumTitle: "Album", albumArtist: "Artist")
        await cache.store([], for: query, fetches: [TestDiscogsClock.stamp()])
        clock.set(TestDiscogsClock.stamp(18_000))
        let result = await cache.candidates(for: query)
        XCTAssertNil(result)
    }

    func testCacheExpiresAtBoundary() async {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("discogs-boundary-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let clock = TestDiscogsClock()
        let cache = DiscogsArtworkSearchCache(
            fileURL: fileURL, maximumAge: 60, clock: { clock.sample() })
        let query = DiscogsArtworkSearchQuery(
            albumTitle: "Album",
            albumArtist: "Artist"
        )
        await cache.store([], for: query, fetches: [TestDiscogsClock.stamp()])

        clock.set(TestDiscogsClock.stamp(60))
        let result = await cache.candidates(for: query)

        XCTAssertNil(result)
    }
    func testFutureDatedCacheEntryIsRejected() async {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("discogs-future-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let clock = TestDiscogsClock()
        let cache = DiscogsArtworkSearchCache(
            fileURL: fileURL, maximumAge: 60, clock: { clock.sample() })
        let query = DiscogsArtworkSearchQuery(
            albumTitle: "Album",
            albumArtist: "Artist"
        )
        await cache.store([], for: query, fetches: [TestDiscogsClock.stamp()])

        clock.set(TestDiscogsClock.stamp(-1))
        let result = await cache.candidates(for: query)

        XCTAssertNil(result)
    }

    func testStoresEmptyAndNonemptyResultsForResume() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-discogs-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let clock = TestDiscogsClock()
        let cache = DiscogsArtworkSearchCache(fileURL: fileURL, clock: { clock.sample() })
        let query = DiscogsArtworkSearchQuery(
            albumTitle: "Touch",
            albumArtist: "Yuji Ohno",
            year: 1981
        )
        let candidate = DiscogsArtworkCandidate(
            id: 42,
            title: "Touch",
            artist: "Yuji Ohno",
            year: 1981,
            country: "Japan",
            formats: ["LP"],
            genres: ["Jazz"],
            styles: ["Fusion"],
            thumbnailURL: URL(string: "https://example.com/thumb.jpg"),
            imageURL: URL(string: "https://example.com/cover.jpg")!,
            sourcePageURL: URL(string: "https://example.com/release/42")!,
            fetchedAt: TestDiscogsClock.stamp()
        )

        await cache.store([candidate], for: query, fetches: [candidate.fetchedAt])
        let restored = await cache.candidates(for: query)
        XCTAssertEqual(restored?.value, [candidate])

        let emptyQuery = DiscogsArtworkSearchQuery(
            albumTitle: "No Match",
            albumArtist: "Nobody"
        )
        await cache.store([], for: emptyQuery, fetches: [TestDiscogsClock.stamp()])
        let restoredEmpty = await cache.candidates(for: emptyQuery)
        XCTAssertEqual(restoredEmpty?.value, [])
    }

    func testExpiredResultsAreRetried() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-discogs-cache-expiry-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let clock = TestDiscogsClock()
        let cache = DiscogsArtworkSearchCache(
            fileURL: fileURL, maximumAge: 60, clock: { clock.sample() })
        let query = DiscogsArtworkSearchQuery(albumTitle: "Album", albumArtist: "Artist")

        await cache.store([], for: query, fetches: [TestDiscogsClock.stamp()])

        clock.set(TestDiscogsClock.stamp(61))
        let expired = await cache.candidates(for: query)
        XCTAssertNil(expired)
    }
}
