import Foundation

/// A transient download batch. The submitter remains the shared action boundary.
@MainActor
enum DiscogsArtworkApplication {
    static func apply(
        _ suggestions: [DiscogsArtworkAlbumSuggestion],
        clock: () -> DiscogsFetchStamp? = DiscogsClock.sample,
        download: (DiscogsArtworkCandidate) async throws -> Data,
        normalize: (Data) -> Data = ArtworkStorage.normalized,
        isCurrent: () -> Bool = { true },
        progress: (Int) -> Void = { _ in },
        submit: ([LibraryArtworkChange]) async -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError>
    ) async throws -> LibraryHealthMutationOutcome {
        struct ImageKey: Hashable {
            let url: URL
            let evidence: DiscogsContentEvidence
        }
        let evidence = suggestions.map { $0.candidate.evidence }
        var downloaded: [ImageKey: Data] = [:]
        var changes: [LibraryArtworkChange] = []
        for (index, suggestion) in suggestions.enumerated() {
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
            try requireFreshDiscogsEvidence(evidence, clock: clock)
            let bytes: Data
            let key = ImageKey(url: suggestion.candidate.imageURL, evidence: suggestion.candidate.evidence)
            do {
                if let existing = downloaded[key] { bytes = existing }
                else {
                    bytes = try await download(suggestion.candidate)
                }
            }
            catch {
                try Task.checkCancellation()
                guard isCurrent() else { throw CancellationError() }
                try requireFreshDiscogsEvidence(evidence, clock: clock)
                throw error
            }
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
            try requireFreshDiscogsEvidence(evidence, clock: clock)
            guard ArtworkStorage.pixelSize(of: bytes) != nil else { throw LibraryHealthMutationError.invalidArtwork }
            downloaded[key] = bytes
            changes.append(LibraryArtworkChange(albumID: suggestion.album.id,
                expectedArtworkDigest: suggestion.album.expectedArtworkDigest,
                imageData: normalize(bytes), discogsEvidence: suggestion.candidate.evidence))
            progress(index + 1)
        }
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        try requireFreshDiscogsEvidence(evidence, clock: clock)
        return try await submit(changes).get()
    }
}
