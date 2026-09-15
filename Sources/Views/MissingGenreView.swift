import SwiftUI
import SwiftData

/// Library health view for tracks missing genre, with Discogs genre lookup.
public struct MissingGenreView: View {
    @EnvironmentObject private var libraryActions: LibraryItemActionHandler
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var loadError: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Scanning…")
                Spacer()
            } else if let loadError {
                Spacer()
                ContentUnavailableView {
                    Label("Could Not Scan Genres", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") { loadTracks() }
                }
                Spacer()
            } else if tracks.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Tracks Missing Genre",
                    systemImage: "tag.slash",
                    description: Text("All library tracks have a genre assigned.")
                )
                Spacer()
            } else {
                trackList
            }
        }
        .background(SongbirdTheme.background(for: colorScheme))
        .task { loadTracks() }
    }

    private var trackList: some View {
        List {
            Section {
                HStack {
                    Text("\(tracks.count) track\(tracks.count == 1 ? "" : "s") missing genre")
                        .font(.headline)
                    Spacer()
                    Button("Fix Missing Genre…") {
                        DiscogsGenreReviewWindowPresenter.show(modelContext: modelContext, actions: libraryActions)
                    }
                    .buttonStyle(.bordered)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            ForEach(tracks, id: \.id) { track in
                HStack(spacing: 8) {
                    Image(systemName: "tag.slash")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title.isEmpty ? (track.path as NSString).lastPathComponent : track.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if !track.artist.isEmpty {
                                Text(track.artist)
                                    .foregroundStyle(.secondary)
                            }
                            if !track.album.isEmpty {
                                Text(track.album)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 11))
                        .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
    }

    private func loadTracks() {
        isLoading = true
        loadError = nil
        let descriptor = FetchDescriptor<Track>(
            sortBy: [SortDescriptor(\Track.artist), SortDescriptor(\Track.album)]
        )
        do {
            tracks = try modelContext.fetch(descriptor).filter {
                GenreMetadata.isMissing($0.genre)
            }
        } catch {
            tracks = []
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
