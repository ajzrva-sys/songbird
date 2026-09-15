import AppKit
import SwiftUI

/// Uses the same evidence-aware, injectable client as the enclosing review.
struct DiscogsReviewThumbnail: View {
    let candidate: DiscogsArtworkCandidate
    let dependencies: DiscogsReviewDependencies
    @State private var image: NSImage?

    private struct Key: Hashable {
        let url: URL?
        let evidence: DiscogsContentEvidence
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary).overlay {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
        }
        .task(id: Key(url: candidate.thumbnailURL, evidence: candidate.evidence)) {
            image = nil
            guard let url = candidate.thumbnailURL,
                  candidate.evidence.isFresh(at: dependencies.clock()) else { return }
            do {
                let bytes = try await dependencies.client.downloadImage(from: url, evidence: candidate.evidence)
                guard !Task.isCancelled, candidate.evidence.isFresh(at: dependencies.clock()) else { return }
                image = NSImage(data: bytes)
            } catch { image = nil }
        }
    }
}
