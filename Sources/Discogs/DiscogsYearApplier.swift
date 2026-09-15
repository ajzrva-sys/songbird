import Foundation
import SwiftData

struct DiscogsYearSuggestion: Identifiable {
    let album: DiscogsArtworkAlbumTarget
    let year: Int
    let evidence: DiscogsContentEvidence
    var id: UUID { album.id }
    var sourcePageURL: URL? { evidence.sourcePageURL }

    init(album: DiscogsArtworkAlbumTarget, year: Int, evidence: DiscogsContentEvidence) {
        self.album = album
        self.year = year
        self.evidence = evidence
    }

    /// Compatibility for callers holding a model: never retain the live Album or a source label.
    @MainActor
    init(album: Album, year: Int, source: String, evidence: DiscogsContentEvidence) {
        self.init(album: DiscogsArtworkAlbumTarget(album: album), year: year, evidence: evidence)
    }
}

struct DiscogsYearApplyResult: Equatable {
    let appliedAlbums: Int
    let skippedAlbums: Int
}

@MainActor
enum DiscogsYearApplier {
    static func apply(_ suggestions: [DiscogsYearSuggestion], in context: ModelContext,
        clock: () -> DiscogsFetchStamp? = DiscogsClock.sample,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> DiscogsYearApplyResult {
        let evidence = suggestions.map(\.evidence)
        try requireFreshDiscogsEvidence(evidence, clock: clock)
        var seen = Set<UUID>()
        let unique = suggestions.filter { seen.insert($0.id).inserted }
        let albums = try DiscogsArtworkAlbumTarget.resolve(unique.map(\.album), in: context)
        let byID = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var applied = 0
        var skipped = suggestions.count - unique.count
        var originalAlbums: [(Album, Int)] = []
        var originalTracks: [(Track, Int)] = []
        do {
            for suggestion in unique {
                guard suggestion.year > 0, let album = byID[suggestion.id], album.year == 0 else {
                    skipped += 1
                    continue
                }
                try requireFreshDiscogsEvidence(evidence, clock: clock)
                originalAlbums.append((album, album.year))
                album.year = suggestion.year
                for track in album.tracks where track.year == 0 {
                    try requireFreshDiscogsEvidence(evidence, clock: clock)
                    originalTracks.append((track, track.year))
                    track.year = suggestion.year
                }
                applied += 1
            }
            try Task.checkCancellation()
            try requireFreshDiscogsEvidence(evidence, clock: clock)
            if applied > 0 { try save(context) }
            return DiscogsYearApplyResult(appliedAlbums: applied, skippedAlbums: skipped)
        } catch {
            for (album, year) in originalAlbums { album.year = year }
            for (track, year) in originalTracks { track.year = year }
            context.rollback()
            throw error
        }
    }
}
