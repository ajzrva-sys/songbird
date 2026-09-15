import Testing
import SwiftData
@testable import SongbirdLib

struct DiscogsGenreSuggestionPolicyTests {
    @Test("The first Discogs result supplies the suggested primary genre")
    func firstResultWins() {
        let genre = DiscogsGenreSuggestionPolicy.suggestedGenre(
            from: [
                ["Electronic", "Experimental"],
                ["Rock"],
            ]
        )

        #expect(genre == "Electronic")
    }

    @Test("Blank candidate genres are skipped")
    func blankCandidatesAreSkipped() {
        let genre = DiscogsGenreSuggestionPolicy.suggestedGenre(
            from: [
                [],
                ["  "],
                [" Jazz \n"],
            ]
        )

        #expect(genre == "Jazz")
    }

    @Test("No usable candidate produces no suggestion")
    func noSuggestion() {
        #expect(
            DiscogsGenreSuggestionPolicy.suggestedGenre(from: [[], ["\t"]]) == nil
        )
    }

    @MainActor
    @Test("Bulk apply fills only missing genres and preserves assigned values")
    func bulkApplyPreservesAssignedGenres() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let album = Album(title: "Album", artist: "Artist")
        let missing = Track(path: "/missing.wav", title: "Missing")
        let assigned = Track(path: "/assigned.wav", title: "Assigned")
        assigned.genre = "Rock"
        album.tracks = [missing, assigned]
        context.insert(album)
        context.insert(missing)
        context.insert(assigned)
        try context.save()

        let result = try DiscogsGenreBulkApplier.apply(
            [
                DiscogsGenreAlbumSuggestion(
                    album: DiscogsArtworkAlbumTarget(album: album),
                    genre: " Electronic ",
                    evidence: DiscogsContentEvidence(releaseID: 1, fetches: [TestDiscogsClock.stamp()])
                )
            ],
            in: context, clock: { TestDiscogsClock.stamp() }
        )

        #expect(result == DiscogsGenreBulkApplyResult(appliedAlbums: 1, skippedAlbums: 0))
        #expect(missing.genre == "Electronic")
        #expect(assigned.genre == "Rock")
    }

    @MainActor
    @Test("Bulk apply safely skips an album removed during review")
    func bulkApplySkipsRemovedAlbum() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let album = Album(title: "Removed", artist: "Artist")
        context.insert(album)
        try context.save()
        let target = DiscogsArtworkAlbumTarget(album: album)
        context.delete(album)
        try context.save()

        let result = try DiscogsGenreBulkApplier.apply(
            [DiscogsGenreAlbumSuggestion(album: target, genre: "Jazz",
                evidence: DiscogsContentEvidence(releaseID: 1, fetches: [TestDiscogsClock.stamp()]))],
            in: context, clock: { TestDiscogsClock.stamp() }
        )

        #expect(result == DiscogsGenreBulkApplyResult(appliedAlbums: 0, skippedAlbums: 1))
    }

    @Test("Review candidate primary genre uses the same normalized suggestion as bulk")
    func reviewPrimaryGenreMatchesSuggestionPolicy() {
        let candidate = DiscogsGenreReviewView.DiscogsGenreCandidate(id: 42, title: "Synthetic",
            genres: ["  Jazz  "], styles: [],
            evidence: DiscogsContentEvidence(releaseID: 42, fetches: [TestDiscogsClock.stamp()]))
        #expect(candidate.primaryGenre == "Jazz")
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Track.self,
            Album.self,
            Artist.self,
            Playlist.self,
            AlbumFavorite.self,
            TrackFavorite.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
