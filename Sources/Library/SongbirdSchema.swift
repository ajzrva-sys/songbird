import Foundation
import SwiftData

/// Versioned schemas so future attribute adds can use explicit migration stages.
public enum SongbirdSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Track.self, Album.self, Artist.self, Playlist.self]
    }

    @Model
    public final class Track {
        public var id: UUID
        public var title: String
        public var artist: String
        public var album: String
        public var albumArtist: String
        public var genre: String = ""
        public var composer: String = ""
        public var comment: String = ""
        public var year: Int = 0
        public var trackNumber: Int = 0
        public var trackTotal: Int = 0
        public var discNumber: Int = 0
        public var discTotal: Int = 0
        public var beatsPerMinute: Int = 0
        public var duration: TimeInterval = 0
        public var fileSize: Int64 = 0
        public var path: String = ""
        public var dateAdded: Date = Date()
        public var dateModified: Date = Date()
        public var lastPlayed: Date?
        public var playCount: Int = 0
        public var rating: Int = 0
        public var bitrate: Int = 0
        public var sampleRate: Int = 0
        public var artworkData: Data?
        public var checksum: String = ""

        @Relationship(inverse: \SongbirdSchemaV1.Album.tracks)
        public var albumRelation: SongbirdSchemaV1.Album?

        @Relationship(inverse: \SongbirdSchemaV1.Artist.tracks)
        public var artistRelation: SongbirdSchemaV1.Artist?

        public init(path: String) {
            id = UUID()
            title = ""
            artist = "Unknown Artist"
            album = "Unknown Album"
            albumArtist = "Unknown Artist"
            self.path = path
        }
    }

    @Model
    public final class Album {
        public var id: UUID
        public var title: String
        public var artist: String
        public var year: Int
        public var artworkData: Data?
        public var dateAdded: Date
        public var tracks: [SongbirdSchemaV1.Track] = []

        public init(title: String, artist: String = "Unknown Artist", year: Int = 0) {
            id = UUID()
            self.title = title
            self.artist = artist
            self.year = year
            dateAdded = Date()
        }
    }

    @Model
    public final class Artist {
        public var id: UUID
        public var name: String
        public var dateAdded: Date
        public var tracks: [SongbirdSchemaV1.Track] = []

        public init(name: String) {
            id = UUID()
            self.name = name
            dateAdded = Date()
        }
    }

    @Model
    public final class Playlist {
        public var id: UUID = UUID()
        public var name: String = ""
        public var dateCreated: Date = Date()
        public var dateModified: Date = Date()
        public var smartPlaylist: Bool = false
        public var smartPlaylistRules: Data?
        public var systemKey: String?
        public var tracks: [SongbirdSchemaV1.Track] = []

        public init(name: String) {
            id = UUID()
            self.name = name
        }
    }
}

public enum SongbirdSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Track.self, Album.self, Artist.self, Playlist.self]
    }
}

public enum SongbirdSchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Track.self, Album.self, Artist.self, Playlist.self, AlbumFavorite.self]
    }
}

public enum SongbirdSchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Track.self, Album.self, Artist.self, Playlist.self, AlbumFavorite.self, TrackFavorite.self]
    }
}

public enum SongbirdMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SongbirdSchemaV1.self, SongbirdSchemaV2.self, SongbirdSchemaV3.self, SongbirdSchemaV4.self]
    }

    public static var stages: [MigrationStage] {
        [
            .custom(
                fromVersion: SongbirdSchemaV1.self,
                toVersion: SongbirdSchemaV2.self,
                willMigrate: { context in
                    try reconcileDuplicatePaths(in: context)
                },
                didMigrate: nil
            ),
            .lightweight(
                fromVersion: SongbirdSchemaV2.self,
                toVersion: SongbirdSchemaV3.self
            ),
            .custom(
                fromVersion: SongbirdSchemaV3.self,
                toVersion: SongbirdSchemaV4.self,
                willMigrate: { context in
                    try copyTrackLoveStateToTrackFavorite(in: context)
                },
                didMigrate: nil
            ),
        ]
    }

    private static func reconcileDuplicatePaths(in context: ModelContext) throws {
        let tracks = try context.fetch(FetchDescriptor<SongbirdSchemaV1.Track>())
        let playlists = try context.fetch(FetchDescriptor<SongbirdSchemaV1.Playlist>())
        var byPath: [String: [SongbirdSchemaV1.Track]] = [:]

        for track in tracks {
            let standardized = URL(fileURLWithPath: track.path).standardizedFileURL.path
            track.path = standardized
            byPath[standardized, default: []].append(track)
        }

        for group in byPath.values where group.count > 1 {
            let sorted = group.sorted { $0.dateAdded < $1.dateAdded }
            guard let survivor = sorted.first else { continue }
            let newest = group.max { $0.dateModified < $1.dateModified } ?? survivor

            survivor.title = newest.title
            survivor.artist = newest.artist
            survivor.album = newest.album
            survivor.albumArtist = newest.albumArtist
            survivor.genre = newest.genre
            survivor.composer = newest.composer
            survivor.comment = newest.comment
            survivor.year = newest.year
            survivor.trackNumber = newest.trackNumber
            survivor.trackTotal = newest.trackTotal
            survivor.discNumber = newest.discNumber
            survivor.discTotal = newest.discTotal
            survivor.beatsPerMinute = newest.beatsPerMinute
            survivor.duration = newest.duration
            survivor.fileSize = newest.fileSize
            survivor.dateModified = newest.dateModified
            survivor.bitrate = newest.bitrate
            survivor.sampleRate = newest.sampleRate
            survivor.artworkData = newest.artworkData
            survivor.checksum = newest.checksum
            survivor.albumRelation = newest.albumRelation
            survivor.artistRelation = newest.artistRelation
            survivor.rating = group.map(\.rating).max() ?? survivor.rating
            survivor.playCount = group.map(\.playCount).max() ?? survivor.playCount
            survivor.lastPlayed = group.compactMap(\.lastPlayed).max()

            for playlist in playlists {
                let containsDuplicate = playlist.tracks.contains { candidate in
                    sorted.dropFirst().contains { $0 === candidate }
                }
                guard containsDuplicate else { continue }
                if !playlist.tracks.contains(where: { $0 === survivor }) {
                    playlist.tracks.append(survivor)
                }
                playlist.tracks.removeAll { candidate in
                    sorted.dropFirst().contains { $0 === candidate }
                }
            }

            for duplicate in sorted.dropFirst() {
                context.delete(duplicate)
            }
        }

        try context.save()

        let survivingTracks = try context.fetch(FetchDescriptor<SongbirdSchemaV1.Track>())
        let usedAlbumIDs = Set(survivingTracks.compactMap(\.albumRelation?.id))
        let usedArtistIDs = Set(survivingTracks.compactMap(\.artistRelation?.id))
        for album in try context.fetch(FetchDescriptor<SongbirdSchemaV1.Album>())
            where !usedAlbumIDs.contains(album.id) {
            context.delete(album)
        }
        for artist in try context.fetch(FetchDescriptor<SongbirdSchemaV1.Artist>())
            where !usedArtistIDs.contains(artist.id) {
            context.delete(artist)
        }
        try context.save()
    }

    /// Copy existing track love state (rating > 0) into TrackFavorite records.
    /// This runs as a custom willMigrate block on the V3→V4 migration.
    /// Idempotent: TrackFavorite.trackID has @Attribute(.unique).
    private static func copyTrackLoveStateToTrackFavorite(in context: ModelContext) throws {
        let tracks = try context.fetch(FetchDescriptor<Track>())
        for track in tracks where track.rating > 0 {
            let favorite = TrackFavorite(trackID: track.id, dateAdded: track.lastPlayed ?? Date())
            context.insert(favorite)
        }
        try context.save()
    }
}

/// Runtime isolation embedded into a packaged usability app so reopening the
/// bundle cannot silently fall back to the user's normal Songbird library.
public enum SongbirdUIRuntime {
    public static let testingEnvironmentKey = "SONGBIRD_UI_TESTING"
    public static let testingInfoDictionaryKey = "SongbirdUITesting"
    public static let testRootInfoDictionaryKey = "SongbirdUITestRoot"
    public static let importSetupCompletedInfoDictionaryKey = "SongbirdImportSetupCompleted"

    public static func isTesting(
        environment: [String: String],
        infoDictionary: [String: Any]
    ) -> Bool {
        environment[testingEnvironmentKey] == "1"
            || boolValue(infoDictionary[testingInfoDictionaryKey])
    }

    public static func testRoot(
        environment: [String: String],
        infoDictionary: [String: Any]
    ) -> String? {
        if let environmentRoot = environment[MediaLibraryStore.uiTestRootEnvironmentKey] {
            return environmentRoot
        }
        guard isTesting(environment: environment, infoDictionary: infoDictionary) else {
            return nil
        }
        return infoDictionary[testRootInfoDictionaryKey] as? String
    }

    public static func importSetupIsCompleted(
        environment: [String: String],
        infoDictionary: [String: Any]
    ) -> Bool {
        guard isTesting(environment: environment, infoDictionary: infoDictionary) else {
            return false
        }
        return boolValue(infoDictionary[importSetupCompletedInfoDictionaryKey])
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            return ["1", "true", "yes"].contains(value.lowercased())
        }
        return false
    }
}

/// Paths and one-time move helpers for the Songbird SwiftData store.
public enum MediaLibraryStore {
    public static let uiTestRootEnvironmentKey = "SONGBIRD_UI_TEST_ROOT"

    public enum ConfigurationError: Error, LocalizedError, Equatable {
        case emptyUITestRoot
        case relativeUITestRoot(String)
        case unsafeUITestRoot(String)

        public var errorDescription: String? {
            switch self {
            case .emptyUITestRoot:
                return "SONGBIRD_UI_TEST_ROOT cannot be empty."
            case .relativeUITestRoot(let path):
                return "SONGBIRD_UI_TEST_ROOT must be an absolute path, not \(path)."
            case .unsafeUITestRoot(let path):
                return "SONGBIRD_UI_TEST_ROOT cannot use \(path) because it could contain the real Songbird library."
            }
        }
    }

    public static var applicationSupportDirectory: URL {
        let defaultDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        do {
            return try resolvedApplicationSupportDirectory(
                environment: ProcessInfo.processInfo.environment,
                packagedUITestRoot: SongbirdUIRuntime.testRoot(
                    environment: ProcessInfo.processInfo.environment,
                    infoDictionary: Bundle.main.infoDictionary ?? [:]
                ),
                defaultDirectory: defaultDirectory
            )
        } catch {
            // A malformed test override must never silently fall back to the
            // user's real library. Failing at launch is the safe behavior.
            fatalError(error.localizedDescription)
        }
    }

    /// Resolves the test-only store root without mutating process-wide state.
    ///
    /// When `SONGBIRD_UI_TEST_ROOT` is absent, this returns the normal
    /// Application Support directory. When present, the path must be absolute
    /// and must not be `/` or an ancestor of the real Songbird library.
    public static func resolvedApplicationSupportDirectory(
        environment: [String: String],
        packagedUITestRoot: String? = nil,
        defaultDirectory: URL
    ) throws -> URL {
        guard let configuredRoot = environment[uiTestRootEnvironmentKey] ?? packagedUITestRoot else {
            return defaultDirectory.standardizedFileURL
        }

        let trimmedRoot = configuredRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedRoot.isEmpty == false else {
            throw ConfigurationError.emptyUITestRoot
        }
        guard (trimmedRoot as NSString).isAbsolutePath else {
            throw ConfigurationError.relativeUITestRoot(trimmedRoot)
        }

        let candidate = URL(fileURLWithPath: trimmedRoot, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let realSongbirdDirectory = defaultDirectory
            .appendingPathComponent("Songbird", isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let candidatePath = candidate.path
        let candidatePrefix = candidatePath.hasSuffix("/")
            ? candidatePath
            : candidatePath + "/"

        guard candidatePath != "/",
              realSongbirdDirectory.path != candidatePath,
              realSongbirdDirectory.path.hasPrefix(candidatePrefix) == false else {
            throw ConfigurationError.unsafeUITestRoot(candidatePath)
        }
        return candidate
    }

    public static var songbirdDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Songbird", isDirectory: true)
    }

    public static var libraryStoreURL: URL {
        songbirdDirectory.appendingPathComponent("library.store")
    }

    public static var legacyDefaultStoreURL: URL {
        applicationSupportDirectory.appendingPathComponent("default.store")
    }

    public static func storeSidecars(for base: URL) -> [URL] {
        let path = base.path
        return [
            base,
            URL(fileURLWithPath: path + "-shm"),
            URL(fileURLWithPath: path + "-wal"),
        ]
    }

    /// Ensures `Songbird/` exists and moves `default.store*` → `Songbird/library.store*` once.
    @discardableResult
    public static func migrateLegacyStoreIfNeeded(fileManager: FileManager = .default) -> Bool {
        try? fileManager.createDirectory(at: songbirdDirectory, withIntermediateDirectories: true)
        let dest = libraryStoreURL
        let legacy = legacyDefaultStoreURL
        guard !fileManager.fileExists(atPath: dest.path),
              fileManager.fileExists(atPath: legacy.path) else {
            return false
        }
        for file in storeSidecars(for: legacy) where fileManager.fileExists(atPath: file.path) {
            let suffix: String
            if file.path.hasSuffix("-shm") {
                suffix = "-shm"
            } else if file.path.hasSuffix("-wal") {
                suffix = "-wal"
            } else {
                suffix = ""
            }
            let target = URL(fileURLWithPath: dest.path + suffix)
            try? fileManager.moveItem(at: file, to: target)
        }
        return true
    }

    @discardableResult
    public static func backupStore(
        at base: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let stamp = Int(Date().timeIntervalSince1970)
        let backupBase = base.deletingLastPathComponent()
            .appendingPathComponent("library-backup-\(stamp).store")
        for file in storeSidecars(for: base) where fileManager.fileExists(atPath: file.path) {
            let suffix: String
            if file.path.hasSuffix("-shm") {
                suffix = "-shm"
            } else if file.path.hasSuffix("-wal") {
                suffix = "-wal"
            } else {
                suffix = ""
            }
            let dest = URL(fileURLWithPath: backupBase.path + suffix)
            try fileManager.copyItem(at: file, to: dest)
        }
        return backupBase
    }

    public static func removeStore(at base: URL, fileManager: FileManager = .default) {
        for file in storeSidecars(for: base) where fileManager.fileExists(atPath: file.path) {
            try? fileManager.removeItem(at: file)
        }
    }
}
