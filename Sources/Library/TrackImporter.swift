import Foundation
import SwiftData

/// The result of explicitly re-reading one existing track's local metadata.
public enum TrackMetadataRefreshOutcome: Equatable, Sendable {
    /// Metadata was read and applied to the track.
    case refreshed
    /// The track's local file was unavailable when the refresh ran.
    case fileMissing
    /// The containing volume or path could not be inspected reliably.
    case fileUnavailable
    /// The local file existed, but Songbird could not read audio metadata from it.
    case unreadable
}

/// Shared import path for drop, scan, and Open File(s).
@MainActor
public enum TrackImporter {
    /// Imports audio files at the given URLs. Returns how many new tracks were added.
    @discardableResult
    public static func importURLs(_ urls: [URL], into context: ModelContext) async throws -> Int {
        var added = 0
        for url in urls {
            if try await importURL(url, into: context) != nil {
                added += 1
            }
        }
        do {
            _ = try AlbumRelationshipReconciler.reconcile(in: context)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return added
    }

    /// Collects audio files from a folder (or returns `[url]` if it is a file).
    nonisolated public static func collectAudioURLs(from url: URL) -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            return supportedExtensions.contains(url.pathExtension.lowercased()) ? [url] : []
        }
        var files: [URL] = []
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        while let fileURL = enumerator.nextObject() as? URL {
            if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                files.append(fileURL)
            }
        }
        return files
    }

    @discardableResult
    public static func importURL(_ url: URL, into context: ModelContext) async throws -> Track? {
        let path = Track.standardizedPath(url.path)
        let canonicalKey = LibraryPathIdentity.key(path)
        let matches = try context.fetch(FetchDescriptor<Track>()).filter {
            LibraryPathIdentity.key($0.path) == canonicalKey
        }
        guard matches.count <= 1 else {
            throw LibraryImportPathError.canonicalCollision(matches.map(\.path))
        }
        if let existing = matches.first {
            if !LibraryPathIdentity.hasSameScalarSpelling(existing.path, path) {
                existing.path = path
            }
            if existing.resolvedArtworkData == nil,
               let folderArtwork = folderArtworkData(for: url) {
                try linkRelations(for: existing, artworkData: folderArtwork, in: context)
            }
            let filenameTitle = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let tagsLookEmpty = existing.artist == "Unknown Artist"
                || existing.album == "Unknown Album"
                || existing.title == filenameTitle
                || existing.title.range(of: #"^\d{1,2}-\d{2}\s"#, options: .regularExpression) != nil
            if tagsLookEmpty {
                _ = try await refreshMetadata(for: existing, in: context)
            } else {
                try await refreshIfChanged(existing, at: path, in: context)
            }
            return nil
        }
        guard let meta = await MetadataReader.read(from: url) else { return nil }

        let track = Track(path: path, title: meta.title, artist: meta.artist, album: meta.album)
        apply(meta, to: track, path: path)
        track.checksum = Track.contentChecksum(at: path)
        context.insert(track)
        try linkRelations(
            for: track,
            artworkData: meta.artworkData ?? folderArtworkData(for: url),
            in: context
        )
        return track
    }

    /// Cheap size+mtime check; only hash + re-read when the file changed.
    @discardableResult
    public static func refreshIfChanged(_ track: Track, at path: String, in context: ModelContext) async throws -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? Int64) ?? 0
        let mtime = attrs?[.modificationDate] as? Date
        if size == track.fileSize,
           let mtime,
           abs(mtime.timeIntervalSince(track.dateModified)) < 1 {
            return false
        }
        let checksum = Track.contentChecksum(at: path)
        if checksum == track.checksum, !checksum.isEmpty {
            track.fileSize = size
            if let mtime { track.dateModified = mtime }
            return false
        }
        return try await refreshMetadata(for: track, in: context) == .refreshed
    }

    /// Re-reads local metadata into an existing track while preserving identity and play statistics.
    ///
    /// - Returns: A result that distinguishes a refreshed track from a missing or unreadable file.
    @discardableResult
    public static func refreshMetadata(
        for track: Track,
        in context: ModelContext
    ) async throws -> TrackMetadataRefreshOutcome {
        let resolution = await FileAvailabilityWorker().resolve(path: track.path)
        let url: URL
        switch resolution {
        case .available(let actualURL):
            url = actualURL
        case .missing:
            return .fileMissing
        case .unavailable:
            return .fileUnavailable
        }
        guard let meta = await MetadataReader.read(from: url) else { return .unreadable }
        let livePath = Track.standardizedPath(url.path)
        track.path = livePath
        apply(meta, to: track, path: livePath)
        try linkRelations(
            for: track,
            artworkData: meta.artworkData ?? folderArtworkData(for: url),
            in: context
        )
        return .refreshed
    }

    private static func apply(_ meta: AudioMetadata, to track: Track, path: String) {
        track.title = meta.title
        track.artist = meta.artist
        track.album = meta.album
        track.albumArtist = meta.albumArtist
        track.genre = meta.genre
        track.composer = meta.composer
        track.comment = meta.comment
        track.year = meta.year
        track.trackNumber = meta.trackNumber
        track.trackTotal = meta.trackTotal
        track.discNumber = meta.discNumber
        track.discTotal = meta.discTotal
        track.beatsPerMinute = meta.beatsPerMinute
        track.duration = meta.duration
        track.bitrate = meta.bitrate
        track.sampleRate = meta.sampleRate
        track.artworkData = nil
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        track.fileSize = (attrs?[.size] as? Int64) ?? 0
        if let mtime = attrs?[.modificationDate] as? Date {
            track.dateModified = mtime
        }
        track.checksum = Track.contentChecksum(at: path)
    }

    /// Finds an immediate sibling named cover.jpg, ignoring filename case.
    /// Keeping this lookup local to the audio folder prevents art from one
    /// album being applied to tracks in another nested folder.
    nonisolated static func folderArtworkData(for audioURL: URL) -> Data? {
        let folderURL = audioURL.deletingLastPathComponent()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        guard let coverURL = entries.first(where: {
            $0.lastPathComponent.caseInsensitiveCompare("cover.jpg") == .orderedSame
        }),
        let values = try? coverURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
        values.isRegularFile == true,
        let byteCount = values.fileSize,
        byteCount > 0,
        byteCount <= 25 * 1024 * 1024 else { return nil }

        return try? Data(contentsOf: coverURL, options: .mappedIfSafe)
    }

    public static func linkRelations(
        for track: Track,
        artworkData: Data? = nil,
        in context: ModelContext
    ) throws {
        let artistName = track.artist.isEmpty ? "Unknown Artist" : track.artist
        let albumTitle = track.album.isEmpty ? "Unknown Album" : track.album
        let rawAlbumArtist = track.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let albumArtistName = rawAlbumArtist.isEmpty || rawAlbumArtist == "Unknown Artist"
            ? artistName
            : rawAlbumArtist

        let artist: Artist
        var artistDesc = FetchDescriptor<Artist>(predicate: #Predicate { $0.name == artistName })
        artistDesc.fetchLimit = 1
        if let found = try context.fetch(artistDesc).first {
            artist = found
        } else {
            artist = Artist(name: artistName)
            context.insert(artist)
        }
        track.artistRelation = artist

        let identity = AlbumPhysicalIdentity(
            title: albumTitle,
            path: track.path,
            performer: albumArtistName
        )
        let albums = try context.fetch(FetchDescriptor<Album>())
        let matchingAlbum = albums.first { candidate in
            candidate.tracks.contains { relatedTrack in
                relatedTrack.id != track.id
                    && AlbumRelationshipReconciler.physicalIdentity(for: relatedTrack) == identity
            }
        }
        let reusableCurrentAlbum = track.albumRelation.flatMap { current in
            current.tracks.allSatisfy { $0.id == track.id } ? current : nil
        }

        let album: Album
        if let found = matchingAlbum ?? reusableCurrentAlbum {
            album = found
        } else {
            album = Album(title: albumTitle, artist: albumArtistName, year: track.year)
            album.artworkData = artworkData.map(ArtworkStorage.normalized)
            context.insert(album)
        }
        album.title = albumTitle
        if album.artworkData == nil {
            album.artworkData = artworkData.map(ArtworkStorage.normalized)
        }
        track.albumRelation = album
        track.artworkData = nil
    }
}

private enum LibraryImportPathError: LocalizedError {
    case canonicalCollision([String])

    var errorDescription: String? {
        switch self {
        case .canonicalCollision(let paths):
            "The library already contains canonically equivalent paths: \(paths.joined(separator: ", "))"
        }
    }
}
