import SwiftUI

enum TrackContextMenuLabels {
    static func action(_ singular: String, count: Int) -> String {
        count > 1 ? "\(singular) \(count) Tracks" : singular
    }

    static func addToQueue(count: Int) -> String {
        count > 1 ? "Add \(count) Tracks to Queue" : "Add to Queue"
    }

    static func editMetadata(count: Int) -> String {
        count > 1 ? "Edit Metadata for \(count) Tracks…" : "Edit Metadata…"
    }
}

public struct TrackContextMenu: View {
    public let track: LibraryTrackSnapshot
    public let targetIDs: [UUID]
    public var bringMainPlayerForward = false
    public var playNowAction: (() -> Void)?
    public var playNextAction: (() -> Void)?
    public var showsPlayNext = true
    public var removeFromQueueAction: (() -> Void)?
    public var removeFromPlaylistAction: (() -> Void)?
    public var deleteAction: (() -> Void)?

    @EnvironmentObject private var actions: LibraryItemActionHandler

    public init(
        track: LibraryTrackSnapshot,
        targetIDs: [UUID],
        bringMainPlayerForward: Bool = false,
        playNowAction: (() -> Void)? = nil,
        playNextAction: (() -> Void)? = nil,
        showsPlayNext: Bool = true,
        removeFromQueueAction: (() -> Void)? = nil,
        removeFromPlaylistAction: (() -> Void)? = nil,
        deleteAction: (() -> Void)? = nil
    ) {
        self.track = track
        self.targetIDs = targetIDs
        self.bringMainPlayerForward = bringMainPlayerForward
        self.playNowAction = playNowAction
        self.playNextAction = playNextAction
        self.showsPlayNext = showsPlayNext
        self.removeFromQueueAction = removeFromQueueAction
        self.removeFromPlaylistAction = removeFromPlaylistAction
        self.deleteAction = deleteAction
    }

    public var body: some View {
        Group {
            if let playNowAction {
                Button("Play Now", action: playNowAction)
            } else {
                Button(TrackContextMenuLabels.action("Play", count: targetIDs.count)) {
                    actions.requestPlay(trackIDs: targetIDs)
                }
            }
            if showsPlayNext {
                Button(TrackContextMenuLabels.action("Play Next", count: targetIDs.count)) {
                    if let playNextAction {
                        playNextAction()
                    } else {
                        actions.playNext(trackIDs: targetIDs)
                    }
                }
            }
            Button(TrackContextMenuLabels.addToQueue(count: targetIDs.count)) {
                actions.addToQueue(trackIDs: targetIDs)
            }
            if let removeFromQueueAction {
                Button("Remove from Queue", role: .destructive, action: removeFromQueueAction)
            }

            Divider()
            Button("Go to Album") {
                guard let albumID = track.albumID else { return }
                actions.showAlbum(
                    albumID: albumID,
                    bringMainPlayerForward: bringMainPlayerForward
                )
            }
            .disabled(track.albumID == nil)
            Button("Go to Artist") {
                actions.showArtist(
                    name: track.artist,
                    bringMainPlayerForward: bringMainPlayerForward
                )
            }
            .disabled(track.artist.isEmpty)

            PlaylistDestinationMenu(
                trackIDs: targetIDs,
                bringMainPlayerForward: bringMainPlayerForward
            )
            if let removeFromPlaylistAction {
                Button("Remove from Playlist", role: .destructive, action: removeFromPlaylistAction)
            }

            Divider()
            Button(TrackContextMenuLabels.editMetadata(count: targetIDs.count)) {
                actions.showInfo(trackIDs: targetIDs)
            }
            Button("Show Lyrics") { actions.showLyrics(trackID: track.id) }
            Button("Show in Finder") { actions.showInFinder(trackIDs: targetIDs) }
                .disabled(actions.canShowInFinder(trackIDs: targetIDs) == false)
            Button("Re-read Metadata") { actions.refreshMetadata(trackIDs: targetIDs) }
                .disabled(actions.canRefreshMetadata(trackIDs: targetIDs) == false)

            Divider()
            Button(track.isLoved ? "Remove from Favorites" : "Add to Favorites") {
                actions.setTrackLoved(!track.isLoved, trackIDs: targetIDs)
            }

            if let deleteAction {
                Divider()
                Button("Delete from Library…", role: .destructive, action: deleteAction)
            }
        }
    }

}

public struct AlbumContextMenu: View {
    public let albums: [LibraryAlbumGroupSnapshot]
    public var refreshMetadataAction: () -> Void
    public var deleteAction: () -> Void

    @EnvironmentObject private var actions: LibraryItemActionHandler

    public init(
        album: LibraryAlbumGroupSnapshot,
        refreshMetadataAction: @escaping () -> Void,
        deleteAction: @escaping () -> Void
    ) {
        self.albums = [album]
        self.refreshMetadataAction = refreshMetadataAction
        self.deleteAction = deleteAction
    }

    public init(
        albums: [LibraryAlbumGroupSnapshot],
        refreshMetadataAction: @escaping () -> Void,
        deleteAction: @escaping () -> Void
    ) {
        self.albums = albums
        self.refreshMetadataAction = refreshMetadataAction
        self.deleteAction = deleteAction
    }

    public var body: some View {
        Group {
            Button("Play") { actions.requestPlay(trackIDs: trackIDs) }
            Button("Play Next") { actions.playNext(trackIDs: trackIDs) }
            Button("Add to Queue") { actions.addToQueue(trackIDs: trackIDs) }
            Button(albums.count == 1 ? "Shuffle Album" : "Shuffle Albums") {
                actions.requestPlay(trackIDs: trackIDs, shuffled: true)
            }

            Divider()
            Button("Go to Album") {
                guard albums.count == 1, let albumID = albums.first?.albumIDs.first else { return }
                actions.showAlbum(albumID: albumID)
            }
            .disabled(albums.count != 1 || albums.first?.albumIDs.isEmpty != false)
            Button("Go to Artist") {
                guard let artist = sharedArtist else { return }
                actions.showArtist(name: artist)
            }
            .disabled(sharedArtist == nil)

            PlaylistDestinationMenu(trackIDs: trackIDs)

            Divider()
            Button("Edit Metadata…") { actions.showInfo(trackIDs: trackIDs) }
            Button("Show in Finder") { actions.showInFinder(trackIDs: trackIDs) }
                .disabled(actions.canShowInFinder(trackIDs: trackIDs) == false)
            Button("Re-read Metadata…", action: refreshMetadataAction)
                .disabled(actions.canRefreshMetadata(trackIDs: trackIDs) == false)

            Divider()
            Button(allFavorite ? "Remove from Favorites" : "Add to Favorites") {
                actions.setAlbumFavorite(allFavorite == false, albumIDs: albumIDs)
            }
            Button("Search for Artwork…") {
                guard albums.count == 1, let album = albums.first else { return }
                actions.searchForArtwork(albumIDs: album.albumIDs, title: album.title)
            }
            .disabled(albums.count != 1)

            Divider()
            Button(
                albums.count == 1 ? "Delete Album…" : "Delete \(albums.count) Albums…",
                role: .destructive,
                action: deleteAction
            )
        }
    }

    private var trackIDs: [UUID] {
        orderedUnique(albums.flatMap(\.trackIDs))
    }

    private var albumIDs: [UUID] {
        orderedUnique(albums.flatMap(\.albumIDs))
    }

    private var allFavorite: Bool {
        albums.isEmpty == false && albums.allSatisfy(\.isFavorite)
    }

    private var sharedArtist: String? {
        let artists = Set(albums.map(\.artist).filter { $0.isEmpty == false })
        return artists.count == 1 ? artists.first : nil
    }

    private func orderedUnique<ID: Hashable>(_ ids: [ID]) -> [ID] {
        var seen: Set<ID> = []
        return ids.filter { seen.insert($0).inserted }
    }
}
