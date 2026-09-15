public enum DiscogsArtworkSuggestionPolicy {
    public static func suggestedCandidate(
        from candidates: [DiscogsArtworkCandidate],
        at now: DiscogsFetchStamp?
    ) -> DiscogsArtworkCandidate? {
        guard let first = candidates.first, first.evidence.isFresh(at: now) else { return nil }
        return first
    }
}

struct DiscogsArtworkAlbumSuggestion: Sendable {
    let album: DiscogsArtworkAlbumTarget
    let candidate: DiscogsArtworkCandidate
}
