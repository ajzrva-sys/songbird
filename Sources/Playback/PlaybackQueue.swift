import Combine
import Foundation

/// One occurrence of a library track in the playback queue.
///
/// Track IDs describe library identity. Queue-entry IDs describe a specific
/// occurrence, allowing the same track to appear more than once without
/// confusing SwiftUI row identity or queue movement commands.
public struct PlaybackQueueEntry: Identifiable {
    public let id: UUID
    public let track: Track

    public init(id: UUID = UUID(), track: Track) {
        self.id = id
        self.track = track
    }
}

public struct PlaybackQueueValueSnapshot {
    fileprivate let entries: [PlaybackQueueEntry]
}

public struct PlaybackQueueTrackReferenceSnapshot {
    fileprivate let current: PlaybackQueueEntry?
    fileprivate let upcoming: [PlaybackQueueEntry]
    fileprivate let history: [PlaybackQueueEntry]
}

public struct PlaybackQueueIdentityEntry: Equatable, Sendable {
    public let entryID: UUID
    public let trackID: UUID
}

public struct PlaybackQueueIdentitySnapshot: Equatable, Sendable {
    public let current: PlaybackQueueIdentityEntry?
    public let upcoming: [PlaybackQueueIdentityEntry]
    public let history: [PlaybackQueueIdentityEntry]
    public let shuffleOrder: [UUID]
    public let shuffleEnabled: Bool
    public let repeatMode: String
}

@MainActor
public final class PlaybackQueue: ObservableObject {
    @Published public private(set) var currentEntry: PlaybackQueueEntry?
    @Published public private(set) var upcomingEntries: [PlaybackQueueEntry] = [] {
        didSet { rebuildShuffleBagIfNeeded() }
    }
    @Published public private(set) var historyEntries: [PlaybackQueueEntry] = []
    @Published public var shuffleEnabled: Bool = false {
        didSet {
            if shuffleEnabled {
                rebuildShuffleBag()
            } else {
                shuffleOrder.removeAll()
            }
        }
    }
    @Published public var repeatMode: RepeatMode = .off
    @Published public private(set) var effectiveOrderRevision: UInt = 0

    /// Stable permutation of upcoming queue-entry IDs while shuffle is on.
    private var shuffleOrder: [PlaybackQueueEntry.ID] = []

    public var currentTrack: Track? { currentEntry?.track }
    public var upcomingTracks: [Track] { upcomingEntries.map(\.track) }
    public var history: [Track] { historyEntries.map(\.track) }

    /// Rows in the order they will actually play.
    public var displayedUpcomingEntries: [PlaybackQueueEntry] {
        guard shuffleEnabled else { return upcomingEntries }
        ensureShuffleBag()
        let entriesByID = Dictionary(uniqueKeysWithValues: upcomingEntries.map { ($0.id, $0) })
        return shuffleOrder.compactMap { entriesByID[$0] }
    }

    public enum RepeatMode: String, CaseIterable {
        case off, all, one

        public var systemImage: String {
            switch self {
            case .off, .all: "repeat"
            case .one: "repeat.1"
            }
        }

        public var help: String {
            switch self {
            case .off: "Repeat Off"
            case .all: "Repeat All"
            case .one: "Repeat One"
            }
        }
    }

    public init() {}

    @discardableResult
    public func enqueue(_ tracks: [Track]) -> [PlaybackQueueEntry] {
        let entries = tracks.map { PlaybackQueueEntry(track: $0) }
        upcomingEntries.append(contentsOf: entries)
        return entries
    }

    /// Replaces playback with one ordered collection without changing the
    /// user's global shuffle preference.
    @discardableResult
    public func replace(with tracks: [Track], startingAt index: Int = 0) -> Track? {
        guard tracks.indices.contains(index) else { return nil }
        let entries = tracks.map { PlaybackQueueEntry(track: $0) }
        currentEntry = entries[index]
        upcomingEntries = Array(entries.dropFirst(index + 1))
        historyEntries.removeAll()
        if shuffleEnabled { rebuildShuffleBag() }
        return entries[index].track
    }

    public func setCurrentTrack(_ track: Track) {
        if currentEntry?.track.id == track.id {
            return
        }
        currentEntry = PlaybackQueueEntry(track: track)
    }

    @discardableResult
    public func enqueueNext(_ track: Track) -> PlaybackQueueEntry {
        let entry = PlaybackQueueEntry(track: track)
        upcomingEntries.insert(entry, at: 0)
        if shuffleEnabled {
            shuffleOrder.removeAll { $0 == entry.id }
            shuffleOrder.insert(entry.id, at: 0)
        }
        markEffectiveOrderChanged()
        return entry
    }

    @discardableResult
    public func enqueueNext(_ tracks: [Track]) -> [PlaybackQueueEntry] {
        let entries = tracks.map { PlaybackQueueEntry(track: $0) }
        guard entries.isEmpty == false else { return [] }
        upcomingEntries.insert(contentsOf: entries, at: 0)
        if shuffleEnabled {
            let ids = Set(entries.map(\.id))
            shuffleOrder.removeAll { ids.contains($0) }
            shuffleOrder.insert(contentsOf: entries.map(\.id), at: 0)
        }
        markEffectiveOrderChanged()
        return entries
    }

    /// Moves the selected occurrence to the front and removes other queued
    /// occurrences of the same library track.
    @discardableResult
    public func moveNext(entryID: PlaybackQueueEntry.ID) -> Bool {
        guard let selected = upcomingEntries.first(where: { $0.id == entryID }) else { return false }
        let duplicateEntryIDs = Set(upcomingEntries.lazy
            .filter { $0.track.id == selected.track.id }
            .map(\.id))
        upcomingEntries.removeAll { duplicateEntryIDs.contains($0.id) }
        upcomingEntries.insert(selected, at: 0)
        if shuffleEnabled {
            shuffleOrder.removeAll { duplicateEntryIDs.contains($0) }
            shuffleOrder.insert(selected.id, at: 0)
        }
        markEffectiveOrderChanged()
        return true
    }

    /// Compatibility command for library-ID callers. Queue rows should use
    /// `moveNext(entryID:)` so duplicate occurrences remain deterministic.
    @discardableResult
    public func moveNext(trackID: UUID) -> Bool {
        guard let entry = displayedUpcomingEntries.first(where: { $0.track.id == trackID }) else {
            return false
        }
        return moveNext(entryID: entry.id)
    }

    @discardableResult
    public func removeUpcoming(entryID: PlaybackQueueEntry.ID) -> Bool {
        guard let index = upcomingEntries.firstIndex(where: { $0.id == entryID }) else { return false }
        upcomingEntries.remove(at: index)
        shuffleOrder.removeAll { $0 == entryID }
        return true
    }

    /// Removes every queued occurrence of one library track.
    @discardableResult
    public func removeUpcoming(trackID: UUID) -> Bool {
        let entryIDs = Set(upcomingEntries.lazy
            .filter { $0.track.id == trackID }
            .map(\.id))
        guard entryIDs.isEmpty == false else { return false }
        upcomingEntries.removeAll { entryIDs.contains($0.id) }
        shuffleOrder.removeAll { entryIDs.contains($0) }
        return true
    }

    @discardableResult
    public func moveUpcoming(entryID: PlaybackQueueEntry.ID, offset: Int) -> Bool {
        guard offset != 0 else { return false }
        if shuffleEnabled {
            ensureShuffleBag()
            guard let source = shuffleOrder.firstIndex(of: entryID) else { return false }
            let destination = min(max(source + offset, 0), shuffleOrder.count - 1)
            guard destination != source else { return false }
            let id = shuffleOrder.remove(at: source)
            shuffleOrder.insert(id, at: destination)
            markEffectiveOrderChanged()
            objectWillChange.send()
            return true
        }

        guard let source = upcomingEntries.firstIndex(where: { $0.id == entryID }) else { return false }
        let destination = min(max(source + offset, 0), upcomingEntries.count - 1)
        guard destination != source else { return false }
        let entry = upcomingEntries.remove(at: source)
        upcomingEntries.insert(entry, at: destination)
        markEffectiveOrderChanged()
        return true
    }

    @discardableResult
    public func moveUpcoming(trackID: UUID, offset: Int) -> Bool {
        guard let entry = displayedUpcomingEntries.first(where: { $0.track.id == trackID }) else {
            return false
        }
        return moveUpcoming(entryID: entry.id, offset: offset)
    }

    public func moveDisplayedUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        if shuffleEnabled {
            ensureShuffleBag()
            shuffleOrder.move(fromOffsets: source, toOffset: destination)
            markEffectiveOrderChanged()
            objectWillChange.send()
        } else {
            upcomingEntries.move(fromOffsets: source, toOffset: destination)
            markEffectiveOrderChanged()
        }
    }

    public func peekNextEntry() -> PlaybackQueueEntry? {
        displayedUpcomingEntries.first
    }

    public func peekNext() -> Track? {
        peekNextEntry()?.track
    }

    @discardableResult
    public func advanceToNext(entryID: PlaybackQueueEntry.ID) -> Track? {
        guard let index = upcomingEntries.firstIndex(where: { $0.id == entryID }) else { return nil }
        if let currentEntry {
            historyEntries.append(currentEntry)
            if historyEntries.count > 500 { historyEntries.removeFirst() }
        }
        let entry = upcomingEntries.remove(at: index)
        shuffleOrder.removeAll { $0 == entry.id }
        currentEntry = entry
        return entry.track
    }

    public func next() -> Track? {
        guard let entry = peekNextEntry() else { return nil }
        return advanceToNext(entryID: entry.id)
    }

    public func peekPreviousEntry() -> PlaybackQueueEntry? {
        historyEntries.last
    }

    @discardableResult
    public func advanceToPrevious(entryID: PlaybackQueueEntry.ID) -> Track? {
        guard historyEntries.last?.id == entryID,
              let previous = historyEntries.popLast() else { return nil }
        if let currentEntry {
            upcomingEntries.insert(currentEntry, at: 0)
            if shuffleEnabled {
                shuffleOrder.removeAll { $0 == currentEntry.id }
                shuffleOrder.insert(currentEntry.id, at: 0)
            }
        }
        currentEntry = previous
        return previous.track
    }

    public func previous() -> Track? {
        guard let entry = peekPreviousEntry() else { return nil }
        return advanceToPrevious(entryID: entry.id)
    }

    @discardableResult
    public func promote(entryID: PlaybackQueueEntry.ID) -> Track? {
        guard let entry = upcomingEntries.first(where: { $0.id == entryID }) else { return nil }
        if let currentEntry {
            historyEntries.append(currentEntry)
            if historyEntries.count > 500 { historyEntries.removeFirst() }
        }
        upcomingEntries.removeAll { $0.id == entry.id }
        shuffleOrder.removeAll { $0 == entry.id }
        currentEntry = entry
        return entry.track
    }

    /// Promotes the first matching occurrence. Backend handoff uses this
    /// compatibility path because it pins a Track before playback begins.
    @discardableResult
    public func promote(_ track: Track) -> Track {
        if let entry = displayedUpcomingEntries.first(where: { $0.track.id == track.id }),
           let promoted = promote(entryID: entry.id) {
            return promoted
        }
        if currentEntry?.track.id != track.id, let currentEntry {
            historyEntries.append(currentEntry)
            if historyEntries.count > 500 { historyEntries.removeFirst() }
        }
        currentEntry = PlaybackQueueEntry(track: track)
        return track
    }

    public func clear() {
        upcomingEntries.removeAll()
        historyEntries.removeAll()
        shuffleOrder.removeAll()
        currentEntry = nil
    }

    public func clearUpcoming() {
        upcomingEntries.removeAll()
        shuffleOrder.removeAll()
    }

    @discardableResult
    public func clearUpcomingReturningSnapshot() -> PlaybackQueueValueSnapshot {
        let snapshot = PlaybackQueueValueSnapshot(entries: upcomingEntries)
        clearUpcoming()
        return snapshot
    }

    public func restoreUpcoming(_ snapshot: PlaybackQueueValueSnapshot) {
        upcomingEntries = snapshot.entries
        if shuffleEnabled { rebuildShuffleBag() }
    }

    @discardableResult
    public func clearHistoryReturningSnapshot() -> PlaybackQueueValueSnapshot {
        let snapshot = PlaybackQueueValueSnapshot(entries: historyEntries)
        historyEntries.removeAll()
        return snapshot
    }

    public func restoreHistory(_ snapshot: PlaybackQueueValueSnapshot) {
        historyEntries = snapshot.entries
    }

    @discardableResult
    public func removeHistory(entryID: PlaybackQueueEntry.ID) -> Bool {
        guard let index = historyEntries.firstIndex(where: { $0.id == entryID }) else {
            return false
        }
        historyEntries.remove(at: index)
        return true
    }

#if DEBUG
    func setStateForTesting(current: Track?, upcoming: [Track], history: [Track]) {
        currentEntry = current.map { PlaybackQueueEntry(track: $0) }
        upcomingEntries = upcoming.map { PlaybackQueueEntry(track: $0) }
        historyEntries = history.map { PlaybackQueueEntry(track: $0) }
        if shuffleEnabled { rebuildShuffleBag() }
    }
#endif

    /// Removes all queue/history occurrences for library track IDs.
    /// Returns true when the current track was removed.
    @discardableResult
    public func removeTracks(trackIDs: Set<UUID>) -> Bool {
        upcomingEntries.removeAll { trackIDs.contains($0.track.id) }
        historyEntries.removeAll { trackIDs.contains($0.track.id) }
        shuffleOrder.removeAll { id in
            upcomingEntries.contains(where: { $0.id == id }) == false
        }
        let removedCurrent = currentEntry.map { trackIDs.contains($0.track.id) } ?? false
        if removedCurrent { currentEntry = nil }
        return removedCurrent
    }

    /// Repoints every queue/history occurrence at a consolidated library track
    /// while retaining each queue-entry identity and position.
    @discardableResult
    public func replaceTrackReferences(
        from trackIDs: Set<UUID>,
        with replacement: Track
    ) -> PlaybackQueueTrackReferenceSnapshot {
        let snapshot = PlaybackQueueTrackReferenceSnapshot(
            current: currentEntry,
            upcoming: upcomingEntries,
            history: historyEntries
        )
        guard trackIDs.isEmpty == false else { return snapshot }
        if let currentEntry, trackIDs.contains(currentEntry.track.id) {
            self.currentEntry = PlaybackQueueEntry(id: currentEntry.id, track: replacement)
        }
        upcomingEntries = upcomingEntries.map { entry in
            trackIDs.contains(entry.track.id)
                ? PlaybackQueueEntry(id: entry.id, track: replacement)
                : entry
        }
        historyEntries = historyEntries.map { entry in
            trackIDs.contains(entry.track.id)
                ? PlaybackQueueEntry(id: entry.id, track: replacement)
                : entry
        }
        return snapshot
    }

    public func restoreTrackReferences(_ snapshot: PlaybackQueueTrackReferenceSnapshot) {
        currentEntry = snapshot.current
        upcomingEntries = snapshot.upcoming
        historyEntries = snapshot.history
    }

    @discardableResult
    public func removeEntries(where shouldRemove: (Track) -> Bool) -> Bool {
        upcomingEntries.removeAll { shouldRemove($0.track) }
        historyEntries.removeAll { shouldRemove($0.track) }
        shuffleOrder.removeAll { id in
            upcomingEntries.contains(where: { $0.id == id }) == false
        }
        let removedCurrent = currentEntry.map { shouldRemove($0.track) } ?? false
        if removedCurrent { currentEntry = nil }
        return removedCurrent
    }

    public var replayTracks: [Track] {
        historyEntries.map(\.track) + (currentEntry.map { [$0.track] } ?? [])
    }

    public func identitySnapshot() -> PlaybackQueueIdentitySnapshot {
        PlaybackQueueIdentitySnapshot(
            current: currentEntry.map { .init(entryID: $0.id, trackID: $0.track.id) },
            upcoming: upcomingEntries.map { .init(entryID: $0.id, trackID: $0.track.id) },
            history: historyEntries.map { .init(entryID: $0.id, trackID: $0.track.id) },
            shuffleOrder: shuffleOrder,
            shuffleEnabled: shuffleEnabled,
            repeatMode: repeatMode.rawValue
        )
    }

    @discardableResult
    public func restoreIdentitySnapshot(
        _ snapshot: PlaybackQueueIdentitySnapshot,
        resolve: (UUID) -> Track?
    ) -> Bool {
        let all = (snapshot.current.map { [$0] } ?? []) + snapshot.upcoming + snapshot.history
        var tracks: [UUID: Track] = [:]
        for entry in all {
            guard let track = resolve(entry.trackID) else { return false }
            tracks[entry.trackID] = track
        }
        func queueEntry(_ value: PlaybackQueueIdentityEntry) -> PlaybackQueueEntry {
            PlaybackQueueEntry(id: value.entryID, track: tracks[value.trackID]!)
        }
        currentEntry = snapshot.current.map(queueEntry)
        upcomingEntries = snapshot.upcoming.map(queueEntry)
        historyEntries = snapshot.history.map(queueEntry)
        shuffleEnabled = snapshot.shuffleEnabled
        repeatMode = RepeatMode(rawValue: snapshot.repeatMode) ?? .off
        shuffleOrder = snapshot.shuffleOrder.filter { id in
            upcomingEntries.contains { $0.id == id }
        }
        markEffectiveOrderChanged()
        return true
    }

    // MARK: - Shuffle bag

    private func rebuildShuffleBagIfNeeded() {
        guard shuffleEnabled else { return }
        ensureShuffleBag()
    }

    private func ensureShuffleBag() {
        guard shuffleEnabled else { return }
        let upcomingIDs = Set(upcomingEntries.map(\.id))
        shuffleOrder.removeAll { upcomingIDs.contains($0) == false }
        let known = Set(shuffleOrder)
        let missing = upcomingEntries.map(\.id).filter { known.contains($0) == false }
        if missing.isEmpty == false {
            shuffleOrder.append(contentsOf: missing.shuffled())
        }
    }

    private func rebuildShuffleBag() {
        shuffleOrder = upcomingEntries.map(\.id).shuffled()
    }

    private func markEffectiveOrderChanged() {
        effectiveOrderRevision &+= 1
    }
}

private extension Array {
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { self[$0] }
        for index in source.sorted(by: >) {
            remove(at: index)
        }
        let removedBeforeDestination = source.count { $0 < destination }
        let insertionIndex = Swift.max(0, Swift.min(count, destination - removedBeforeDestination))
        insert(contentsOf: moving, at: insertionIndex)
    }
}
