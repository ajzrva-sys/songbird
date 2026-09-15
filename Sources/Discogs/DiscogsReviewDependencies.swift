import Foundation

public protocol DiscogsReviewClient: DiscogsSearching {
    func downloadImage(from url: URL, evidence: DiscogsContentEvidence) async throws -> Data
}

extension DiscogsClient: DiscogsReviewClient {}

public protocol DiscogsReviewCaching: Sendable {
    func candidates(for query: DiscogsArtworkSearchQuery) async -> DiscogsArtworkSearchCache.Hit?
    func store(_ candidates: [DiscogsArtworkCandidate], for query: DiscogsArtworkSearchQuery,
               fetches: [DiscogsFetchStamp]) async -> Bool
}
extension DiscogsArtworkSearchCache: DiscogsReviewCaching {}

/// Per-surface dependencies. Injected clients never acquire a live token first.
/// Canned clients must be supplied explicitly; there is no process-wide bypass.
public struct DiscogsReviewDependencies: Sendable {
    public let client: any DiscogsReviewClient
    public let clock: @Sendable () -> DiscogsFetchStamp?
    public let cache: any DiscogsReviewCaching

    public init(client: any DiscogsReviewClient, cacheURL: URL,
                clock: @escaping @Sendable () -> DiscogsFetchStamp?) {
        self.client = client
        self.clock = clock
        self.cache = DiscogsArtworkSearchCache(fileURL: cacheURL, clock: clock)
    }

    public init(client: any DiscogsReviewClient, cache: any DiscogsReviewCaching,
                clock: @escaping @Sendable () -> DiscogsFetchStamp?) {
        self.client = client
        self.cache = cache
        self.clock = clock
    }

    @MainActor
    public func cachedCandidates(for query: DiscogsArtworkSearchQuery) async throws -> DiscogsArtworkSearchCache.Hit? {
        let hit = await cache.candidates(for: query)
        try Task.checkCancellation()
        guard let hit else { return nil }
        try validate(fetches: hit.fetches, candidates: hit.value)
        return hit
    }

    @MainActor
    public func storeCandidates(_ candidates: [DiscogsArtworkCandidate], for query: DiscogsArtworkSearchQuery,
                                fetches: [DiscogsFetchStamp]) async throws {
        try validate(fetches: fetches, candidates: candidates)
        let accepted = await cache.store(candidates, for: query, fetches: fetches)
        try Task.checkCancellation()
        try validate(fetches: fetches, candidates: candidates)
        guard accepted else { throw LibraryHealthMutationError.remoteEvidenceExpired }
    }

    private func validate(fetches: [DiscogsFetchStamp], candidates: [DiscogsArtworkCandidate]) throws {
        let now = clock()
        guard !fetches.isEmpty, fetches.allSatisfy({ DiscogsFreshness.isFresh($0, at: now) }),
              candidates.allSatisfy({ $0.evidence.isFresh(at: now) && fetches.contains($0.fetchedAt) }) else {
            throw LibraryHealthMutationError.remoteEvidenceExpired
        }
    }

    private init() {
        client = DiscogsClient(tokenProvider: { try await DiscogsKeychain.load() })
        clock = { DiscogsClock.sample() }
        cache = DiscogsArtworkSearchCache.shared
    }
    public static var live: Self { Self() }

    @MainActor
    public func search(_ query: DiscogsArtworkSearchQuery, page: Int) async throws -> DiscogsSearchPage {
        let result: DiscogsSearchPage
        do { result = try await client.search(query, page: page) }
        catch DiscogsError.resultsExpired, DiscogsError.freshnessUnavailable {
            throw LibraryHealthMutationError.remoteEvidenceExpired
        }
        try Task.checkCancellation()
        guard DiscogsFreshness.isFresh(result.fetchedAt, at: clock()) else {
            throw LibraryHealthMutationError.remoteEvidenceExpired
        }
        try requireFreshDiscogsEvidence(result.candidates.map(\.evidence), clock: clock)
        return result
    }
}
