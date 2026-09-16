import Foundation
import SwiftData

/// A stable handle to artwork that does not load or move image bytes through UI code.
public enum ArtworkReference: Hashable, Sendable {
    case album(id: UUID, persistentIdentifier: PersistentIdentifier)
    case remote(URL)
    case discogsRemote(URL, evidence: DiscogsContentEvidence)
    case embedded(id: UUID, data: Data)
    case songbirdLogo
    case missingAlbumArtwork
}

public extension ArtworkReference {
    @MainActor
    static func resolved(for track: Track) -> ArtworkReference? {
        if let remoteURL = track.audioCDArtworkURL {
            if let evidence = track.audioCDDiscogsEvidence {
                return .discogsRemote(remoteURL, evidence: evidence)
            }
            return .remote(remoteURL)
        }
        if let snapshot = LibrarySnapshotStore.active?.trackSnapshot(id: track.id) {
            return snapshot.artworkReference ?? .missingAlbumArtwork
        }
        guard let album = track.albumRelation,
              let artworkData = album.artworkData,
              artworkData.isEmpty == false else { return .missingAlbumArtwork }
        return .album(id: album.id, persistentIdentifier: album.persistentModelID)
    }
}

/// Immutable metadata used by library lists, filters, smart playlists, and artwork views.
public struct LibraryTrackSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let persistentIdentifier: PersistentIdentifier
    public let title: String
    public let artist: String
    public let album: String
    public let albumArtist: String
    public let genre: String
    public let composer: String
    public let comment: String
    public let year: Int
    public let trackNumber: Int
    public let discNumber: Int
    public let beatsPerMinute: Int
    public let duration: TimeInterval
    public let fileSize: Int64
    public let path: String
    public let dateAdded: Date
    public let dateModified: Date
    public let lastPlayed: Date?
    public let playCount: Int
    public let rating: Int
    public let isLoved: Bool
    public let albumRating: Int
    public let bitrate: Int
    public let sampleRate: Int
    public let checksum: String
    public let albumID: UUID?
    public let artworkReference: ArtworkReference?

    public var fileKind: String {
        (path as NSString).pathExtension.uppercased()
    }

    init(track: Track, albumRating: Int, albumsWithArtwork: Set<UUID>, lovedTrackIDs: Set<UUID> = []) {
        id = track.id
        persistentIdentifier = track.persistentModelID
        title = track.title
        artist = track.artist
        album = track.album
        albumArtist = track.albumArtist
        genre = track.genre
        composer = track.composer
        comment = track.comment
        year = track.year
        trackNumber = track.trackNumber
        discNumber = track.discNumber
        beatsPerMinute = track.beatsPerMinute
        duration = track.duration
        fileSize = track.fileSize
        path = track.path
        dateAdded = track.dateAdded
        dateModified = track.dateModified
        lastPlayed = track.lastPlayed
        playCount = track.playCount
        rating = track.rating
        isLoved = lovedTrackIDs.contains(track.id)
        self.albumRating = albumRating
        bitrate = track.bitrate
        sampleRate = track.sampleRate
        checksum = track.checksum
        albumID = track.albumRelation?.id
        if let album = track.albumRelation, albumsWithArtwork.contains(album.id) {
            artworkReference = .album(
                id: album.id,
                persistentIdentifier: album.persistentModelID
            )
        } else {
            artworkReference = nil
        }
    }

    /// Public initializer used by projection fixtures without constructing SwiftData models.
    public init(
        id: UUID = UUID(),
        persistentIdentifier: PersistentIdentifier,
        title: String,
        artist: String = "Unknown Artist",
        album: String = "Unknown Album",
        albumArtist: String? = nil,
        genre: String = "",
        composer: String = "",
        comment: String = "",
        year: Int = 0,
        trackNumber: Int = 0,
        discNumber: Int = 0,
        beatsPerMinute: Int = 0,
        duration: TimeInterval = 0,
        fileSize: Int64 = 0,
        path: String = "",
        dateAdded: Date = .distantPast,
        dateModified: Date = .distantPast,
        lastPlayed: Date? = nil,
        playCount: Int = 0,
        rating: Int = 0,
        isLoved: Bool = false,
        albumRating: Int = 0,
        bitrate: Int = 0,
        sampleRate: Int = 0,
        checksum: String = "",
        albumID: UUID? = nil,
        artworkReference: ArtworkReference? = nil
    ) {
        self.id = id
        self.persistentIdentifier = persistentIdentifier
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist ?? artist
        self.genre = genre
        self.composer = composer
        self.comment = comment
        self.year = year
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.beatsPerMinute = beatsPerMinute
        self.duration = duration
        self.fileSize = fileSize
        self.path = path
        self.dateAdded = dateAdded
        self.dateModified = dateModified
        self.lastPlayed = lastPlayed
        self.playCount = playCount
        self.rating = rating
        self.isLoved = isLoved
        self.albumRating = albumRating
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.checksum = checksum
        self.albumID = albumID
        self.artworkReference = artworkReference
    }

    /// Return a copy with an updated rating for optimistic snapshot updates.
    public func withRating(_ newRating: Int) -> LibraryTrackSnapshot {
        replacing(rating: newRating)
    }

    public func withLoved(_ newValue: Bool) -> LibraryTrackSnapshot {
        replacing(isLoved: newValue)
    }

    public func withAlbumRating(_ newValue: Int) -> LibraryTrackSnapshot {
        replacing(albumRating: newValue)
    }

    public func withArtworkReference(_ newValue: ArtworkReference?) -> LibraryTrackSnapshot {
        replacing(artworkReference: newValue)
    }

    private func replacing(
        rating: Int? = nil,
        isLoved: Bool? = nil,
        albumRating: Int? = nil,
        artworkReference: ArtworkReference?? = nil
    ) -> LibraryTrackSnapshot {
        LibraryTrackSnapshot(
            id: id,
            persistentIdentifier: persistentIdentifier,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            genre: genre,
            composer: composer,
            comment: comment,
            year: year,
            trackNumber: trackNumber,
            discNumber: discNumber,
            beatsPerMinute: beatsPerMinute,
            duration: duration,
            fileSize: fileSize,
            path: path,
            dateAdded: dateAdded,
            dateModified: dateModified,
            lastPlayed: lastPlayed,
            playCount: playCount,
            rating: rating ?? self.rating,
            isLoved: isLoved ?? self.isLoved,
            albumRating: albumRating ?? self.albumRating,
            bitrate: bitrate,
            sampleRate: sampleRate,
            checksum: checksum,
            albumID: albumID,
            artworkReference: artworkReference ?? self.artworkReference
        )
    }
}

public struct LibraryAlbumSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let persistentIdentifier: PersistentIdentifier
    public let title: String
    public let artist: String
    public let year: Int
    public let dateAdded: Date
    public let trackIDs: [UUID]
    public let artworkReference: ArtworkReference?
    public let isFavorite: Bool

    init(album: Album, favoriteAlbumIDs: Set<UUID>) {
        id = album.id
        persistentIdentifier = album.persistentModelID
        title = album.title
        artist = album.artist
        year = album.year
        dateAdded = album.dateAdded
        trackIDs = album.tracks.map(\.id)
        artworkReference = album.artworkData == nil ? nil : .album(
            id: album.id,
            persistentIdentifier: album.persistentModelID
        )
        isFavorite = favoriteAlbumIDs.contains(album.id)
    }

    public init(
        id: UUID = UUID(),
        persistentIdentifier: PersistentIdentifier,
        title: String,
        artist: String,
        year: Int = 0,
        dateAdded: Date = Date(),
        trackIDs: [UUID] = [],
        artworkReference: ArtworkReference? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.persistentIdentifier = persistentIdentifier
        self.title = title
        self.artist = artist
        self.year = year
        self.dateAdded = dateAdded
        self.trackIDs = trackIDs
        self.artworkReference = artworkReference
        self.isFavorite = isFavorite
    }

    public func withFavorite(_ newValue: Bool) -> LibraryAlbumSnapshot {
        LibraryAlbumSnapshot(
            id: id,
            persistentIdentifier: persistentIdentifier,
            title: title,
            artist: artist,
            year: year,
            dateAdded: dateAdded,
            trackIDs: trackIDs,
            artworkReference: artworkReference,
            isFavorite: newValue
        )
    }

    public func withTrackIDs(_ newValue: [UUID]) -> LibraryAlbumSnapshot {
        LibraryAlbumSnapshot(
            id: id,
            persistentIdentifier: persistentIdentifier,
            title: title,
            artist: artist,
            year: year,
            dateAdded: dateAdded,
            trackIDs: newValue,
            artworkReference: artworkReference,
            isFavorite: isFavorite
        )
    }
}

public struct LibraryPlaylistSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let persistentIdentifier: PersistentIdentifier
    public let name: String
    public let dateCreated: Date
    public let dateModified: Date
    public let isSmart: Bool
    public let rules: SmartPlaylistRuleSet?
    public let systemKey: String?
    public let trackIDs: [UUID]

    init(playlist: Playlist) {
        id = playlist.id
        persistentIdentifier = playlist.persistentModelID
        name = playlist.name
        dateCreated = playlist.dateCreated
        dateModified = playlist.dateModified
        isSmart = playlist.smartPlaylist
        rules = SmartPlaylistRuleSet.decode(from: playlist.smartPlaylistRules)
        systemKey = playlist.systemKey
        trackIDs = playlist.smartPlaylist
            ? playlist.tracks.map(\.id)
            : PlaylistOrderStore.order(playlistID: playlist.id, membership: playlist.tracks.map(\.id))
    }

    public init(
        id: UUID = UUID(),
        persistentIdentifier: PersistentIdentifier,
        name: String,
        dateCreated: Date = Date(),
        dateModified: Date = Date(),
        isSmart: Bool = false,
        rules: SmartPlaylistRuleSet? = nil,
        systemKey: String? = nil,
        trackIDs: [UUID] = []
    ) {
        self.id = id
        self.persistentIdentifier = persistentIdentifier
        self.name = name
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.isSmart = isSmart
        self.rules = rules
        self.systemKey = systemKey
        self.trackIDs = trackIDs
    }
}

public struct LibrarySnapshot: Equatable, Sendable {
    public let revision: Int
    public let trackRevision: Int
    public let albumStructureRevision: Int
    public let albumPresentationRevision: Int
    public let playlistRevision: Int
    public let generatedAt: Date
    public let tracks: [LibraryTrackSnapshot]
    public let tracksByID: [UUID: LibraryTrackSnapshot]
    public let trackIDByPersistentIdentifier: [PersistentIdentifier: UUID]
    public let albums: [LibraryAlbumSnapshot]
    public let albumsByID: [UUID: LibraryAlbumSnapshot]
    public let albumIDByPersistentIdentifier: [PersistentIdentifier: UUID]
    public let playlists: [LibraryPlaylistSnapshot]
    public let playlistsByID: [UUID: LibraryPlaylistSnapshot]
    public let playlistIDByPersistentIdentifier: [PersistentIdentifier: UUID]
    public let artistNames: [String]
    public let genreNames: [String]

    public init(
        revision: Int,
        trackRevision: Int? = nil,
        albumStructureRevision: Int? = nil,
        albumPresentationRevision: Int? = nil,
        playlistRevision: Int? = nil,
        generatedAt: Date = Date(),
        tracks: [LibraryTrackSnapshot],
        albums: [LibraryAlbumSnapshot],
        playlists: [LibraryPlaylistSnapshot],
        artistNames: [String]? = nil,
        genreNames: [String]? = nil
    ) {
        self.revision = revision
        self.trackRevision = trackRevision ?? revision
        self.albumStructureRevision = albumStructureRevision ?? revision
        self.albumPresentationRevision = albumPresentationRevision ?? revision
        self.playlistRevision = playlistRevision ?? revision
        self.generatedAt = generatedAt
        self.tracks = tracks
        self.tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        self.trackIDByPersistentIdentifier = Dictionary(
            tracks.map { ($0.persistentIdentifier, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        self.albums = albums
        self.albumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
        self.albumIDByPersistentIdentifier = Dictionary(
            albums.map { ($0.persistentIdentifier, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        self.playlists = playlists
        self.playlistsByID = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0) })
        self.playlistIDByPersistentIdentifier = Dictionary(
            playlists.map { ($0.persistentIdentifier, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        self.artistNames = artistNames ?? Self.uniqueSorted(tracks.map(\.artist))
        self.genreNames = genreNames ?? Self.uniqueSorted(tracks.map(\.genre))
    }

    public static let empty = LibrarySnapshot(
        revision: 0,
        tracks: [],
        albums: [],
        playlists: []
    )

    private static func uniqueSorted(_ values: [String]) -> [String] {
        normalizedGenreList(values.filter { $0.isEmpty == false })
    }

    /// Deduplicates strings case-insensitively, keeping the most frequent
    /// variant (or the best-cased one on ties). Returns a sorted list.
    public static func normalizedGenreList(_ values: [String]) -> [String] {
        var counts: [String: [String]] = [:]
        for value in values {
            let key = value.lowercased()
            counts[key, default: []].append(value)
        }
        return counts.values.compactMap { variants in
            bestGenreVariant(variants)
        }.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    /// Picks the best representative from a set of case variants.
    /// Prefers the most common, then title-cased, then the original order.
    public static func bestGenreVariant(_ variants: [String]) -> String? {
        guard let first = variants.first else { return nil }
        var frequency: [String: Int] = [:]
        for v in variants { frequency[v, default: 0] += 1 }
        let maxCount = frequency.values.max() ?? 1
        let mostCommon = frequency.filter { $0.value == maxCount }.map(\.key)
        if mostCommon.count == 1 { return mostCommon[0] }
        // Among tied variants, prefer the one that looks like title case
        // (first letter uppercase, rest not all uppercase).
        for candidate in mostCommon {
            let chars = Array(candidate)
            if chars.first?.isUppercase == true,
               chars.dropFirst().contains(where: \.isLowercase) {
                return candidate
            }
        }
        return first
    }
}
