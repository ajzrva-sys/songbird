import SwiftUI

/// Keep this view adjacent to provider content, outside any selection Button.
struct DiscogsAttributionView: View {
    let sourcePageURL: URL?

    var body: some View {
        if let sourcePageURL {
            Link("Data provided by Discogs.", destination: sourcePageURL)
                .font(.caption2)
        }
    }
}
