import XCTest
import SwiftData
@testable import SongbirdLib

@MainActor
final class DiscogsYearFreshnessTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Album.self, Track.self, Artist.self, Playlist.self,
            AlbumFavorite.self, TrackFavorite.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    private func suggestion(_ album: Album) -> DiscogsYearSuggestion {
        DiscogsYearSuggestion(album: DiscogsArtworkAlbumTarget(album: album), year: 1999,
            evidence: DiscogsContentEvidence(releaseID: 42, fetches: [TestDiscogsClock.stamp()]))
    }
    func testExpiredYearsNeverSaveAndRollbackObservedValues() throws {
        for expireAtSave in [false, true] {
            let store = try container(); let context = store.mainContext
            let album = Album(title: "A", artist: "Artist")
            let track = Track(path: "/synthetic/a.wav", title: "A")
            context.insert(album); context.insert(track); album.tracks = [track]
            try context.save()
            var saves = 0
            XCTAssertThrowsError(try DiscogsYearApplier.apply([suggestion(album)], in: context,
                clock: {
                    TestDiscogsClock.stamp(!expireAtSave || track.year > 0 ? 18_000 : 0)
                }, save: { context in saves += 1; try context.save() })) {
                XCTAssertEqual($0 as? LibraryHealthMutationError, .remoteEvidenceExpired)
            }
            XCTAssertEqual(saves, 0)
            XCTAssertEqual(album.year, 0); XCTAssertEqual(track.year, 0)
            XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<Album>()).first?.year, 0)
        }
    }

    func testSaveFailureRestoresAlbumAndTrackInMemoryAndStore() throws {
        enum Failure: Error { case save }
        let store = try container(); let context = store.mainContext
        let album = Album(title: "A", artist: "Artist")
        let track = Track(path: "/synthetic/a.wav", title: "A")
        context.insert(album); context.insert(track); album.tracks = [track]
        try context.save()
        XCTAssertThrowsError(try DiscogsYearApplier.apply([suggestion(album)], in: context,
            clock: { TestDiscogsClock.stamp() }, save: { _ in throw Failure.save }))
        XCTAssertEqual(album.year, 0); XCTAssertEqual(track.year, 0)
        try context.save()
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<Album>()).first?.year, 0)
    }

    func testCacheOriginKeepsCanonicalAttributionAndStableAlbumSnapshot() async throws {
        struct Offline: DiscogsReviewClient {
            func search(_ query: DiscogsArtworkSearchQuery, page: Int) async throws -> DiscogsSearchPage {
                XCTFail("A cache-origin result must not need HTTP or credentials")
                throw DiscogsError.networkUnavailable
            }
            func downloadImage(from url: URL, evidence: DiscogsContentEvidence) async throws -> Data {
                XCTFail("Year lookup cannot download images")
                throw DiscogsError.imageDownloadFailed
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dependencies = DiscogsReviewDependencies(client: Offline(), cacheURL: directory.appendingPathComponent("cache.json"), clock: { TestDiscogsClock.stamp() })
        let query = DiscogsArtworkSearchQuery(albumTitle: "A", albumArtist: "Artist")
        let candidate = DiscogsArtworkCandidate(id: 42, title: "Remote", artist: "Artist", year: 1999,
            country: nil, formats: [], genres: [], styles: [], thumbnailURL: nil,
            imageURL: URL(string: "https://example.invalid/image")!,
            sourcePageURL: URL(string: "https://www.discogs.com/release/42")!, fetchedAt: TestDiscogsClock.stamp())
        try await dependencies.storeCandidates([candidate], for: query, fetches: [candidate.fetchedAt])
        let hit = try await dependencies.cachedCandidates(for: query)
        let cached = try XCTUnwrap(hit?.value.first)
        let album = Album(title: "Local", artist: "Artist")
        let result = MissingYearView.SearchResult(album: album, year: cached.year!, source: "cached", evidence: cached.evidence)
        album.title = "Changed later"
        XCTAssertEqual(result.album.title, "Local")
        XCTAssertEqual(result.sourcePageURL?.absoluteString, "https://www.discogs.com/release/42")
        XCTAssertEqual(result.evidence, candidate.evidence)
    }

    func testStableIDsMissingOnlyAndDuplicates() throws {
        let store = try container(); let context = store.mainContext
        let album = Album(title: "Same", artist: "Artist")
        let removed = Album(title: "Same", artist: "Artist")
        let filled = Album(title: "Filled", artist: "Artist", year: 2020)
        let missing = Track(path: "/synthetic/missing.wav", title: "Missing")
        let assigned = Track(path: "/synthetic/assigned.wav", title: "Assigned")
        assigned.year = 2000
        for value in [album, removed, filled] { context.insert(value) }
        context.insert(missing); context.insert(assigned); album.tracks = [missing, assigned]
        try context.save()
        let staleTarget = suggestion(removed)
        context.delete(removed); try context.save()
        let replacement = Album(title: "Same", artist: "Artist")
        context.insert(replacement); try context.save()
        let value = suggestion(album)
        let result = try DiscogsYearApplier.apply([value, value, staleTarget, suggestion(filled)], in: context,
            clock: { TestDiscogsClock.stamp() })
        XCTAssertEqual(result.appliedAlbums, 1)
        XCTAssertEqual(result.skippedAlbums, 3)
        XCTAssertEqual(album.year, 1999); XCTAssertEqual(missing.year, 1999)
        XCTAssertEqual(assigned.year, 2000); XCTAssertEqual(filled.year, 2020)
        XCTAssertEqual(replacement.year, 0)
        XCTAssertEqual(value.sourcePageURL?.absoluteString, "https://www.discogs.com/release/42")
    }
}
