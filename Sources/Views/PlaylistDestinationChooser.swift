import SwiftUI

enum PlaylistDestinationEmptyReason: Equatable {
    case none
    case noMatches(query: String)

    static func resolve(resultCount: Int, searchText: String) -> Self {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resultCount == 0, query.isEmpty == false else { return .none }
        return .noMatches(query: query)
    }
}

public struct PlaylistDestinationChooser: View {
    let request: PlaylistDestinationRequest

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var actions: LibraryItemActionHandler
    @State private var searchText = ""

    public init(request: PlaylistDestinationRequest) {
        self.request = request
    }

    private var playlists: [LibraryPlaylistSnapshot] {
        actions.manualPlaylists.filter {
            searchText.isEmpty || $0.name.localizedStandardContains(searchText)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose Playlist")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            List(playlists) { playlist in
                Button(playlist.name) {
                    if case .success = actions.addToPlaylist(
                        trackIDs: request.trackIDs,
                        playlistID: playlist.id
                    ) {
                        actions.playlistDestinationRequest = nil
                        dismiss()
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "Search Playlists")
            .overlay {
                switch PlaylistDestinationEmptyReason.resolve(
                    resultCount: playlists.count,
                    searchText: searchText
                ) {
                case .none:
                    EmptyView()
                case .noMatches(let query):
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 420)
    }
}
