import Foundation
import SwiftData

@Model
public final class Playlist {
    public var id: UUID = UUID()
    public var name: String = ""
    public var dateCreated: Date = Date()
    public var dateModified: Date = Date()
    public var smartPlaylist: Bool = false
    public var smartPlaylistRules: Data?  // JSON-encoded rules
    /// Stable key for built-in smart mixes; user playlists leave this nil/empty.
    public var systemKey: String? = nil

    public var tracks: [Track] = []

    public var isSystemSmartPlaylist: Bool {
        !(systemKey ?? "").isEmpty
    }

    public init(name: String, smart: Bool = false, systemKey: String? = nil) {
        self.id = UUID()
        self.name = name
        self.dateCreated = Date()
        self.dateModified = Date()
        self.smartPlaylist = smart
        self.systemKey = systemKey
    }
}

/// Persists manual-playlist ordering separately because SwiftData relationship
/// arrays preserve membership but do not provide stable ordering across saves.
enum PlaylistOrderStore {
    private static let key = "songbird.playlist.trackOrder.v1"
    private static let lock = NSLock()

    static func order(playlistID: UUID, membership: [UUID]) -> [UUID] {
        lock.lock()
        defer { lock.unlock() }
        let members = Set(membership)
        let stored = load()[playlistID.uuidString] ?? []
        var seen = Set<UUID>()
        let retained = stored.filter { members.contains($0) && seen.insert($0).inserted }
        return retained + membership.filter { seen.insert($0).inserted }
    }

    static func set(_ order: [UUID], playlistID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var all = load()
        all[playlistID.uuidString] = order
        save(all)
    }

    static func remove(playlistID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var all = load()
        all.removeValue(forKey: playlistID.uuidString)
        save(all)
    }

    static func snapshot(playlistIDs: Set<UUID>) -> [UUID: [UUID]] {
        lock.lock()
        defer { lock.unlock() }
        let all = load()
        return Dictionary(uniqueKeysWithValues: playlistIDs.map {
            ($0, all[$0.uuidString] ?? [])
        })
    }

    static func restore(_ snapshot: [UUID: [UUID]]) {
        lock.lock()
        defer { lock.unlock() }
        var all = load()
        for (id, order) in snapshot { all[id.uuidString] = order }
        save(all)
    }

    static func fullSnapshot() -> [UUID: [UUID]] {
        lock.lock()
        defer { lock.unlock() }
        return Dictionary(uniqueKeysWithValues: load().compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }

    static func restoreFullSnapshot(_ snapshot: [UUID: [UUID]]) {
        lock.lock()
        defer { lock.unlock() }
        save(Dictionary(uniqueKeysWithValues: snapshot.map { ($0.key.uuidString, $0.value) }))
    }

    private static func load() -> [String: [UUID]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode([String: [UUID]].self, from: data) else {
            return [:]
        }
        return value
    }

    private static func save(_ value: [String: [UUID]]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
