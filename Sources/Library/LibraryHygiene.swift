import Foundation
import os
import SwiftData

public struct LibraryMaintenanceProgress: Equatable, Sendable {
    public let operation: String
    public let completed: Int
    public let total: Int?

    public init(operation: String, completed: Int, total: Int? = nil) {
        self.operation = operation
        self.completed = completed
        self.total = total
    }
}

public struct OrphanCleanupResult: Equatable, Sendable {
    public let albums: Int
    public let artists: Int
}

public struct LibraryMaintenanceProgressReporter: Sendable {
    private let handler: @Sendable (LibraryMaintenanceProgress) async -> Void

    public init(_ handler: @escaping @Sendable (LibraryMaintenanceProgress) async -> Void) {
        self.handler = handler
    }

    public func report(_ progress: LibraryMaintenanceProgress) async {
        await handler(progress)
    }
}

public struct LibraryMaintenancePreview: Equatable, Sendable {
    public var missingTracks: Int
    public var unavailableTracks: Int
    public var emptyAlbums: Int
    public var emptyArtists: Int

    public init(
        missingTracks: Int = 0,
        unavailableTracks: Int = 0,
        emptyAlbums: Int = 0,
        emptyArtists: Int = 0
    ) {
        self.missingTracks = missingTracks
        self.unavailableTracks = unavailableTracks
        self.emptyAlbums = emptyAlbums
        self.emptyArtists = emptyArtists
    }
}

/// Cancellable, actor-isolated maintenance. No model or filesystem traversal reaches the main actor.
public actor LibraryMaintenanceService {
    private let container: ModelContainer
    private let pathResolver: FilesystemPathResolver
    private let signposter = OSSignposter(subsystem: "Songbird", category: "LibraryMaintenance")

    public init(modelContainer: ModelContainer) {
        container = modelContainer
        pathResolver = FilesystemPathResolver()
    }

    init(modelContainer: ModelContainer, pathResolver: FilesystemPathResolver) {
        container = modelContainer
        self.pathResolver = pathResolver
    }

    public func previewMissingTracks(
        progress: LibraryMaintenanceProgressReporter? = nil
    ) async throws -> LibraryMaintenancePreview {
        let context = ModelContext(container)
        let tracks = try context.fetch(FetchDescriptor<Track>())
        var missing = 0
        var unavailable = 0
        var cache = FilesystemPathResolver.Cache()
        for (index, track) in tracks.enumerated() {
            try Task.checkCancellation()
            switch pathResolver.resolve(track.path, cache: &cache) {
            case .available:
                break
            case .missing:
                missing += 1
            case .unavailable:
                unavailable += 1
            }
            if index.isMultiple(of: 50) {
                await progress?.report(.init(
                    operation: "Counting missing files",
                    completed: index,
                    total: tracks.count
                ))
            }
        }
        await progress?.report(.init(
            operation: "Counting missing files",
            completed: tracks.count,
            total: tracks.count
        ))
        return LibraryMaintenancePreview(
            missingTracks: missing,
            unavailableTracks: unavailable
        )
    }

    public func previewOrphanAlbumsAndArtists() async throws -> LibraryMaintenancePreview {
        let context = ModelContext(container)
        let albums = try context.fetch(FetchDescriptor<Album>())
        let artists = try context.fetch(FetchDescriptor<Artist>())
        try Task.checkCancellation()
        return LibraryMaintenancePreview(
            emptyAlbums: albums.lazy.filter(\.tracks.isEmpty).count,
            emptyArtists: artists.lazy.filter(\.tracks.isEmpty).count
        )
    }

    public func removeMissingTracks(progress: LibraryMaintenanceProgressReporter? = nil) async throws -> Int {
        let state = signposter.beginInterval("Remove missing tracks")
        defer { signposter.endInterval("Remove missing tracks", state) }
        let context = ModelContext(container)
        let tracks = try context.fetch(FetchDescriptor<Track>())
        var removed = 0
        var cache = FilesystemPathResolver.Cache()
        for (index, track) in tracks.enumerated() {
            try Task.checkCancellation()
            if case .missing = pathResolver.resolve(track.path, cache: &cache) {
                context.delete(track)
                removed += 1
            }
            if index.isMultiple(of: 50) {
                await progress?.report(.init(operation: "Checking for missing files", completed: index, total: tracks.count))
            }
        }
        if removed > 0 { try context.save() }
        await progress?.report(.init(operation: "Checking for missing files", completed: tracks.count, total: tracks.count))
        return removed
    }

    public func relocateTracks(
        from oldRoot: String,
        to newRoot: String,
        progress: LibraryMaintenanceProgressReporter? = nil
    ) async throws -> Int {
        let state = signposter.beginInterval("Relocate tracks")
        defer { signposter.endInterval("Relocate tracks", state) }
        let old = (oldRoot as NSString).standardizingPath
        let newBase = (newRoot as NSString).standardizingPath
        guard !old.isEmpty, !newBase.isEmpty else { return 0 }
        let context = ModelContext(container)
        let tracks = try context.fetch(FetchDescriptor<Track>())
        var updated = 0
        var cache = FilesystemPathResolver.Cache()
        for (index, track) in tracks.enumerated() {
            try Task.checkCancellation()
            let path = (track.path as NSString).standardizingPath
            if path.hasPrefix(old) {
                let suffix = String(path.dropFirst(old.count))
                let candidate = (newBase as NSString).appendingPathComponent(
                    suffix.hasPrefix("/") ? String(suffix.dropFirst()) : suffix
                )
                if let resolved = pathResolver.existingFileURL(for: candidate, cache: &cache) {
                    update(track: track, to: resolved.path)
                    updated += 1
                }
            }
            if index.isMultiple(of: 25) {
                await progress?.report(.init(operation: "Relocating library files", completed: index, total: tracks.count))
            }
        }
        if updated > 0 { try context.save() }
        await progress?.report(.init(operation: "Relocating library files", completed: tracks.count, total: tracks.count))
        return updated
    }

    public func locateMissingTracks(
        searchRoots: [String],
        progress: LibraryMaintenanceProgressReporter? = nil
    ) async throws -> Int {
        let state = signposter.beginInterval("Locate missing tracks")
        defer { signposter.endInterval("Locate missing tracks", state) }
        var cache = FilesystemPathResolver.Cache()
        let roots: [String] = searchRoots.compactMap { rawPath -> String? in
            let path = (rawPath as NSString).standardizingPath
            guard !path.isEmpty else { return nil }
            return pathResolver.existingFileURL(for: path, cache: &cache)?.path
        }
        guard !roots.isEmpty else { return 0 }
        let context = ModelContext(container)
        let tracks = try context.fetch(FetchDescriptor<Track>())
        let missing = tracks.filter {
            if case .missing = pathResolver.resolve($0.path, cache: &cache) { return true }
            return false
        }
        var updated = 0
        for (index, track) in missing.enumerated() {
            try Task.checkCancellation()
            let filename = (track.path as NSString).lastPathComponent
            var matches: [String] = []
            for root in roots {
                matches.append(contentsOf: try findFilename(filename, under: root, limit: 2 - matches.count))
                if matches.count > 1 { break }
            }
            if matches.count == 1, let path = matches.first {
                update(track: track, to: path)
                updated += 1
            }
            await progress?.report(.init(operation: "Locating missing files", completed: index + 1, total: missing.count))
        }
        if updated > 0 { try context.save() }
        return updated
    }

    public func removeOrphanAlbumsAndArtists(progress: LibraryMaintenanceProgressReporter? = nil) async throws -> OrphanCleanupResult {
        let state = signposter.beginInterval("Clean orphan metadata")
        defer { signposter.endInterval("Clean orphan metadata", state) }
        let context = ModelContext(container)
        let albums = try context.fetch(FetchDescriptor<Album>())
        let artists = try context.fetch(FetchDescriptor<Artist>())
        let favorites = try context.fetch(FetchDescriptor<AlbumFavorite>())
        let survivingAlbumIDs = Set(albums.lazy.filter { !$0.tracks.isEmpty }.map(\.id))
        let total = albums.count + artists.count
        var albumsRemoved = 0
        var artistsRemoved = 0
        var completed = 0
        var favoritesRemoved = 0
        for album in albums {
            try Task.checkCancellation()
            if album.tracks.isEmpty {
                context.delete(album)
                albumsRemoved += 1
            }
            completed += 1
            if completed.isMultiple(of: 50) {
                await progress?.report(.init(operation: "Cleaning empty albums and artists", completed: completed, total: total))
            }
        }
        for artist in artists {
            try Task.checkCancellation()
            if artist.tracks.isEmpty {
                context.delete(artist)
                artistsRemoved += 1
            }
            completed += 1
            if completed.isMultiple(of: 50) {
                await progress?.report(.init(operation: "Cleaning empty albums and artists", completed: completed, total: total))
            }
        }
        for favorite in favorites where survivingAlbumIDs.contains(favorite.albumID) == false {
            context.delete(favorite)
            favoritesRemoved += 1
        }
        if albumsRemoved > 0 || artistsRemoved > 0 || favoritesRemoved > 0 {
            try context.save()
        }
        await progress?.report(.init(operation: "Cleaning empty albums and artists", completed: total, total: total))
        return .init(albums: albumsRemoved, artists: artistsRemoved)
    }

    private func update(track: Track, to path: String) {
        track.path = Track.standardizedPath(path)
        track.checksum = Track.contentChecksum(at: path)
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        track.fileSize = (attributes?[.size] as? Int64) ?? track.fileSize
        track.dateModified = (attributes?[.modificationDate] as? Date) ?? track.dateModified
    }

    private func findFilename(_ name: String, under root: String, limit: Int) throws -> [String] {
        guard limit > 0, let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        var results: [String] = []
        while let relative = enumerator.nextObject() as? String {
            try Task.checkCancellation()
            if (relative as NSString).lastPathComponent.caseInsensitiveCompare(name) == .orderedSame {
                results.append((root as NSString).appendingPathComponent(relative))
                if results.count >= limit { break }
            }
        }
        return results
    }
}

public enum LibraryHygiene {
    @discardableResult
    @MainActor
    public static func removeMissingTracks(in context: ModelContext) -> Int {
        do {
            let tracks = try context.fetch(FetchDescriptor<Track>())
            var removed = 0
            let resolver = FilesystemPathResolver()
            for track in tracks {
                if case .missing = resolver.resolve(track.path) {
                    context.delete(track)
                    removed += 1
                }
            }
            if removed > 0 { try context.save() }
            return removed
        } catch {
            context.rollback()
            report(error, operation: "remove missing tracks")
            return 0
        }
    }

    @discardableResult
    @MainActor
    public static func removeTrackIfPresent(path: String, in context: ModelContext) -> Bool {
        let standardized = (path as NSString).standardizingPath
        var descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.path == standardized })
        descriptor.fetchLimit = 1
        do {
            if let track = try context.fetch(descriptor).first {
                context.delete(track)
                return true
            }
            var alternate = FetchDescriptor<Track>(predicate: #Predicate { $0.path == path })
            alternate.fetchLimit = 1
            guard let track = try context.fetch(alternate).first else { return false }
            context.delete(track)
            return true
        } catch {
            report(error, operation: "update the watched library folder")
            return false
        }
    }

    @discardableResult
    @MainActor
    public static func relocateTracks(from oldRoot: String, to newRoot: String, in context: ModelContext) -> Int {
        let old = (oldRoot as NSString).standardizingPath
        let newBase = (newRoot as NSString).standardizingPath
        guard !old.isEmpty, !newBase.isEmpty else { return 0 }
        let tracks: [Track]
        do {
            tracks = try context.fetch(FetchDescriptor<Track>())
        } catch {
            report(error, operation: "read tracks for relocation")
            return 0
        }
        var updated = 0
        for track in tracks {
            let path = (track.path as NSString).standardizingPath
            guard path.hasPrefix(old) else { continue }
            let suffix = String(path.dropFirst(old.count))
            let candidate = (newBase as NSString).appendingPathComponent(
                suffix.hasPrefix("/") ? String(suffix.dropFirst()) : suffix
            )
            if case .available(let actualURL) = FilesystemPathResolver().resolve(candidate) {
                let actualPath = actualURL.path
                track.path = Track.standardizedPath(actualPath)
                track.checksum = Track.contentChecksum(at: actualPath)
                let attrs = try? FileManager.default.attributesOfItem(atPath: actualPath)
                track.fileSize = (attrs?[.size] as? Int64) ?? track.fileSize
                if let mtime = attrs?[.modificationDate] as? Date {
                    track.dateModified = mtime
                }
                updated += 1
            }
        }
        if updated > 0 {
            do {
                try context.save()
            } catch {
                context.rollback()
                report(error, operation: "save relocated tracks")
                return 0
            }
        }
        return updated
    }

    /// Groups non-empty checksums that appear more than once.
    @MainActor
    public static func duplicateGroups(in context: ModelContext) -> [[Track]] {
        let tracks: [Track]
        do {
            tracks = try context.fetch(FetchDescriptor<Track>())
        } catch {
            report(error, operation: "read tracks for duplicate analysis")
            return []
        }
        var byChecksum: [String: [Track]] = [:]
        for track in tracks {
            let key = track.checksum
            guard !key.isEmpty else { continue }
            byChecksum[key, default: []].append(track)
        }
        return byChecksum.values.filter { $0.count > 1 }
    }

    /// Keeps the first track in each duplicate group; removes the rest from the library.
    @discardableResult
    @MainActor
    public static func removeDuplicateTracks(in context: ModelContext) -> Int {
        var removed = 0
        for group in duplicateGroups(in: context) {
            let sorted = group.sorted { $0.dateAdded < $1.dateAdded }
            for track in sorted.dropFirst() {
                context.delete(track)
                removed += 1
            }
        }
        if removed > 0 {
            do {
                try context.save()
            } catch {
                context.rollback()
                report(error, operation: "remove duplicate tracks")
                return 0
            }
        }
        return removed
    }

    @discardableResult
    @MainActor
    public static func removeOrphanAlbumsAndArtists(in context: ModelContext) -> (albums: Int, artists: Int) {
        let albums: [Album]
        let artists: [Artist]
        let favorites: [AlbumFavorite]
        do {
            albums = try context.fetch(FetchDescriptor<Album>())
            artists = try context.fetch(FetchDescriptor<Artist>())
            favorites = try context.fetch(FetchDescriptor<AlbumFavorite>())
        } catch {
            report(error, operation: "read empty library records")
            return (0, 0)
        }
        let survivingAlbumIDs = Set(albums.lazy.filter { !$0.tracks.isEmpty }.map(\.id))
        var albumsRemoved = 0
        var artistsRemoved = 0
        for album in albums where album.tracks.isEmpty {
            context.delete(album)
            albumsRemoved += 1
        }
        for artist in artists where artist.tracks.isEmpty {
            context.delete(artist)
            artistsRemoved += 1
        }
        var favoritesRemoved = 0
        for favorite in favorites where survivingAlbumIDs.contains(favorite.albumID) == false {
            context.delete(favorite)
            favoritesRemoved += 1
        }
        if albumsRemoved > 0 || artistsRemoved > 0 || favoritesRemoved > 0 {
            do {
                try context.save()
            } catch {
                context.rollback()
                report(error, operation: "clean empty library records")
                return (0, 0)
            }
        }
        return (albumsRemoved, artistsRemoved)
    }

    /// Search library folders for the same filename; update path when exactly one match.
    @discardableResult
    @MainActor
    public static func locateMissingTracks(
        in context: ModelContext,
        searchRoots: [String]
    ) -> Int {
        let roots = searchRoots
            .map { ($0 as NSString).standardizingPath }
            .filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }
        guard !roots.isEmpty else { return 0 }

        let tracks: [Track]
        do {
            tracks = try context.fetch(FetchDescriptor<Track>())
        } catch {
            report(error, operation: "read missing tracks")
            return 0
        }
        var updated = 0
        let resolver = FilesystemPathResolver()
        for track in tracks where resolver.resolve(track.path) == .missing {
            let name = (track.path as NSString).lastPathComponent
            var matches: [String] = []
            for root in roots {
                let found = findFilename(name, under: root)
                matches.append(contentsOf: found)
                if matches.count > 1 { break }
            }
            if matches.count == 1, let path = matches.first {
                track.path = Track.standardizedPath(path)
                track.checksum = Track.contentChecksum(at: path)
                let attrs = try? FileManager.default.attributesOfItem(atPath: path)
                track.fileSize = (attrs?[.size] as? Int64) ?? track.fileSize
                if let mtime = attrs?[.modificationDate] as? Date {
                    track.dateModified = mtime
                }
                updated += 1
            }
        }
        if updated > 0 {
            do {
                try context.save()
            } catch {
                context.rollback()
                report(error, operation: "save located tracks")
                return 0
            }
        }
        return updated
    }

    private static func findFilename(_ name: String, under root: String) -> [String] {
        var results: [String] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: root) else { return [] }
        while let relative = enumerator.nextObject() as? String {
            if (relative as NSString).lastPathComponent.caseInsensitiveCompare(name) == .orderedSame {
                results.append((root as NSString).appendingPathComponent(relative))
                if results.count > 1 { return results }
            }
        }
        return results
    }

    @MainActor
    private static func report(_ error: Error, operation: String) {
        LibraryStatus.shared.showPlaybackError(
            "Could not \(operation): \(error.localizedDescription)"
        )
    }
}
