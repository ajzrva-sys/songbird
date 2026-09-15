import Foundation

public actor DiscogsArtworkSearchCache {
    public static let shared = DiscogsArtworkSearchCache()
    public static let defaultMaximumAge = DiscogsFreshness.maximumAge
    public typealias Hit = DiscogsResponseCache<[DiscogsArtworkCandidate]>.Hit
    private let cache: DiscogsResponseCache<[DiscogsArtworkCandidate]>

    init(fileURL: URL = DiscogsArtworkSearchCache.defaultFileURL,
         maximumAge: TimeInterval = DiscogsArtworkSearchCache.defaultMaximumAge,
         clock: @escaping @Sendable () -> DiscogsFetchStamp? = { DiscogsClock.sample() }) {
        cache = DiscogsResponseCache(fileURL: fileURL, maximumAge: maximumAge, clock: clock)
    }

    public func candidates(for query: DiscogsArtworkSearchQuery) async -> Hit? {
        guard let hit = await cache.value(for: Self.key(for: query)),
              Self.hasEvidence(hit.value, fetches: hit.fetches) else { return nil }
        return hit
    }

    @discardableResult
    public func store(_ candidates: [DiscogsArtworkCandidate], for query: DiscogsArtworkSearchQuery,
                      fetches: [DiscogsFetchStamp]) async -> Bool {
        guard Self.hasEvidence(candidates, fetches: fetches) else { return false }
        return await cache.store(candidates, fetches: fetches, for: Self.key(for: query))
    }

    private static func hasEvidence(_ candidates: [DiscogsArtworkCandidate],
                                    fetches: [DiscogsFetchStamp]) -> Bool {
        candidates.allSatisfy { $0.id > 0 && fetches.contains($0.fetchedAt) }
    }

    private static func key(for query: DiscogsArtworkSearchQuery) -> String {
        let title = normalized(query.albumTitle)
        let artist = normalized(query.albumArtist)
        return "\(artist)\u{1f}\(title)\u{1f}\(query.year ?? 0)"
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }

    private static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appendingPathComponent("Songbird", isDirectory: true)
            .appendingPathComponent("discogs-artwork-search-cache.json")
    }
}
