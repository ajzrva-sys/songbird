import SwiftUI

public struct PlaylistDestinationMenu: View {
    let trackIDs: [UUID]
    var bringMainPlayerForward = false

    @EnvironmentObject private var actions: LibraryItemActionHandler

    public init(trackIDs: [UUID], bringMainPlayerForward: Bool = false) {
        self.trackIDs = trackIDs
        self.bringMainPlayerForward = bringMainPlayerForward
    }

    public var body: some View {
        Menu(trackIDs.count > 1 ? "Add \(trackIDs.count) Tracks to Playlist" : "Add to Playlist") {
            Button("New Playlist…") {
                actions.requestNewPlaylist(
                    trackIDs: trackIDs,
                    bringMainPlayerForward: bringMainPlayerForward
                )
            }
            if actions.recentManualPlaylists.isEmpty == false { Divider() }
            ForEach(actions.recentManualPlaylists) { playlist in
                Button(playlist.name) {
                    actions.addToPlaylist(trackIDs: trackIDs, playlistID: playlist.id)
                }
            }
            if actions.manualPlaylists.count > actions.recentManualPlaylists.count {
                Divider()
                Button("Choose Playlist…") {
                    actions.requestPlaylistDestination(
                        trackIDs: trackIDs,
                        bringMainPlayerForward: bringMainPlayerForward
                    )
                }
            }
        }
    }
}
