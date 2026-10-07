import SwiftUI

/// Durable play history for the Queue section. Combines the persisted play log
/// with live library tracks for play-again and navigation.
public struct PlayHistoryView: View {
    @EnvironmentObject private var playHistory: PlayHistoryStore
    @EnvironmentObject private var queue: PlaybackQueue
    @EnvironmentObject private var librarySnapshots: LibrarySnapshotStore
    @EnvironmentObject private var actions: LibraryItemActionHandler
    @ObservedObject private var discogsClock = DiscogsPresentationClock.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var summaryOwner = LibraryContentSummaryOwner()
    @State private var confirmsClear = false
    @State private var seeded = false

    private var textColor: Color { SongbirdTheme.text(for: colorScheme) }
    private var secondaryColor: Color { SongbirdTheme.secondaryText(for: colorScheme) }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("History")
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if playHistory.items.isEmpty == false || queue.historyEntries.isEmpty == false {
                    Button("Clear History", role: .destructive) {
                        confirmsClear = true
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(secondaryColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()

            if playHistory.items.isEmpty && queue.historyEntries.isEmpty {
                emptyState
            } else {
                List {
                    if queue.historyEntries.isEmpty == false {
                        Section("This Session") {
                            ForEach(Array(queue.historyEntries.reversed())) { entry in
                                sessionRow(entry)
                            }
                        }
                    }
                    if playHistory.items.isEmpty == false {
                        Section("Listening History") {
                            ForEach(displayItems) { item in
                                historyRow(item)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(SongbirdTheme.background(for: colorScheme))
        .accessibilityIdentifier("library.playHistory")
        .alert("Clear Play History?", isPresented: $confirmsClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) {
                playHistory.clear()
                _ = queue.clearHistoryReturningSnapshot()
            }
        } message: {
            Text("Removes the persistent listening log and this session’s previously played list. Track play counts in the library are unchanged.")
        }
        .onAppear {
            LibraryStatus.shared.summary.activate(owner: summaryOwner)
            seedIfNeeded()
            updateSummary()
        }
        .onDisappear { LibraryStatus.shared.summary.clear(owner: summaryOwner) }
        .onChange(of: playHistory.items.count) { _, _ in updateSummary() }
        .onChange(of: queue.historyEntries.count) { _, _ in updateSummary() }
        .onChange(of: librarySnapshots.snapshot.revision) { _, _ in
            seedIfNeeded()
        }
    }

    /// Persisted events first; hide ones already shown as live session rows
    /// for the same track to avoid double-listing the current listen.
    private var displayItems: [PlayHistoryItem] {
        let sessionTrackIDs = Set(queue.historyEntries.map(\.track.id))
        var seenSession = false
        return playHistory.items.filter { item in
            if sessionTrackIDs.contains(item.trackID) {
                if seenSession { return false }
                seenSession = true
            }
            return true
        }
    }

    private var subtitle: String {
        let count = playHistory.items.count + queue.historyEntries.count
        if count == 0 { return "Nothing played yet" }
        return "\(count) play\(count == 1 ? "" : "s")"
    }

    private func seedIfNeeded() {
        guard seeded == false else { return }
        let tracks = librarySnapshots.snapshot.tracks
        guard tracks.isEmpty == false else { return }
        seeded = true
        playHistory.seedFromLibraryIfNeeded(tracks: tracks)
    }

    private func updateSummary() {
        let count = playHistory.items.count
        let duration = playHistory.items.reduce(0) { $0 + $1.duration }
        LibraryStatus.shared.summary.update(
            owner: summaryOwner,
            summary: .tracks(count: count, duration: duration)
        )
    }

    private func sessionRow(_ entry: PlaybackQueueEntry) -> some View {
        let track = entry.track
        let meta = track.audioCDMetadata(at: discogsClock.now)
        let title = meta.title.isEmpty ? track.title : meta.title
        let artist = meta.artist.isEmpty ? track.artist : meta.artist
        let album = meta.album.isEmpty ? track.album : meta.album
        return rowContent(
            title: title.isEmpty ? "Unknown" : title,
            artist: artist,
            album: album,
            duration: track.duration,
            trailing: {
                EmptyView()
            },
            context: {
                historyContextMenu(
                    trackID: track.id,
                    albumID: track.albumRelation?.id,
                    artistName: artist,
                    historyItemID: nil
                )
            }
        )
    }

    private func historyRow(_ item: PlayHistoryItem) -> some View {
        let live = librarySnapshots.snapshot.tracksByID[item.trackID]
        let albumID = live?.albumID
        let artistName = live?.artist ?? item.artist
        return rowContent(
            title: item.title.isEmpty ? "Unknown" : item.title,
            artist: item.artist,
            album: item.album,
            duration: item.duration,
            caption: item.playedAt.formatted(date: .abbreviated, time: .shortened),
            trailing: {
                EmptyView()
            },
            context: {
                historyContextMenu(
                    trackID: item.trackID,
                    albumID: albumID,
                    artistName: artistName,
                    historyItemID: item.id,
                    trackAvailable: live != nil
                )
            }
        )
    }

    private func rowContent<Trailing: View, Context: View>(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        caption: String? = nil,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder context: () -> Context
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                Text(artist.isEmpty ? "Unknown Artist" : artist)
                    .font(.caption)
                    .foregroundColor(secondaryColor)
                    .lineLimit(1)
                Text(albumLabel(album, caption: caption))
                    .font(.caption2)
                    .foregroundColor(secondaryColor)
                    .lineLimit(1)
            }
            Spacer()
            Text(formatDuration(duration))
                .font(.caption.monospacedDigit())
                .foregroundColor(secondaryColor)
            trailing()
        }
        .contentShape(Rectangle())
        .contextMenu { context() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(artist)")
    }

    private func albumLabel(_ album: String, caption: String?) -> String {
        let albumText = album.isEmpty ? "Unknown Album" : album
        guard let caption else { return albumText }
        return "\(albumText) · \(caption)"
    }

    @ViewBuilder
    private func historyContextMenu(
        trackID: UUID,
        albumID: UUID?,
        artistName: String,
        historyItemID: UUID?,
        trackAvailable: Bool = true
    ) -> some View {
        if trackAvailable {
            Button("Play Now") { actions.requestPlayNow(trackID: trackID) }
            Button("Add to Play Queue") { actions.addToQueue(trackIDs: [trackID]) }
            Button("Play Next") { actions.playNext(trackIDs: [trackID]) }
            if let albumID {
                Button("Go to Album") { actions.showAlbum(albumID: albumID) }
            }
            if artistName.isEmpty == false {
                Button("Go to Artist") { actions.showArtist(name: artistName) }
            }
            Button("Add to New Playlist") {
                actions.requestNewPlaylist(trackIDs: [trackID])
            }
        }
        if let historyItemID {
            if trackAvailable {
                Divider()
            }
            Button("Remove from History") {
                playHistory.remove(id: historyItemID)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundColor(secondaryColor)
            Text("No Play History")
                .font(.headline)
                .foregroundColor(textColor)
            Text("Tracks you listen to will appear here. History is kept across launches.")
                .font(.caption)
                .foregroundColor(secondaryColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
