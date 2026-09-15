import SwiftUI

struct MissingAlbumArtworkButton: View {
    let albumTitle: String
    var cornerRadius: CGFloat = 8
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GeometryReader { geometry in
                ArtworkThumbnailView(
                    reference: .missingAlbumArtwork,
                    pointSize: geometry.size,
                    accessibilityLabel: "No album artwork for \(albumTitle)",
                    cornerRadius: cornerRadius
                )
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .help("Search Discogs for artwork for \(albumTitle)")
    }
}
