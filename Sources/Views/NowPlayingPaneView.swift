import SwiftUI

/// Right-sidebar Now Playing pane showing the current queue.
/// Mirrors PlayQueueView in a narrower layout that obeys the active theme.
struct NowPlayingPaneView: View {
    @ObservedObject private var discogsClock = DiscogsPresentationClock.shared
    @EnvironmentObject private var queue: PlaybackQueue
    @EnvironmentObject private var playbackPresentation: PlaybackPresentationState
    @EnvironmentObject private var actions: LibraryItemActionHandler
    @EnvironmentObject private var librarySnapshots: LibrarySnapshotStore
    @Environment(\.colorScheme) private var colorScheme

    private var textColor: Color { SongbirdTheme.text(for: colorScheme) }
    private var secondaryColor: Color { SongbirdTheme.secondaryText(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if allQueued.isEmpty {
                emptyState
            } else {
                trackList
            }
        }
        .background(SongbirdTheme.background(for: colorScheme))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.fill")
                .font(.system(size: 10))
                .foregroundColor(.accentColor)
            Text("Now Playing")
                .font(.headline)
                .foregroundColor(textColor)
            Spacer()
            Text("\(allQueued.count) \(allQueued.count == 1 ? "track" : "tracks")")
                .font(.caption)
                .foregroundColor(secondaryColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Track list

    private var trackList: some View {
        List {
            if let current = queue.currentEntry {
                Section("Now Playing") {
                    paneRow(current, isCurrent: true)
                }
            }
            if queue.upcomingEntries.isEmpty == false {
                Section("Up Next") {
                    ForEach(queue.displayedUpcomingEntries) { entry in
                        paneRow(entry, isCurrent: false)
                    }
                    .onMove { source, destination in
                        queue.moveDisplayedUpcoming(
                            fromOffsets: source,
                            toOffset: destination
                        )
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Row

    private func paneRow(_ entry: PlaybackQueueEntry, isCurrent: Bool) -> some View {
        let track = entry.track
        return HStack(spacing: 6) {
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.accentColor)
                    .frame(width: 12)
            }
            VStack(alignment: .leading, spacing: 1) {
                DiscogsTrackAttributionView(track: track, now: discogsClock.now)
                Text(track.audioCDMetadata(at: discogsClock.now).title.isEmpty ? "Unknown" : track.audioCDMetadata(at: discogsClock.now).title)
                    .font(isCurrent ? .callout.bold() : .callout)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                Text(track.audioCDMetadata(at: discogsClock.now).artist)
                    .font(.caption2)
                    .foregroundColor(secondaryColor)
                    .lineLimit(1)
            }
            Spacer()
            Text(formatDuration(track.duration))
                .font(.caption2.monospacedDigit())
                .foregroundColor(secondaryColor)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            actions.requestPlayQueueEntry(entryID: entry.id)
        }
        .contextMenu {
            if let snapshot = librarySnapshots.trackSnapshot(id: track.id) {
                TrackContextMenu(
                    track: snapshot,
                    targetIDs: [track.id],
                    playNowAction: {
                        actions.requestPlayQueueEntry(entryID: entry.id)
                    },
                    playNextAction: isCurrent ? nil : {
                        queue.moveNext(entryID: entry.id)
                    },
                    showsPlayNext: isCurrent == false,
                    removeFromQueueAction: isCurrent ? nil : {
                        queue.removeUpcoming(entryID: entry.id)
                    }
                )
                if isCurrent == false {
                    Divider()
                    Button("Move Earlier") {
                        queue.moveUpcoming(entryID: entry.id, offset: -1)
                    }
                    .disabled(queue.displayedUpcomingEntries.first?.id == entry.id)
                    Button("Move Later") {
                        queue.moveUpcoming(entryID: entry.id, offset: 1)
                    }
                    .disabled(queue.displayedUpcomingEntries.last?.id == entry.id)
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "text.alignleft")
                .font(.title2)
                .foregroundColor(secondaryColor)
            Text("Queue Empty")
                .font(.callout)
                .foregroundColor(textColor)
            Text("Add tracks to start playing.")
                .font(.caption)
                .foregroundColor(secondaryColor)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var allQueued: [Track] {
        var items: [Track] = []
        if let current = queue.currentEntry {
            items.append(current.track)
        }
        items.append(contentsOf: queue.displayedUpcomingEntries.map(\.track))
        return items
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
