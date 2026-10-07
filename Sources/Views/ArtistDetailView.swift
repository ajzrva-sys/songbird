import SwiftUI

enum ArtistDetailViewMode: String, CaseIterable, Identifiable {
    case albums = "Albums"
    case tracks = "Tracks"

    var id: Self { self }
}

struct ArtistDetailView: View {
    let name: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewMode = ArtistDetailViewMode.albums

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .help(name)
                Spacer(minLength: 12)
                Picker("Artist View", selection: $viewMode) {
                    ForEach(ArtistDetailViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 176)
                .accessibilityLabel("Artist View")
                .accessibilityIdentifier("library.artistViewMode")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()

            switch viewMode {
            case .albums:
                AlbumGridView(scope: .artist(name: name), showsTitle: false)
            case .tracks:
                TrackTableView(
                    title: name,
                    collection: .artist(name),
                    showsFilters: false,
                    showsHeader: false
                )
            }
        }
        .background(SongbirdTheme.background(for: colorScheme))
        .accessibilityIdentifier("library.artistDetail")
    }
}
