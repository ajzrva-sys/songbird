import Foundation

/// Sample on the caller's actor, immediately at each use/mutation boundary.
/// Nil evidence is reserved for local operations, never Discogs suggestions.
func requireFreshDiscogsEvidence(
    _ evidence: [DiscogsContentEvidence],
    clock: () -> DiscogsFetchStamp? = DiscogsClock.sample
) throws {
    guard !evidence.isEmpty else { return }
    let now = clock()
    guard evidence.allSatisfy({ $0.isFresh(at: now) }) else {
        throw LibraryHealthMutationError.remoteEvidenceExpired
    }
}
