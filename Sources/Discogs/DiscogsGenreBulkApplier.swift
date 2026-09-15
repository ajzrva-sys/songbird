import Foundation
import SwiftData

struct DiscogsGenreAlbumSuggestion {
    let album: DiscogsArtworkAlbumTarget
    let genre: String
    let evidence: DiscogsContentEvidence
}

struct DiscogsGenreBulkApplyResult: Equatable {
    let appliedAlbums: Int
    let skippedAlbums: Int
}

@MainActor
enum DiscogsGenreBulkApplier {
    static func apply(
        _ suggestions: [DiscogsGenreAlbumSuggestion],
        in context: ModelContext,
        clock: () -> DiscogsFetchStamp? = DiscogsClock.sample
    ) throws -> DiscogsGenreBulkApplyResult {
        let evidence = suggestions.map(\.evidence)
        try requireFreshDiscogsEvidence(evidence, clock: clock)
        var seen = Set<UUID>()
        let uniqueSuggestions = suggestions.filter { seen.insert($0.album.id).inserted }

        var originalGenres: [(Track, String)] = []
        do {
            let albums = try DiscogsArtworkAlbumTarget.resolve(
                uniqueSuggestions.map(\.album),
                in: context
            )
            let albumsByID = Dictionary(
                albums.map { ($0.id, $0) },
                uniquingKeysWith: { current, _ in current }
            )
            let existingGenres = try context.fetch(FetchDescriptor<Track>())
                .map(\.genre)
                .filter { GenreMetadata.isMissing($0) == false }
            let variantsByKey = Dictionary(
                grouping: existingGenres,
                by: { $0.localizedLowercase }
            )
            let preferredCasing = variantsByKey.compactMapValues {
                LibrarySnapshot.bestGenreVariant($0)
            }

            var applied = 0
            var skipped = suggestions.count - uniqueSuggestions.count
            for suggestion in uniqueSuggestions {
                let normalizedGenre = GenreMetadata.normalized(suggestion.genre)
                guard normalizedGenre.isEmpty == false,
                      let album = albumsByID[suggestion.album.id] else {
                    skipped += 1
                    continue
                }
                let missingTracks = album.tracks.filter {
                    GenreMetadata.isMissing($0.genre)
                }
                guard missingTracks.isEmpty == false else {
                    skipped += 1
                    continue
                }
                let genre = preferredCasing[normalizedGenre.localizedLowercase]
                    ?? normalizedGenre
                for track in missingTracks {
                    try requireFreshDiscogsEvidence(evidence, clock: clock)
                    originalGenres.append((track, track.genre))
                    track.genre = genre
                }
                applied += 1
            }

            try Task.checkCancellation()
            try requireFreshDiscogsEvidence(evidence, clock: clock)
            try context.save()
            return DiscogsGenreBulkApplyResult(
                appliedAlbums: applied,
                skippedAlbums: skipped
            )
        } catch {
            // SwiftData rollback can leave already-observed model properties stale.
            for (track, genre) in originalGenres { track.genre = genre }
            context.rollback()
            throw error
        }
    }
}
