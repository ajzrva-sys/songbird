import SwiftUI

@MainActor
enum PlayQueueRowAccessibilityRouting {
    static func offersPlayNext(isCurrent: Bool) -> Bool {
        isCurrent == false
    }

    static func playNow(
        entryID: PlaybackQueueEntry.ID,
        perform: (PlaybackQueueEntry.ID) -> Void
    ) {
        perform(entryID)
    }

    @discardableResult
    static func playNext(
        entryID: PlaybackQueueEntry.ID,
        isCurrent: Bool,
        perform: (PlaybackQueueEntry.ID) -> Bool
    ) -> Bool {
        guard offersPlayNext(isCurrent: isCurrent) else { return false }
        return perform(entryID)
    }
}

/// Classic play-queue pane with empty state and reorder/remove.
public struct PlayQueueView: View {
    @ObservedObject private var discogsClock = DiscogsPresentationClock.shared
    private enum QueueUndo {
        case upcoming(PlaybackQueueValueSnapshot)
        case history(PlaybackQueueValueSnapshot)
    }
    @EnvironmentObject var playbackSession: PlaybackSession
    @EnvironmentObject var queue: PlaybackQueue
    @EnvironmentObject private var librarySnapshots: LibrarySnapshotStore
    @EnvironmentObject private var actions: LibraryItemActionHandler
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedEntryID: PlaybackQueueEntry.ID?
    @State private var latestUndo: QueueUndo?
    @State private var undoMessage: String?
    @State private var summaryOwner = LibraryContentSummaryOwner()

    private var textColor: Color { SongbirdTheme.text(for: colorScheme) }
    private var secondaryColor: Color { SongbirdTheme.secondaryText(for: colorScheme) }

    private var allQueued: [Track] {
        var items: [Track] = []
        if let current = queue.currentEntry {
            items.append(current.track)
        }
        items.append(contentsOf: queue.displayedUpcomingEntries.map(\.track))
        return items
    }

    private var allQueueEntryIDs: [PlaybackQueueEntry.ID] {
        (queue.currentEntry.map { [$0.id] } ?? []) + queue.displayedUpcomingEntries.map(\.id)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Play Queue")
                    .font(.title2.bold())
                    .foregroundColor(textColor)
                Spacer()
                if queue.upcomingEntries.isEmpty == false {
                    Button("Clear Up Next") {
                        latestUndo = .upcoming(queue.clearUpcomingReturningSnapshot())
                        undoMessage = "Cleared Up Next."
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(secondaryColor)
                }
                if queue.historyEntries.isEmpty == false {
                    Button("Clear History") {
                        latestUndo = .history(queue.clearHistoryReturningSnapshot())
                        undoMessage = "Cleared playback history."
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(secondaryColor)
                }
            }
            .padding()

            if let undoMessage, latestUndo != nil {
                HStack {
                    Text(undoMessage).font(.caption).foregroundStyle(secondaryColor)
                    Button("Undo") { restoreLatestQueueSnapshot() }
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }

            ZStack {
                if allQueued.isEmpty && queue.historyEntries.isEmpty {
                    emptyState
                } else {
                    List {
                        if let current = queue.currentEntry {
                            Section("Now Playing") {
                                queueRow(current, isCurrent: true)
                            }
                        }
                        if queue.upcomingEntries.isEmpty == false {
                            Section(queue.shuffleEnabled ? "Up Next — Shuffled" : "Up Next") {
                                ForEach(queue.displayedUpcomingEntries) { entry in
                                    queueRow(entry, isCurrent: false)
                                }
                                .onMove { source, destination in
                                    queue.moveDisplayedUpcoming(
                                        fromOffsets: source,
                                        toOffset: destination
                                    )
                                }
                            }
                        }
                        if queue.historyEntries.isEmpty == false {
                            Section("Previously Played") {
                                ForEach(Array(queue.historyEntries.reversed())) { entry in
                                    historyRow(entry)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SongbirdTheme.background(for: colorScheme))
        .onAppear {
            LibraryStatus.shared.summary.activate(owner: summaryOwner)
            updateSummary()
        }
        .onChange(of: allQueueEntryIDs) { _, _ in
            updateSummary()
        }
        .onDisappear { LibraryStatus.shared.summary.clear(owner: summaryOwner) }
    }

    private func updateSummary() {
        LibraryStatus.shared.summary.update(
            owner: summaryOwner,
            summary: .tracks(
                count: allQueued.count,
                duration: allQueued.reduce(0) { $0 + $1.duration }
            )
        )
    }

    private func queueRow(_ entry: PlaybackQueueEntry, isCurrent: Bool) -> some View {
        let track = entry.track
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                DiscogsTrackAttributionView(track: track, now: discogsClock.now)
                Text(track.audioCDMetadata(at: discogsClock.now).title.isEmpty ? "Unknown" : track.audioCDMetadata(at: discogsClock.now).title)
                    .font(isCurrent ? .body.bold() : .body)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                Text("\(track.audioCDMetadata(at: discogsClock.now).artist) — \(track.audioCDMetadata(at: discogsClock.now).album)")
                    .font(.caption)
                    .foregroundColor(secondaryColor)
                    .lineLimit(1)
            }
            Spacer()
            Text(formatDuration(track.duration))
                .font(.caption.monospacedDigit())
                .foregroundColor(secondaryColor)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            actions.requestPlayQueueEntry(entryID: entry.id)
        }
        .focusable()
        .focused($focusedEntryID, equals: entry.id)
        .onKeyPress(keys: [.return, .space]) { _ in
            actions.requestPlayQueueEntry(entryID: entry.id)
            return .handled
        }
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard isCurrent == false, press.modifiers.contains(.option) else { return .ignored }
            let offset = press.key == .upArrow ? -1 : 1
            return queue.moveUpcoming(entryID: entry.id, offset: offset) ? .handled : .ignored
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            Button("Play Now") {
                PlayQueueRowAccessibilityRouting.playNow(entryID: entry.id) {
                    actions.requestPlayQueueEntry(entryID: $0)
                }
            }
            if PlayQueueRowAccessibilityRouting.offersPlayNext(isCurrent: isCurrent) {
                Button("Play Next") {
                    PlayQueueRowAccessibilityRouting.playNext(
                        entryID: entry.id,
                        isCurrent: isCurrent
                    ) {
                        queue.moveNext(entryID: $0)
                    }
                }
            }
            if let albumID = track.albumRelation?.id {
                Button("Go to Album") {
                    actions.showAlbum(albumID: albumID)
                }
            }
            Button("Go to Artist") {
                actions.showArtist(name: track.audioCDMetadata(at: discogsClock.now).artist)
            }
            Button("Add to New Playlist") {
                actions.requestNewPlaylist(trackIDs: [track.id])
            }
            Button({
                let isLoved = librarySnapshots.trackSnapshot(id: track.id)?.isLoved ?? false
                return isLoved ? "Remove from Favorites" : "Add to Favorites"
            }()) {
                let isLoved = librarySnapshots.trackSnapshot(id: track.id)?.isLoved ?? false
                actions.setTrackLoved(!isLoved, trackIDs: [track.id])
            }
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
            } else if isCurrent == false {
                Button("Play Now") { actions.requestPlayQueueEntry(entryID: entry.id) }
                Button("Play Next") { queue.moveNext(entryID: entry.id) }
                Button("Remove from Queue", role: .destructive) {
                    queue.removeUpcoming(entryID: entry.id)
                }
            }
        }
    }

    private func historyRow(_ entry: PlaybackQueueEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                DiscogsTrackAttributionView(track: entry.track, now: discogsClock.now)
                Text(entry.track.audioCDMetadata(at: discogsClock.now).title.isEmpty ? "Unknown" : entry.track.audioCDMetadata(at: discogsClock.now).title)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                Text("\(entry.track.audioCDMetadata(at: discogsClock.now).artist) — \(entry.track.audioCDMetadata(at: discogsClock.now).album)")
                    .font(.caption)
                    .foregroundColor(secondaryColor)
                    .lineLimit(1)
            }
            Spacer()
            Button("Play Again") { actions.requestPlayNow(trackID: entry.track.id) }
                .controlSize(.small)
            Button("Remove from History", systemImage: "xmark") {
                queue.removeHistory(entryID: entry.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
        }
    }

    private func restoreLatestQueueSnapshot() {
        guard let latestUndo else { return }
        switch latestUndo {
        case .upcoming(let snapshot): queue.restoreUpcoming(snapshot)
        case .history(let snapshot): queue.restoreHistory(snapshot)
        }
        self.latestUndo = nil
        undoMessage = nil
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.largeTitle)
                .foregroundColor(secondaryColor)
            Text("Play Queue is Empty")
                .font(.headline)
                .foregroundColor(textColor)
            Text("Add tracks with Add to Queue or Play Next.")
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
