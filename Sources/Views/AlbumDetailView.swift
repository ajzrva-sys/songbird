import SwiftUI

public struct AlbumDetailView: View {
    public let albumID: UUID

    @EnvironmentObject private var librarySnapshots: LibrarySnapshotStore
    @EnvironmentObject private var albumProjectionStore: LibraryAlbumProjectionStore
    @EnvironmentObject private var actions: LibraryItemActionHandler
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var showingMetadataConfirmation = false
    @State private var showingDeleteConfirmation = false

    public init(albumID: UUID) {
        self.albumID = albumID
    }

    private var album: LibraryAlbumGroupSnapshot? {
        albumProjectionStore.group(
            containing: albumID,
            fallback: librarySnapshots.snapshot
        )
    }

    private var displayDetail: String? {
        guard let album else { return nil }
        return albumProjectionStore.displayDetail(forGroupID: album.id)
    }

    public var body: some View {
        Group {
            if let album {
                VStack(spacing: 0) {
                    albumHeader(album)
                    Divider()
                    TrackTableView(
                        title: album.title,
                        collection: .orderedTrackIDs(album.trackIDs),
                        showsFilters: false,
                        showsHeader: false,
                        supportsSearch: false,
                        emptyMessage: "Album Unavailable",
                        emptyHint: "The album's tracks are no longer in the library"
                    )
                }
                .navigationTitle(album.title)
                .contextMenu {
                    AlbumContextMenu(
                        album: album,
                        refreshMetadataAction: { showingMetadataConfirmation = true },
                        deleteAction: { showingDeleteConfirmation = true }
                    )
                }
            } else {
                switch albumProjectionStore.state {
                case .loading:
                    ProgressView("Loading Album…")
                case .failed(let message, _):
                    ContentUnavailableView {
                        Label("Album Could Not Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") {
                            Task {
                                await albumProjectionStore.update(
                                    from: librarySnapshots.snapshot,
                                    force: true
                                )
                            }
                        }
                    }
                case .loaded:
                    ContentUnavailableView(
                        "Album Not Found",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text("This album is no longer available in the library.")
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SongbirdTheme.background(for: colorScheme))
        .task(id: librarySnapshots.snapshot.revision) {
            await albumProjectionStore.update(from: librarySnapshots.snapshot)
        }
        .task(id: album?.id) {
            guard let album, album.artworkReference == nil else { return }
            await actions.discoverFolderArtwork(albumIDs: album.albumIDs)
        }
        .onDisappear {
            if let album {
                actions.cancelSidebarPlaylistTargeting(sourceID: album.id)
            }
        }
        .alert("Re-read Album Metadata?", isPresented: $showingMetadataConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Re-read Metadata") {
                guard let album else { return }
                actions.refreshMetadata(trackIDs: album.trackIDs)
            }
        } message: {
            Text("Songbird will re-read metadata for \(album?.trackIDs.count ?? 0) tracks. You can cancel from the status bar.")
        }
        .alert("Delete Album?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete from Library", role: .destructive) {
                guard let album else { return }
                if case .success = actions.deleteAlbum(
                    albumIDs: album.albumIDs,
                    trackIDs: album.trackIDs
                ) {
                    dismiss()
                }
            }
        } message: {
            Text("“\(album?.title ?? "This album")” will be removed from your library. The files on disk are not deleted.")
        }
    }

    private func albumHeader(_ album: LibraryAlbumGroupSnapshot) -> some View {
        HStack(alignment: .top, spacing: 20) {
            if let artworkReference = album.artworkReference {
                ArtworkThumbnailView(
                    reference: artworkReference,
                    pointSize: CGSize(width: 160, height: 160),
                    accessibilityLabel: "Album artwork for \(album.title)",
                    cornerRadius: 8,
                    placeholderSymbol: "square.stack",
                    placeholderColor: SongbirdTheme.placeholder(for: colorScheme)
                )
                .frame(width: 160, height: 160)
            } else {
                MissingAlbumArtworkButton(
                    albumTitle: album.title,
                    action: {
                        actions.searchForArtwork(
                            albumIDs: album.albumIDs,
                            title: album.title
                        )
                    }
                )
                .frame(width: 160, height: 160)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(album.title)
                        .font(.title.bold())
                        .lineLimit(2)
                    Button(
                        album.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: album.isFavorite ? "heart.fill" : "heart"
                    ) {
                        actions.setAlbumFavorite(
                            album.isFavorite == false,
                            albumIDs: album.albumIDs
                        )
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityAddTraits(album.isFavorite ? .isSelected : [])
                }

                Button(album.artist) {
                    actions.showArtist(name: album.artist)
                }
                .buttonStyle(.link)
                .font(.title3)

                if let displayDetail {
                    Text(displayDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text(albumSummary(album))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Play", systemImage: "play.fill") {
                        actions.requestPlay(trackIDs: album.trackIDs)
                    }
                    Button("Shuffle", systemImage: "shuffle") {
                        actions.requestPlay(trackIDs: album.trackIDs, shuffled: true)
                    }
                    Button("Add to Queue", systemImage: "text.badge.plus") {
                        actions.addToQueue(trackIDs: album.trackIDs)
                    }
                    Button("Add to Playlist", systemImage: isChoosingPlaylist(for: album)
                        ? "music.note.list"
                        : "text.badge.plus") {
                        actions.beginSidebarPlaylistTargeting(
                            sourceID: album.id,
                            sourceName: album.title,
                            trackIDs: album.trackIDs
                        )
                    }
                    .tint(isChoosingPlaylist(for: album) ? .accentColor : nil)
                    .help(isChoosingPlaylist(for: album)
                        ? "Cancel choosing a playlist"
                        : "Choose a playlist in the sidebar")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func isChoosingPlaylist(for album: LibraryAlbumGroupSnapshot) -> Bool {
        actions.sidebarPlaylistTargetRequest?.sourceID == album.id
    }

    private func albumSummary(_ album: LibraryAlbumGroupSnapshot) -> String {
        let trackCount = "\(album.trackIDs.count) track\(album.trackIDs.count == 1 ? "" : "s")"
        let discs = album.discCount > 1 ? " · \(album.discCount) discs" : ""
        let year = album.year > 0 ? " · \(album.year)" : ""
        return trackCount + discs + year
    }

}
