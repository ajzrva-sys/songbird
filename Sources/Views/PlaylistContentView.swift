import SwiftUI
import UniformTypeIdentifiers

struct PlaylistContentView: View {
    let playlistID: UUID

    @EnvironmentObject private var snapshots: LibrarySnapshotStore
    @EnvironmentObject private var actions: LibraryItemActionHandler
    @EnvironmentObject private var navigation: LibraryNavigationCoordinator
    @State private var isDropTargeted = false
    @State private var showsAddTracks = false
    @State private var showsRename = false
    @State private var renameText = ""
    @State private var showsDelete = false
    @State private var showsSmartEditor = false

    private var playlist: LibraryPlaylistSnapshot? {
        snapshots.snapshot.playlists.first { $0.id == playlistID }
    }

    var body: some View {
        Group {
            if let playlist {
                VStack(spacing: 0) {
                    playlistHeader(playlist)
                    Divider()
                    TrackTableView(
                        title: playlist.name,
                        collection: .playlist(playlist.id),
                        showsFilters: !playlist.isSmart,
                        showsHeader: false,
                        emptyMessage: "Empty Playlist",
                        emptyHint: playlist.isSmart
                            ? "No tracks match these smart rules"
                            : "Drag tracks here, or choose Add Tracks…"
                    )
                }
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.accentColor, lineWidth: 3)
                            .padding(6)
                            .allowsHitTesting(false)
                    }
                }
                .onDrop(of: [.songbirdTrackIDs, .plainText], isTargeted: $isDropTargeted) {
                    handleDrop($0, playlist: playlist)
                }
                .sheet(isPresented: $showsAddTracks) {
                    PlaylistTrackPickerView(playlist: playlist) { ids in
                        report(actions.addTracks(ids, toPlaylist: playlist.id))
                    }
                }
                .sheet(isPresented: $showsSmartEditor) {
                    SmartPlaylistEditorView(target: SmartPlaylistEditorTarget(snapshot: playlist))
                }
                .alert("Rename Playlist", isPresented: $showsRename) {
                    TextField("Name", text: $renameText)
                    Button("Cancel", role: .cancel) {}
                    Button("Save") {
                        _ = actions.renamePlaylist(
                            playlistID: playlist.id,
                            expectedName: playlist.name,
                            newName: renameText
                        )
                    }
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .alert("Delete Playlist?", isPresented: $showsDelete) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        if case .success = actions.deletePlaylist(playlistID: playlist.id) {
                            navigation.selectRoot(.allTracks)
                        }
                    }
                } message: {
                    Text("“\(playlist.name)” will be removed. Library tracks and audio files remain unchanged.")
                }
            } else {
                ContentUnavailableView {
                    Label("Playlist Not Found", systemImage: "music.note.list")
                } description: {
                    Text("This playlist is no longer in the library.")
                } actions: {
                    Button("Open All Tracks") { navigation.selectRoot(.allTracks) }
                }
            }
        }
    }

    private func playlistHeader(_ playlist: LibraryPlaylistSnapshot) -> some View {
        let ids = resolvedTrackIDs(playlist)
        let tracks = ids.compactMap { snapshots.snapshot.tracksByID[$0] }
        let duration = tracks.reduce(0) { $0 + $1.duration }
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name).font(.title2.weight(.semibold)).lineLimit(1)
                Text("\(tracks.count) track\(tracks.count == 1 ? "" : "s") · \(Self.durationText(duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Play") { actions.requestPlay(trackIDs: ids) }
                .buttonStyle(.borderedProminent)
                .disabled(ids.isEmpty)
            Button("Shuffle") { actions.requestPlay(trackIDs: ids, shuffled: true) }
                .disabled(ids.isEmpty)
            if playlist.isSmart {
                Button("Edit Rules…") { showsSmartEditor = true }
            } else {
                Button("Add Tracks…") { showsAddTracks = true }
            }
            Menu {
                if !playlist.isSmart || playlist.systemKey == nil {
                    Button("Rename…") {
                        renameText = playlist.name
                        showsRename = true
                    }
                }
                Button("Export M3U…") { actions.exportPlaylist(playlistID: playlist.id) }
                if playlist.systemKey == nil {
                    Divider()
                    Button("Delete…", role: .destructive) { showsDelete = true }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(16)
    }

    private func resolvedTrackIDs(_ playlist: LibraryPlaylistSnapshot) -> [UUID] {
        playlist.isSmart
            ? (playlist.rules?.filter(snapshots.snapshot.tracks).map(\.id) ?? [])
            : playlist.trackIDs
    }

    private func handleDrop(
        _ providers: [NSItemProvider],
        playlist: LibraryPlaylistSnapshot
    ) -> Bool {
        guard !playlist.isSmart else {
            LibraryStatus.shared.showNotice(
                "Smart playlists are controlled by their rules.",
                severity: .warning,
                autoDismissAfter: 4
            )
            return false
        }
        return TrackIDDropDecoder.decode(providers: providers) { ids in
            report(actions.addTracks(ids, toPlaylist: playlist.id))
        }
    }

    private func report(_ result: Result<PlaylistAddSummary, LibraryActionError>) {
        guard case .success(let summary) = result else { return }
        LibraryStatus.shared.showNotice(
            "Added \(summary.added); \(summary.duplicateSkipped) already present; \(summary.missing) unavailable.",
            severity: .success,
            autoDismissAfter: 4
        )
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

private struct PlaylistTrackPickerView: View {
    let playlist: LibraryPlaylistSnapshot
    let add: ([UUID]) -> Void

    @EnvironmentObject private var snapshots: LibrarySnapshotStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: Set<UUID> = []

    private var existing: Set<UUID> { Set(playlist.trackIDs) }
    private var candidates: [LibraryTrackSnapshot] {
        snapshots.snapshot.tracks.filter { track in
            !existing.contains(track.id)
                && (query.isEmpty
                    || track.title.localizedStandardContains(query)
                    || track.artist.localizedStandardContains(query)
                    || track.album.localizedStandardContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Tracks to \(playlist.name)").font(.title2.weight(.semibold))
                Spacer()
                TextField("Search Library", text: $query).textFieldStyle(.roundedBorder).frame(width: 240)
            }
            .padding()
            Divider()
            List(candidates, selection: $selection) { track in
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title.isEmpty ? (track.path as NSString).lastPathComponent : track.title)
                    Text("\(track.artist) · \(track.album)").font(.caption).foregroundStyle(.secondary)
                }
                .tag(track.id)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            Divider()
            HStack {
                Text("\(selection.count) selected").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Tracks") {
                    let ordered = snapshots.snapshot.tracks.map(\.id).filter(selection.contains)
                    add(ordered)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 680, minHeight: 500)
    }
}
