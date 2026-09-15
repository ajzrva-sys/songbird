import SwiftUI
import SwiftData

/// Library health view showing albums without artwork.
public struct MissingArtworkView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var libraryActions: LibraryItemActionHandler
    @Environment(\.colorScheme) private var colorScheme
    @State private var albums: [Album] = []
    @State private var isLoading = true

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Scanning…")
                Spacer()
            } else if albums.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Missing Artwork",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("All albums have artwork assigned.")
                )
                Spacer()
            } else {
                List {
                    Section {
                        HStack {
                            Text("\(albums.count) album\(albums.count == 1 ? "" : "s") without artwork")
                                .font(.headline)
                            Spacer()
                            Button("Find Artwork on Discogs…") {
                                DiscogsBulkReviewWindowPresenter.show(
                                    modelContext: modelContext,
                                    actions: libraryActions
                                )
                            }
                            .buttonStyle(.bordered)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    ForEach(albums, id: \.id) { album in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary)
                                .frame(width: 40, height: 40)
                                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.title.isEmpty ? "Unknown Album" : album.title)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                Text(album.artist.isEmpty ? "Unknown Artist" : album.artist)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text("\(album.tracks.count) track\(album.tracks.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .scrollContentBackground(.hidden)
            }
        }
        .background(SongbirdTheme.background(for: colorScheme))
        .task { loadAlbums() }
    }

    private func loadAlbums() {
        let descriptor = FetchDescriptor<Album>(sortBy: [SortDescriptor(\Album.title)])
        do {
            let all = try modelContext.fetch(descriptor)
            albums = all.filter { $0.artworkData == nil }
        } catch {
            albums = []
        }
        isLoading = false
    }
}
