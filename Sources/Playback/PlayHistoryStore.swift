import Foundation

/// One durable play-history event. Lightweight so the log can still render
/// after a track is removed from the library.
public struct PlayHistoryItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let trackID: UUID
    public let title: String
    public let artist: String
    public let album: String
    public let playedAt: Date
    public let duration: TimeInterval

    public init(
        id: UUID = UUID(),
        trackID: UUID,
        title: String,
        artist: String,
        album: String,
        playedAt: Date,
        duration: TimeInterval
    ) {
        self.id = id
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.playedAt = playedAt
        self.duration = duration
    }
}

/// Lightweight library seed row for first-open history fill-in.
public struct PlayHistorySeed: Equatable, Sendable {
    public let trackID: UUID
    public let title: String
    public let artist: String
    public let album: String
    public let lastPlayed: Date?
    public let duration: TimeInterval

    public init(
        trackID: UUID,
        title: String,
        artist: String,
        album: String,
        lastPlayed: Date?,
        duration: TimeInterval
    ) {
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.lastPlayed = lastPlayed
        self.duration = duration
    }

    public init(snapshot: LibraryTrackSnapshot) {
        self.init(
            trackID: snapshot.id,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            lastPlayed: snapshot.lastPlayed,
            duration: snapshot.duration
        )
    }
}

/// Persistent chronological play log. Session queue history remains on
/// `PlaybackQueue`; this store survives window close and relaunch.
@MainActor
public final class PlayHistoryStore: ObservableObject {
    public static let shared = PlayHistoryStore()
    public static let maxItems = 500
    public static let storageKey = "playback.historyLog"

    @Published public private(set) var items: [PlayHistoryItem] = []

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        items = Self.load(from: defaults)
    }

    /// Newest first.
    public var recentTrackIDs: [UUID] {
        items.map(\.trackID)
    }

    public func record(track: Track, playedAt: Date = Date()) {
        guard track.isAudioCDTrack == false else { return }
        let item = PlayHistoryItem(
            trackID: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            playedAt: playedAt,
            duration: track.duration
        )
        items.insert(item, at: 0)
        if items.count > Self.maxItems {
            items.removeLast(items.count - Self.maxItems)
        }
        persist()
    }

    public func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    public func clear() {
        items.removeAll()
        persist()
    }

    /// Folds library `lastPlayed` data into the log once when the store is empty,
    /// so existing play counts become immediately browsable.
    public func seedFromLibraryIfNeeded(tracks: [LibraryTrackSnapshot]) {
        seedFromLibraryIfNeeded(tracks.map(PlayHistorySeed.init(snapshot:)))
    }

    public func seedFromLibraryIfNeeded(_ seeds: [PlayHistorySeed]) {
        guard items.isEmpty else { return }
        let seeded = seeds
            .compactMap { seed -> PlayHistoryItem? in
                guard let playedAt = seed.lastPlayed else { return nil }
                return PlayHistoryItem(
                    trackID: seed.trackID,
                    title: seed.title,
                    artist: seed.artist,
                    album: seed.album,
                    playedAt: playedAt,
                    duration: seed.duration
                )
            }
            .sorted { $0.playedAt > $1.playedAt }
        guard seeded.isEmpty == false else { return }
        items = Array(seeded.prefix(Self.maxItems))
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(items)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            // Keep the in-memory list usable even if defaults write fails.
        }
    }

    private static func load(from defaults: UserDefaults) -> [PlayHistoryItem] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([PlayHistoryItem].self, from: data)) ?? []
    }
}
