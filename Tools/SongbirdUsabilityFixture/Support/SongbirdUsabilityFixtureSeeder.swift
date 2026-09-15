import AppKit
import CryptoKit
import Foundation
import SongbirdLib
import SwiftData

public enum SongbirdUsabilityFixtureProfile: String, CaseIterable, Codable, Sendable {
    case empty
    case standard
    case health
    case large
}

public struct SongbirdUsabilityFixtureManifest: Codable, Equatable, Sendable {
    public struct MediaFileEntry: Codable, Equatable, Sendable {
        public let path: String
        public let sha256: String
    }

    public struct FolderEntry: Codable, Equatable, Sendable {
        public let purpose: String
        public let path: String
        public let intendedMode: LibraryFolderMode
        public let configured: Bool
        public let available: Bool
        public let mediaFiles: [MediaFileEntry]
    }

    public struct PlaylistEntry: Codable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let isSmart: Bool
        public let systemKey: String?
        public let trackIDs: [UUID]
    }

    public struct AlbumEntry: Codable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let artist: String
        public let hasArtwork: Bool
        public let isFavorite: Bool
    }

    public struct TrackEntry: Codable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let artist: String
        public let album: String
        public let path: String
        public let fileExists: Bool
        public let isFavorite: Bool
    }

    public let schemaVersion: Int
    public let generationSeed: UInt64
    public let generatorRevision: String
    public let profile: SongbirdUsabilityFixtureProfile
    public let storePath: String
    public let mediaDirectory: String
    public let albums: [AlbumEntry]
    public let tracks: [TrackEntry]
    public let playlists: [PlaylistEntry]
    public let folders: [FolderEntry]
    public let playlistCount: Int

    public var albumCount: Int { albums.count }
    public var trackCount: Int { tracks.count }
}

public struct SongbirdUsabilityStateReport: Codable, Equatable, Sendable {
    public struct TrackState: Codable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let artist: String
        public let album: String
        public let genre: String
        public let comments: String
        public let rating: Int
        public let isFavorite: Bool
        public let path: String
        public let fileExists: Bool
    }

    public struct PlaylistState: Codable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let isSmart: Bool
        public let systemKey: String?
        public let orderedTrackIDs: [UUID]
    }

    public struct MediaState: Codable, Equatable, Sendable {
        public let path: String
        public let fileExists: Bool
        public let sha256: String?
    }

    public let fixture: SongbirdUsabilityFixtureProfile
    public let tracks: [TrackState]
    public let playlists: [PlaylistState]
    public let folders: [LibraryFolderConfiguration]
    public let media: [MediaState]
}

public enum SongbirdUsabilityFixtureError: Error, LocalizedError, Equatable {
    case missingRootEnvironment
    case invalidLargeTrackCount(Int)
    case artworkEncodingFailed
    case manifestMissing(String)
    case verificationFailed(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .missingRootEnvironment:
            return "Set SONGBIRD_UI_TEST_ROOT to a disposable absolute directory."
        case .invalidLargeTrackCount(let count):
            return "The large fixture track count must be between 1 and 50,000, not \(count)."
        case .artworkEncodingFailed:
            return "Could not encode deterministic fixture artwork."
        case .manifestMissing(let path):
            return "The fixture manifest is missing at \(path)."
        case .verificationFailed(let expected, let actual):
            return "Fixture verification failed: expected \(expected), found \(actual)."
        }
    }
}

/// Builds disposable, deterministic libraries for black-box usability tests.
/// All destructive work is confined to a validated `SONGBIRD_UI_TEST_ROOT`.
@MainActor
public struct SongbirdUsabilityFixtureSeeder {
    public nonisolated static let manifestFilename = "fixture-manifest.json"
    public nonisolated static let defaultLargeTrackCount = 10_000
    public nonisolated static let generationSeed: UInt64 = 0x534F4E4742495244
    public nonisolated static let generatorRevision = "large-10000-v2"
    public nonisolated static let playbackFixtureDuration: TimeInterval = 30

    public let root: URL
    public let songbirdDirectory: URL
    public let storeURL: URL
    public let mediaDirectory: URL
    public let manifestURL: URL

    public init(root: URL) throws {
        let defaultDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let validatedRoot = try MediaLibraryStore.resolvedApplicationSupportDirectory(
            environment: [MediaLibraryStore.uiTestRootEnvironmentKey: root.path],
            defaultDirectory: defaultDirectory
        )
        self.root = validatedRoot
        songbirdDirectory = validatedRoot.appendingPathComponent("Songbird", isDirectory: true)
        storeURL = songbirdDirectory.appendingPathComponent("library.store")
        mediaDirectory = validatedRoot.appendingPathComponent("Media", isDirectory: true)
        manifestURL = validatedRoot.appendingPathComponent(Self.manifestFilename)
    }

    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        guard environment[MediaLibraryStore.uiTestRootEnvironmentKey] != nil else {
            throw SongbirdUsabilityFixtureError.missingRootEnvironment
        }
        let defaultDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let validatedRoot = try MediaLibraryStore.resolvedApplicationSupportDirectory(
            environment: environment,
            defaultDirectory: defaultDirectory
        )
        return try Self(root: validatedRoot)
    }

    @discardableResult
    public func seed(
        profile: SongbirdUsabilityFixtureProfile = .standard,
        largeTrackCount: Int = Self.defaultLargeTrackCount,
        fileManager: FileManager = .default
    ) throws -> SongbirdUsabilityFixtureManifest {
        if profile == .large, !(1...50_000).contains(largeTrackCount) {
            throw SongbirdUsabilityFixtureError.invalidLargeTrackCount(largeTrackCount)
        }

        try prepareDirectories(fileManager: fileManager)
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let seeded: SeededModels
        switch profile {
        case .empty:
            seeded = SeededModels(albums: [], tracks: [], trackModels: [])
        case .standard:
            seeded = try seedStandardLibrary(in: context, fileManager: fileManager)
        case .health:
            seeded = try seedHealthLibrary(in: context, fileManager: fileManager)
        case .large:
            seeded = try seedLargeLibrary(
                trackCount: largeTrackCount,
                in: context,
                fileManager: fileManager
            )
        }

        try DefaultSmartPlaylists.ensureInstalled(in: context)
        try context.save()
        let playlists = try context.fetch(FetchDescriptor<Playlist>())
            .sorted { lhs, rhs in
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map {
                SongbirdUsabilityFixtureManifest.PlaylistEntry(
                    id: $0.id,
                    name: $0.name,
                    isSmart: $0.smartPlaylist,
                    systemKey: $0.systemKey,
                    trackIDs: $0.tracks.map(\.id)
                )
            }
        let manifest = SongbirdUsabilityFixtureManifest(
            schemaVersion: 2,
            generationSeed: Self.generationSeed,
            generatorRevision: Self.generatorRevision,
            profile: profile,
            storePath: storeURL.path,
            mediaDirectory: mediaDirectory.path,
            albums: seeded.albums,
            tracks: seeded.tracks,
            playlists: playlists,
            folders: profile == .standard ? try folderEntries(fileManager: fileManager) : [],
            playlistCount: playlists.count
        )
        try writeManifest(manifest)
        return manifest
    }

    public func verify() throws -> SongbirdUsabilityFixtureManifest {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw SongbirdUsabilityFixtureError.manifestMissing(manifestURL.path)
        }
        let manifest = try JSONDecoder().decode(
            SongbirdUsabilityFixtureManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let context = ModelContext(try makeContainer())
        let actualTracks = try context.fetchCount(FetchDescriptor<Track>())
        let actualAlbums = try context.fetchCount(FetchDescriptor<Album>())
        let actualPlaylists = try context.fetchCount(FetchDescriptor<Playlist>())

        guard actualTracks == manifest.trackCount else {
            throw SongbirdUsabilityFixtureError.verificationFailed(
                expected: "\(manifest.trackCount) tracks",
                actual: "\(actualTracks) tracks"
            )
        }
        guard actualAlbums == manifest.albumCount else {
            throw SongbirdUsabilityFixtureError.verificationFailed(
                expected: "\(manifest.albumCount) albums",
                actual: "\(actualAlbums) albums"
            )
        }
        guard actualPlaylists == manifest.playlistCount else {
            throw SongbirdUsabilityFixtureError.verificationFailed(
                expected: "\(manifest.playlistCount) playlists",
                actual: "\(actualPlaylists) playlists"
            )
        }
        return manifest
    }

    public func configureApplicationDefaults(
        bundleIdentifier: String,
        manifest: SongbirdUsabilityFixtureManifest
    ) throws {
        guard bundleIdentifier.isEmpty == false,
              let defaults = UserDefaults(suiteName: bundleIdentifier) else {
            throw SongbirdUsabilityFixtureError.verificationFailed(
                expected: "a writable disposable defaults domain",
                actual: bundleIdentifier
            )
        }
        let configurations = manifest.folders
            .filter(\.configured)
            .map { LibraryFolderConfiguration(path: $0.path, mode: $0.intendedMode) }
        LibraryFolderConfigurationStore.save(configurations, defaults: defaults)
        defaults.set(true, forKey: ImportSetupView.completedKey)
        defaults.synchronize()
    }

    public func stateReport(
        bundleIdentifier: String,
        fileManager: FileManager = .default
    ) throws -> SongbirdUsabilityStateReport {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw SongbirdUsabilityFixtureError.manifestMissing(manifestURL.path)
        }
        let manifest = try JSONDecoder().decode(
            SongbirdUsabilityFixtureManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let context = ModelContext(try makeContainer())
        let favorites = Set(try context.fetch(FetchDescriptor<TrackFavorite>()).map(\.trackID))
        let tracks = try context.fetch(FetchDescriptor<Track>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                SongbirdUsabilityStateReport.TrackState(
                    id: $0.id,
                    title: $0.title,
                    artist: $0.artist,
                    album: $0.album,
                    genre: $0.genre,
                    comments: $0.comment,
                    rating: $0.rating,
                    isFavorite: favorites.contains($0.id),
                    path: $0.path,
                    fileExists: fileManager.fileExists(atPath: $0.path)
                )
            }
        let defaults = UserDefaults(suiteName: bundleIdentifier)
        let storedOrder = defaults?.data(forKey: "songbird.playlist.trackOrder.v1")
            .flatMap { try? JSONDecoder().decode([String: [UUID]].self, from: $0) } ?? [:]
        let playlists = try context.fetch(FetchDescriptor<Playlist>())
            .sorted { lhs, rhs in
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map { playlist in
                let membership = playlist.tracks.map(\.id)
                let members = Set(membership)
                var seen = Set<UUID>()
                let ordered = (storedOrder[playlist.id.uuidString] ?? [])
                    .filter { members.contains($0) && seen.insert($0).inserted }
                    + membership.filter { seen.insert($0).inserted }
                return SongbirdUsabilityStateReport.PlaylistState(
                    id: playlist.id,
                    name: playlist.name,
                    isSmart: playlist.smartPlaylist,
                    systemKey: playlist.systemKey,
                    orderedTrackIDs: ordered
                )
            }
        let folders = defaults?.data(forKey: LibraryFolderConfigurationStore.configurationsKey)
            .flatMap {
                try? JSONDecoder().decode([LibraryFolderConfiguration].self, from: $0)
            } ?? []
        let media = manifest.folders.flatMap(\.mediaFiles).map { entry in
            let exists = fileManager.fileExists(atPath: entry.path)
            let digest: String?
            if exists, let data = try? Data(contentsOf: URL(fileURLWithPath: entry.path)) {
                digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            } else {
                digest = nil
            }
            return SongbirdUsabilityStateReport.MediaState(
                path: entry.path,
                fileExists: exists,
                sha256: digest
            )
        }
        return SongbirdUsabilityStateReport(
            fixture: manifest.profile,
            tracks: tracks,
            playlists: playlists,
            folders: folders,
            media: media
        )
    }

    private func prepareDirectories(fileManager: FileManager) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: songbirdDirectory, withIntermediateDirectories: true)
        MediaLibraryStore.removeStore(at: storeURL, fileManager: fileManager)
        if fileManager.fileExists(atPath: mediaDirectory.path) {
            try fileManager.removeItem(at: mediaDirectory)
        }
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }
        try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let selectionRoot = root.appendingPathComponent("FolderSelections", isDirectory: true)
        if fileManager.fileExists(atPath: selectionRoot.path) {
            try fileManager.removeItem(at: selectionRoot)
        }
        let folderFiles = [
            ("AddAndScan", "add-and-scan.wav", 1),
            ("WithoutScanning", "without-scanning.wav", 2),
            ("InitialImport", "initial-import.wav", 3),
            ("ConfiguredWatching", "watching-root.wav", 4),
            ("ConfiguredManual", "manual-root.wav", 5),
        ]
        for (name, filename, seed) in folderFiles {
            let directory = selectionRoot.appendingPathComponent(name, isDirectory: true)
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try Self.folderWAVData(seed: seed).write(
                to: directory.appendingPathComponent(filename),
                options: .atomic
            )
        }
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: SongbirdMigrationPlan.self,
            configurations: configuration
        )
    }

    private func writeManifest(_ manifest: SongbirdUsabilityFixtureManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }
}

private extension SongbirdUsabilityFixtureSeeder {
    struct SeededModels {
        let albums: [SongbirdUsabilityFixtureManifest.AlbumEntry]
        let tracks: [SongbirdUsabilityFixtureManifest.TrackEntry]
        let trackModels: [Track]
    }

    struct AlbumSpec {
        let idIndex: Int
        let key: String
        let title: String
        let artist: String
        let year: Int
        let artworkSeed: Int?
        let isFavorite: Bool
    }

    struct TrackSpec {
        let idIndex: Int
        let albumKey: String
        let title: String
        let artist: String
        let albumArtist: String
        let genre: String
        let duration: TimeInterval
        let playCount: Int
        let isFavorite: Bool
        let fileExists: Bool
        var relativePath: String? = nil
    }

    func folderEntries(
        fileManager: FileManager
    ) throws -> [SongbirdUsabilityFixtureManifest.FolderEntry] {
        let selectionRoot = root.appendingPathComponent("FolderSelections", isDirectory: true)
        let specifications: [(String, String, LibraryFolderMode, Bool)] = [
            ("addAndScan", "AddAndScan", .watching, false),
            ("addWithoutScanning", "WithoutScanning", .watching, false),
            ("initialImport", "InitialImport", .watching, false),
            ("configuredWatching", "ConfiguredWatching", .watching, true),
            ("configuredManual", "ConfiguredManual", .manualScanOnly, true),
            ("configuredUnavailable", "ConfiguredUnavailable", .watching, true),
        ]
        return try specifications.map { purpose, directoryName, mode, configured in
            let directory = selectionRoot
                .appendingPathComponent(directoryName, isDirectory: true)
                .standardizedFileURL
            let available = fileManager.fileExists(atPath: directory.path)
            let mediaFiles: [SongbirdUsabilityFixtureManifest.MediaFileEntry]
            if available {
                mediaFiles = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { url in
                    let digest = SHA256.hash(data: try Data(contentsOf: url))
                    return .init(
                        path: url.path,
                        sha256: digest.map { String(format: "%02x", $0) }.joined()
                    )
                }
            } else {
                mediaFiles = []
            }
            return .init(
                purpose: purpose,
                path: directory.path,
                intendedMode: mode,
                configured: configured,
                available: available,
                mediaFiles: mediaFiles
            )
        }
    }

    func seedStandardLibrary(
        in context: ModelContext,
        fileManager: FileManager
    ) throws -> SeededModels {
        let albumSpecs = [
            AlbumSpec(
                idIndex: 201,
                key: "northern-lights",
                title: "Northern Lights",
                artist: "The Skylarks",
                year: 2024,
                artworkSeed: 1,
                isFavorite: true
            ),
            AlbumSpec(
                idIndex: 202,
                key: "quiet-rooms",
                title: "Quiet Rooms",
                artist: "Dana Okafor",
                year: 2022,
                artworkSeed: nil,
                isFavorite: false
            ),
            AlbumSpec(
                idIndex: 203,
                key: "signals",
                title: "Signals: A Compilation",
                artist: "Various Artists",
                year: 2025,
                artworkSeed: nil,
                isFavorite: false
            ),
            AlbumSpec(
                idIndex: 204,
                key: "distant-sea",
                title: "交響曲『遥かな海』— 2025 Remastered Deluxe Edition With An Intentionally Long Name",
                artist: "東京アンサンブル",
                year: 2025,
                artworkSeed: 2,
                isFavorite: false
            ),
            AlbumSpec(
                idIndex: 205,
                key: "missing-files",
                title: "The Missing File",
                artist: "Test Conditions",
                year: 2020,
                artworkSeed: nil,
                isFavorite: false
            ),
        ]
        let trackSpecs = [
            TrackSpec(idIndex: 1001, albumKey: "northern-lights", title: "First Light", artist: "The Skylarks", albumArtist: "The Skylarks", genre: "Alternative", duration: 214, playCount: 12, isFavorite: true, fileExists: true),
            TrackSpec(idIndex: 1002, albumKey: "northern-lights", title: "Over the Ridge", artist: "The Skylarks", albumArtist: "The Skylarks", genre: "Alternative", duration: 187, playCount: 4, isFavorite: false, fileExists: true),
            TrackSpec(idIndex: 1003, albumKey: "northern-lights", title: "Aurora Return", artist: "The Skylarks", albumArtist: "The Skylarks", genre: "Alternative", duration: 246, playCount: 0, isFavorite: false, fileExists: true),
            TrackSpec(idIndex: 1004, albumKey: "quiet-rooms", title: "A Room With No Clocks", artist: "Dana Okafor", albumArtist: "Dana Okafor", genre: "Jazz", duration: 302, playCount: 8, isFavorite: false, fileExists: true),
            TrackSpec(idIndex: 1005, albumKey: "quiet-rooms", title: "Dust in the Hall", artist: "Dana Okafor", albumArtist: "Dana Okafor", genre: "Jazz", duration: 271, playCount: 1, isFavorite: false, fileExists: true),
            TrackSpec(idIndex: 1006, albumKey: "quiet-rooms", title: "Before the Door Closes", artist: "Dana Okafor", albumArtist: "Dana Okafor", genre: "Jazz", duration: 199, playCount: 0, isFavorite: false, fileExists: true),
            TrackSpec(idIndex: 1007, albumKey: "signals", title: "Glass Circuit", artist: "Iris Vale", albumArtist: "Various Artists", genre: "Electronic", duration: 223, playCount: 21, isFavorite: true, fileExists: true),
            TrackSpec(idIndex: 1008, albumKey: "signals", title: "Paper Satellites", artist: "The Skylarks", albumArtist: "Various Artists", genre: "Electronic", duration: 205, playCount: 3, isFavorite: false, fileExists: true),
            TrackSpec(idIndex: 1009, albumKey: "signals", title: "밤의 신호", artist: "윤서", albumArtist: "Various Artists", genre: "K-Pop", duration: 194, playCount: 6, isFavorite: false, fileExists: true),
            TrackSpec(idIndex: 1010, albumKey: "signals", title: "São Paulo, 4 A.M.", artist: "Marina Luz", albumArtist: "Various Artists", genre: "Electronic", duration: 258, playCount: 2, isFavorite: false, fileExists: true),
            TrackSpec(idIndex: 1011, albumKey: "distant-sea", title: "第一楽章：潮流", artist: "東京アンサンブル", albumArtist: "東京アンサンブル", genre: "Classical", duration: 604, playCount: 2, isFavorite: false, fileExists: true),
            TrackSpec(idIndex: 1012, albumKey: "distant-sea", title: "第二楽章：水平線", artist: "東京アンサンブル", albumArtist: "東京アンサンブル", genre: "Classical", duration: 718, playCount: 0, isFavorite: false, fileExists: true),
            TrackSpec(idIndex: 1013, albumKey: "distant-sea", title: "Finale — 帰港", artist: "東京アンサンブル", albumArtist: "東京アンサンブル", genre: "Classical", duration: 551, playCount: 1, isFavorite: false, fileExists: true),
            TrackSpec(idIndex: 1014, albumKey: "missing-files", title: "Unavailable Recording", artist: "Test Conditions", albumArtist: "Test Conditions", genre: "Test", duration: 120, playCount: 0, isFavorite: false, fileExists: false),
        ]
        let seeded = try seed(
            albumSpecs: albumSpecs,
            trackSpecs: trackSpecs,
            in: context,
            fileManager: fileManager
        )

        let availableTracks = seeded.trackModels.filter {
            fileManager.fileExists(atPath: $0.path)
        }
        let morningMix = Playlist(name: "Morning Mix")
        morningMix.id = Self.fixtureUUID(2_001)
        morningMix.dateCreated = Self.baseDate.addingTimeInterval(-10 * 86_400)
        morningMix.dateModified = Self.baseDate
        morningMix.tracks = Array(availableTracks.prefix(5))
        context.insert(morningMix)

        let electronicFavorites = Playlist(name: "Top-Rated Electronic", smart: true)
        electronicFavorites.id = Self.fixtureUUID(2_002)
        electronicFavorites.smartPlaylistRules = try SmartPlaylistRuleSet(
            matchMode: .all,
            conditions: [
                SmartCondition(field: .genre, op: .contains, value: "Electronic"),
                SmartCondition(field: .rating, op: .greaterThan, value: "0"),
            ]
        ).encode()
        context.insert(electronicFavorites)
        return seeded
    }

    func seedLargeLibrary(
        trackCount: Int,
        in context: ModelContext,
        fileManager: FileManager
    ) throws -> SeededModels {
        let albumCount = min(1_000, max(1, (trackCount + 9) / 10))
        let albumSpecs = (0..<albumCount).map { index in
            AlbumSpec(
                idIndex: 10_000 + index,
                key: "large-album-\(index)",
                title: "Fixture Album \(String(format: "%03d", index + 1))",
                artist: "Fixture Artist \(String(format: "%02d", index % 24 + 1))",
                year: 1980 + index % 46,
                artworkSeed: index.isMultiple(of: 4) ? index + 10 : nil,
                isFavorite: index.isMultiple(of: 13)
            )
        }
        let genres = ["Alternative", "Classical", "Electronic", "Jazz", "Pop", "World"]
        let trackSpecs = (0..<trackCount).map { index in
            let albumIndex = index % albumCount
            let album = albumSpecs[albumIndex]
            return TrackSpec(
                idIndex: 20_000 + index,
                albumKey: album.key,
                title: "Fixture Track \(String(format: "%05d", index + 1))",
                artist: index.isMultiple(of: 9)
                    ? "Guest Performer \(index % 11 + 1)"
                    : album.artist,
                albumArtist: album.artist,
                genre: genres[index % genres.count],
                duration: TimeInterval(90 + index % 480),
                playCount: index % 37,
                isFavorite: index.isMultiple(of: 97),
                fileExists: index.isMultiple(of: 503) == false
            )
        }
        let seeded = try seed(
            albumSpecs: albumSpecs,
            trackSpecs: trackSpecs,
            in: context,
            fileManager: fileManager
        )
        let sampler = Playlist(name: "Large Library Sampler")
        sampler.id = Self.fixtureUUID(40_001)
        sampler.tracks = stride(
            from: 0,
            to: seeded.trackModels.count,
            by: max(1, seeded.trackModels.count / 20)
        )
            .prefix(20)
            .map { seeded.trackModels[$0] }
        context.insert(sampler)
        return seeded
    }

    func seedHealthLibrary(
        in context: ModelContext,
        fileManager: FileManager
    ) throws -> SeededModels {
        let albumSpecs = [
            AlbumSpec(idIndex: 301, key: "unknown", title: "Unknown Album", artist: "Fixture Artist", year: 0, artworkSeed: nil, isFavorite: false),
            AlbumSpec(idIndex: 302, key: "safe-sibling", title: "Safe Sibling", artist: "Fixture Artist", year: 2024, artworkSeed: nil, isFavorite: false),
            AlbumSpec(idIndex: 303, key: "first", title: "First", artist: "Fixture Artist", year: 2024, artworkSeed: nil, isFavorite: false),
            AlbumSpec(idIndex: 304, key: "second", title: "Second", artist: "Fixture Artist", year: 2024, artworkSeed: nil, isFavorite: false),
            AlbumSpec(idIndex: 305, key: "file-health", title: "File Health", artist: "Fixture Artist", year: 2024, artworkSeed: nil, isFavorite: false),
        ]
        let trackSpecs = [
            TrackSpec(idIndex: 3001, albumKey: "unknown", title: "Needs Sibling Evidence", artist: "Fixture Artist", albumArtist: "Fixture Artist", genre: "", duration: 120, playCount: 0, isFavorite: false, fileExists: true, relativePath: "Safe Sibling/01.wav"),
            TrackSpec(idIndex: 3002, albumKey: "safe-sibling", title: "Tagged Sibling", artist: "Fixture Artist", albumArtist: "Fixture Artist", genre: "Rock", duration: 121, playCount: 0, isFavorite: false, fileExists: true, relativePath: "Safe Sibling/02.wav"),
            TrackSpec(idIndex: 3003, albumKey: "unknown", title: "Review This Folder", artist: "Fixture Artist", albumArtist: "Fixture Artist", genre: "", duration: 122, playCount: 0, isFavorite: false, fileExists: true, relativePath: "Possible Album/01.wav"),
            TrackSpec(idIndex: 3004, albumKey: "unknown", title: "Disc One", artist: "Fixture Artist", albumArtist: "Fixture Artist", genre: "", duration: 123, playCount: 0, isFavorite: false, fileExists: true, relativePath: "Box Set/CD 1/01.wav"),
            TrackSpec(idIndex: 3005, albumKey: "unknown", title: "Disc Two", artist: "Fixture Artist", albumArtist: "Fixture Artist", genre: "", duration: 124, playCount: 0, isFavorite: false, fileExists: true, relativePath: "Box Set/CD 2/01.wav"),
            TrackSpec(idIndex: 3006, albumKey: "unknown", title: "Conflicting Evidence", artist: "Fixture Artist", albumArtist: "Fixture Artist", genre: "", duration: 125, playCount: 0, isFavorite: false, fileExists: true, relativePath: "Conflict/01.wav"),
            TrackSpec(idIndex: 3007, albumKey: "first", title: "First Opinion", artist: "Fixture Artist", albumArtist: "Fixture Artist", genre: "", duration: 126, playCount: 0, isFavorite: false, fileExists: true, relativePath: "Conflict/02.wav"),
            TrackSpec(idIndex: 3008, albumKey: "second", title: "Second Opinion", artist: "Fixture Artist", albumArtist: "Fixture Artist", genre: "", duration: 127, playCount: 0, isFavorite: false, fileExists: true, relativePath: "Conflict/03.wav"),
            TrackSpec(idIndex: 3009, albumKey: "unknown", title: "No Local Evidence", artist: "Fixture Artist", albumArtist: "Fixture Artist", genre: "", duration: 128, playCount: 0, isFavorite: false, fileExists: true, relativePath: "Music/01.wav"),
            TrackSpec(idIndex: 3010, albumKey: "file-health", title: "Relocatable Recording", artist: "Fixture Artist", albumArtist: "Fixture Artist", genre: "Test", duration: 129, playCount: 0, isFavorite: false, fileExists: false, relativePath: "Missing/relocatable.wav"),
            TrackSpec(idIndex: 3011, albumKey: "file-health", title: "Ambiguous Recording", artist: "Fixture Artist", albumArtist: "Fixture Artist", genre: "Test", duration: 130, playCount: 0, isFavorite: false, fileExists: false, relativePath: "Missing/ambiguous.wav"),
            TrackSpec(idIndex: 3012, albumKey: "file-health", title: "Unavailable Recording", artist: "Fixture Artist", albumArtist: "Fixture Artist", genre: "Test", duration: 131, playCount: 0, isFavorite: false, fileExists: false, relativePath: "Missing/unavailable.wav"),
        ]
        let seeded = try seed(
            albumSpecs: albumSpecs,
            trackSpecs: trackSpecs,
            in: context,
            fileManager: fileManager
        )
        let localArtwork = mediaDirectory
            .appendingPathComponent("Safe Sibling", isDirectory: true)
            .appendingPathComponent("cover.png")
        try Self.artworkData(seed: 31).write(to: localArtwork, options: .atomic)
        let relocationRoot = root.appendingPathComponent("HealthRelocationRoot", isDirectory: true)
        let uniqueCandidate = relocationRoot
            .appendingPathComponent("Unique", isDirectory: true)
            .appendingPathComponent("relocatable.wav")
        let ambiguousCandidates = ["A", "B"].map {
            relocationRoot.appendingPathComponent($0, isDirectory: true)
                .appendingPathComponent("ambiguous.wav")
        }
        for url in [uniqueCandidate] + ambiguousCandidates {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.silentWAVData().write(to: url, options: .atomic)
        }
        if let relocatable = seeded.trackModels.first(where: { $0.id == Self.fixtureUUID(3010) }) {
            relocatable.checksum = Track.contentChecksum(at: uniqueCandidate.path)
        }
        if let unavailable = seeded.trackModels.first(where: { $0.id == Self.fixtureUUID(3012) }) {
            unavailable.path = "/Volumes/Songbird Fixture Offline/unavailable.wav"
        }
        for duplicateID in [Self.fixtureUUID(3007), Self.fixtureUUID(3008)] {
            seeded.trackModels.first(where: { $0.id == duplicateID })?.checksum =
                "songbird-health-exact-duplicate"
        }
        let entriesByID = Dictionary(uniqueKeysWithValues: seeded.tracks.map { ($0.id, $0) })
        let updatedEntries = seeded.trackModels.compactMap { track -> SongbirdUsabilityFixtureManifest.TrackEntry? in
            guard let original = entriesByID[track.id] else { return nil }
            return .init(
                id: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                path: track.path,
                fileExists: fileManager.fileExists(atPath: track.path),
                isFavorite: original.isFavorite
            )
        }
        return SeededModels(
            albums: seeded.albums,
            tracks: updatedEntries,
            trackModels: seeded.trackModels
        )
    }

    func seed(
        albumSpecs: [AlbumSpec],
        trackSpecs: [TrackSpec],
        in context: ModelContext,
        fileManager: FileManager
    ) throws -> SeededModels {
        let audioTemplate = mediaDirectory.appendingPathComponent("fixture-audio-template")
        if trackSpecs.contains(where: \.fileExists) {
            try Self.silentWAVData().write(to: audioTemplate, options: .atomic)
        }

        var albumModels: [String: Album] = [:]
        var albumEntries: [SongbirdUsabilityFixtureManifest.AlbumEntry] = []
        for (offset, spec) in albumSpecs.enumerated() {
            let album = Album(title: spec.title, artist: spec.artist, year: spec.year)
            album.id = Self.fixtureUUID(spec.idIndex)
            album.dateAdded = Self.baseDate.addingTimeInterval(-Double(offset) * 86_400)
            if let seed = spec.artworkSeed {
                album.artworkData = try Self.artworkData(seed: seed)
            }
            context.insert(album)
            albumModels[spec.key] = album
            if spec.isFavorite {
                context.insert(AlbumFavorite(albumID: album.id, dateAdded: Self.baseDate))
            }
            albumEntries.append(.init(
                id: album.id,
                title: album.title,
                artist: album.artist,
                hasArtwork: album.artworkData?.isEmpty == false,
                isFavorite: spec.isFavorite
            ))
        }

        var artistModels: [String: Artist] = [:]
        var trackEntries: [SongbirdUsabilityFixtureManifest.TrackEntry] = []
        var trackModels: [Track] = []
        for (offset, spec) in trackSpecs.enumerated() {
            guard let album = albumModels[spec.albumKey] else { continue }
            let trackURL = mediaDirectory.appendingPathComponent(
                spec.relativePath ?? String(format: "%05d-fixture.wav", offset + 1)
            )
            if spec.fileExists {
                try fileManager.createDirectory(
                    at: trackURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                do {
                    try fileManager.linkItem(at: audioTemplate, to: trackURL)
                } catch {
                    try fileManager.copyItem(at: audioTemplate, to: trackURL)
                }
            }
            let track = Track(
                path: trackURL.path,
                title: spec.title,
                artist: spec.artist,
                album: album.title
            )
            track.id = Self.fixtureUUID(spec.idIndex)
            track.albumArtist = spec.albumArtist
            track.genre = spec.genre
            track.year = album.year
            track.trackNumber = album.tracks.count + 1
            track.duration = spec.duration
            track.dateAdded = Self.baseDate.addingTimeInterval(-Double(offset % 120) * 86_400)
            track.dateModified = Self.baseDate
            track.playCount = spec.playCount
            track.lastPlayed = spec.playCount > 0
                ? Self.baseDate.addingTimeInterval(-Double(offset % 30) * 86_400)
                : nil
            track.rating = offset % 6
            track.bitrate = 705
            track.sampleRate = 44_100
            track.fileSize = spec.fileExists
                ? Int64((try? fileManager.attributesOfItem(atPath: trackURL.path)[.size] as? Int) ?? 0)
                : 0
            track.checksum = "songbird-usability-fixture-\(spec.idIndex)"
            context.insert(track)
            if spec.isFavorite {
                context.insert(TrackFavorite(trackID: track.id, dateAdded: Self.baseDate))
            }
            album.tracks.append(track)

            let artist: Artist
            if let existing = artistModels[spec.artist] {
                artist = existing
            } else {
                artist = Artist(name: spec.artist)
                artist.id = Self.fixtureUUID(50_000 + artistModels.count)
                artist.dateAdded = track.dateAdded
                context.insert(artist)
                artistModels[spec.artist] = artist
            }
            artist.tracks.append(track)
            trackEntries.append(.init(
                id: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                path: track.path,
                fileExists: spec.fileExists,
                isFavorite: spec.isFavorite
            ))
            trackModels.append(track)
        }
        return SeededModels(
            albums: albumEntries,
            tracks: trackEntries,
            trackModels: trackModels
        )
    }

    static let baseDate = Date(timeIntervalSince1970: 1_735_689_600)

    static func fixtureUUID(_ value: Int) -> UUID {
        let suffix = String(format: "%012d", value)
        return UUID(uuidString: "00000000-0000-4000-8000-\(suffix)")!
    }

    static func silentWAVData(
        frameCount: Int = Int(playbackFixtureDuration * 44_100)
    ) -> Data {
        let channelCount: UInt16 = 1
        let sampleRate: UInt32 = 44_100
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = UInt16(bitsPerSample / 8)
        let blockAlign = channelCount * bytesPerSample
        let byteRate = sampleRate * UInt32(blockAlign)
        let audioByteCount = UInt32(frameCount) * UInt32(blockAlign)

        var data = Data("RIFF".utf8)
        data.appendLittleEndian(UInt32(36) + audioByteCount)
        data.append(Data("WAVEfmt ".utf8))
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(channelCount)
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.append(Data("data".utf8))
        data.appendLittleEndian(audioByteCount)
        data.append(Data(repeating: 0, count: Int(audioByteCount)))
        return data
    }

    static func folderWAVData(seed: Int) -> Data {
        var data = silentWAVData(frameCount: 44_100)
        if data.count >= 46 {
            data[44] = UInt8(truncatingIfNeeded: seed * 31)
            data[45] = UInt8(truncatingIfNeeded: seed * 17)
        }
        return data
    }

    static func artworkData(seed: Int) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 64,
            pixelsHigh: 64,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw SongbirdUsabilityFixtureError.artworkEncodingFailed
        }
        let hue = CGFloat(seed % 17) / 17
        let primary = NSColor(calibratedHue: hue, saturation: 0.72, brightness: 0.85, alpha: 1)
        let secondary = NSColor(
            calibratedHue: (hue + 0.18).truncatingRemainder(dividingBy: 1),
            saturation: 0.62,
            brightness: 0.45,
            alpha: 1
        )
        for y in 0..<64 {
            for x in 0..<64 {
                bitmap.setColor((x + y + seed).isMultiple(of: 18) ? secondary : primary, atX: x, y: y)
            }
        }
        guard let encoded = bitmap.representation(using: .png, properties: [:]) else {
            throw SongbirdUsabilityFixtureError.artworkEncodingFailed
        }
        return encoded
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
