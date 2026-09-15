import XCTest
import SwiftData
@testable import SongbirdLib

@MainActor
final class DiscogsGenreFreshnessTests: XCTestCase {
    func testExpiryBeforeSaveRollsBackAllGenres() throws {
        let store = try ModelContainer(for: Album.self, Track.self, Artist.self, Playlist.self,
            AlbumFavorite.self, TrackFavorite.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = store.mainContext
        let album = Album(title: "Album", artist: "Artist")
        let track = Track(path: "/synthetic/a.wav", title: "A")
        context.insert(album); context.insert(track); album.tracks = [track]
        try context.save()
        let suggestion = DiscogsGenreAlbumSuggestion(album: DiscogsArtworkAlbumTarget(album: album), genre: "Jazz",
            evidence: DiscogsContentEvidence(releaseID: 1, fetches: [TestDiscogsClock.stamp()]))
        var sawAssignment = false
        XCTAssertThrowsError(try DiscogsGenreBulkApplier.apply([suggestion], in: context, clock: {
            if track.genre == "Jazz" { sawAssignment = true; return TestDiscogsClock.stamp(18_000) }
            return TestDiscogsClock.stamp()
        })) {
            XCTAssertEqual($0 as? LibraryHealthMutationError, .remoteEvidenceExpired)
        }
        XCTAssertTrue(sawAssignment, "The final check must run after assignments, before save")
        XCTAssertTrue(GenreMetadata.isMissing(track.genre))
        XCTAssertTrue(try ModelContext(store).fetch(FetchDescriptor<Track>()).allSatisfy { GenreMetadata.isMissing($0.genre) })
    }

    func testExpiredDuplicateStillRejectsWholeBatch() throws {
        let store = try ModelContainer(for: Album.self, Track.self, Artist.self, Playlist.self,
            AlbumFavorite.self, TrackFavorite.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = store.mainContext
        let album = Album(title: "Album", artist: "Artist")
        let track = Track(path: "/synthetic/a.wav", title: "A")
        context.insert(album); context.insert(track); album.tracks = [track]
        try context.save()
        let suggestions = [1.0, 0.0].map { offset in
            DiscogsGenreAlbumSuggestion(album: DiscogsArtworkAlbumTarget(album: album), genre: "Jazz",
                evidence: DiscogsContentEvidence(releaseID: 1, fetches: [TestDiscogsClock.stamp(offset)]))
        }
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(18_000)])
        XCTAssertThrowsError(try DiscogsGenreBulkApplier.apply(suggestions, in: context, clock: { clock.sample() })) {
            XCTAssertEqual($0 as? LibraryHealthMutationError, .remoteEvidenceExpired)
        }
        XCTAssertTrue(GenreMetadata.isMissing(track.genre))
        XCTAssertTrue(try ModelContext(store).fetch(FetchDescriptor<Track>()).allSatisfy { GenreMetadata.isMissing($0.genre) })
    }
}
