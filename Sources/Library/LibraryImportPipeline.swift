import Foundation
import SwiftData

public struct LibraryImportResult: Sendable {
    public let discovered: Int
    public let processed: Int
    public let added: Int
    public let cancelled: Bool
    public let failureMessage: String?
}

struct ExistingTrackSnapshot: Sendable {
    let path: String
    let fileSize: Int64
    let dateModified: Date
    let checksum: String
    let needsArtwork: Bool
}

struct PreparedImport: Sendable {
    enum Action: Sendable {
        case skip
        case touch(checksum: String)
        case refresh(checksum: String?)
        case insert(checksum: String)
    }

    let url: URL
    let existingPath: String?
    let fileSize: Int64
    let dateModified: Date
    let metadata: AudioMetadata?
    let folderArtwork: Data?
    let action: Action
}

enum LibraryPathIdentity {
    /// Canonical-equivalence identity used only for matching. Stored paths keep
    /// the filesystem's scalar spelling and matching remains case-sensitive.
    static func key(_ path: String) -> String {
        Track.standardizedPath(path).precomposedStringWithCanonicalMapping
    }

    static func hasSameScalarSpelling(_ lhs: String, _ rhs: String) -> Bool {
        lhs.unicodeScalars.elementsEqual(rhs.unicodeScalars)
    }
}

private struct LibraryCanonicalPathCollision: LocalizedError {
    let first: String
    let second: String

    var errorDescription: String? {
        "The library contains canonically equivalent paths and cannot be reconciled safely: \(first) and \(second)"
    }
}

private actor FolderArtworkCache {
    private static let maximumEntries = 16
    private static let maximumBytes = 16 * 1024 * 1024

    private var values: [String: Data] = [:]
    private var insertionOrder: [String] = []
    private var cachedBytes = 0
    private var misses = Set<String>()

    func artwork(for audioURL: URL) -> Data? {
        let folder = audioURL.deletingLastPathComponent().standardizedFileURL.path
        if let value = values[folder] { return value }
        if misses.contains(folder) { return nil }
        if let value = TrackImporter.folderArtworkData(for: audioURL).map(ArtworkStorage.normalized) {
            // Import paths are sorted, so a small rolling cache covers adjacent
            // tracks without retaining every cover image for the entire scan.
            if value.count <= Self.maximumBytes {
                while !insertionOrder.isEmpty,
                      values.count >= Self.maximumEntries
                        || cachedBytes + value.count > Self.maximumBytes {
                    let evicted = insertionOrder.removeFirst()
                    if let removed = values.removeValue(forKey: evicted) {
                        cachedBytes -= removed.count
                    }
                }
                values[folder] = value
                insertionOrder.append(folder)
                cachedBytes += value.count
            }
            return value
        }
        misses.insert(folder)
        return nil
    }
}

private actor LibraryImportAdmissionGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var isHeld = false
    private var pendingRegistrations = Set<UUID>()
    private var cancelledRegistrations = Set<UUID>()
    private var waiters: [Waiter] = []

    func acquire() async -> Bool {
        guard Task.isCancelled == false else { return false }
        guard isHeld else {
            isHeld = true
            return true
        }

        let id = UUID()
        pendingRegistrations.insert(id)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingRegistrations.remove(id)
                if cancelledRegistrations.remove(id) != nil || Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume(returning: true)
        }
    }

    private func cancel(id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(returning: false)
        } else if pendingRegistrations.contains(id) {
            cancelledRegistrations.insert(id)
        }
    }
}

private actor LibraryImportStore {
    private let container: ModelContainer
    private var albumIDsByPhysicalKey: [String: UUID] = [:]

    init(container: ModelContainer) {
        self.container = container
    }

    func preload() throws -> [String: ExistingTrackSnapshot] {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Track>()
        descriptor.relationshipKeyPathsForPrefetching = [\Track.albumRelation]
        let tracks = try context.fetch(descriptor)
        for track in tracks {
            guard let albumID = track.albumRelation?.id else { continue }
            albumIDsByPhysicalKey[
                AlbumRelationshipReconciler.physicalIdentity(for: track).stableKey,
                default: albumID
            ] = albumID
        }

        var result: [String: ExistingTrackSnapshot] = [:]
        for track in tracks {
            let key = LibraryPathIdentity.key(track.path)
            if let collision = result[key],
               !LibraryPathIdentity.hasSameScalarSpelling(collision.path, track.path) {
                throw LibraryCanonicalPathCollision(first: collision.path, second: track.path)
            }
            result[key] = ExistingTrackSnapshot(
                path: track.path,
                fileSize: track.fileSize,
                dateModified: track.dateModified,
                checksum: track.checksum,
                needsArtwork: track.resolvedArtworkData == nil
            )
        }
        return result
    }

    func apply(_ records: [PreparedImport]) throws -> Int {
        // A fresh context per commit batch allows SwiftData to release imported
        // models and relationship faults instead of retaining the whole scan.
        let context = ModelContext(container)
        var tracksByPath: [String: Track] = [:]
        var artistsByName: [String: Artist] = [:]
        var albumsByKey: [String: Album] = [:]
        var added = 0

        func track(at path: String) throws -> Track? {
            if let cached = tracksByPath[path] { return cached }
            var descriptor = FetchDescriptor<Track>(
                predicate: #Predicate { $0.path == path }
            )
            descriptor.fetchLimit = 1
            let found = try context.fetch(descriptor).first
            if let found { tracksByPath[path] = found }
            return found
        }

        func link(_ track: Track, artwork: Data?) throws {
            let artistName = track.artist.isEmpty ? "Unknown Artist" : track.artist
            let albumTitle = track.album.isEmpty ? "Unknown Album" : track.album
            let albumArtistName = Self.canonicalAlbumArtist(for: track)

            let artist: Artist
            if let cached = artistsByName[artistName] {
                artist = cached
            } else {
                var descriptor = FetchDescriptor<Artist>(
                    predicate: #Predicate { $0.name == artistName }
                )
                descriptor.fetchLimit = 1
                if let found = try context.fetch(descriptor).first {
                    artist = found
                } else {
                    artist = Artist(name: artistName)
                    context.insert(artist)
                }
                artistsByName[artistName] = artist
            }
            track.artistRelation = artist

            let identity = AlbumPhysicalIdentity(
                title: albumTitle,
                path: track.path,
                performer: albumArtistName
            )
            let key = identity.stableKey
            let album: Album
            if let cached = albumsByKey[key] {
                album = cached
            } else {
                let knownID = albumIDsByPhysicalKey[key]
                let found: Album?
                if let knownID {
                    var descriptor = FetchDescriptor<Album>(
                        predicate: #Predicate { $0.id == knownID }
                    )
                    descriptor.fetchLimit = 1
                    found = try context.fetch(descriptor).first
                } else {
                    found = nil
                }
                if let found {
                    album = found
                } else {
                    album = Album(title: albumTitle, artist: albumArtistName, year: track.year)
                    album.artworkData = artwork
                    context.insert(album)
                    albumIDsByPhysicalKey[key] = album.id
                }
                albumsByKey[key] = album
            }
            if album.artworkData == nil { album.artworkData = artwork }
            track.albumRelation = album
            track.artworkData = nil
        }

        for record in records {
            let livePath = Track.standardizedPath(record.url.path)
            let matchedTrack = try record.existingPath.flatMap { try track(at: $0) }
            if let matchedTrack,
               !LibraryPathIdentity.hasSameScalarSpelling(matchedTrack.path, livePath) {
                matchedTrack.path = livePath
                tracksByPath[livePath] = matchedTrack
            }
            switch record.action {
            case .skip:
                if let track = matchedTrack, track.resolvedArtworkData == nil,
                   let artwork = record.folderArtwork {
                    try link(track, artwork: artwork)
                }
                continue
            case let .touch(checksum):
                guard let track = try matchedTrack ?? track(at: livePath) else { continue }
                track.fileSize = record.fileSize
                track.dateModified = record.dateModified
                track.checksum = checksum
                if track.resolvedArtworkData == nil, let artwork = record.folderArtwork {
                    try link(track, artwork: artwork)
                }
            case let .refresh(checksum):
                guard let track = try matchedTrack ?? track(at: livePath),
                      let metadata = record.metadata else { continue }
                apply(metadata, fileSize: record.fileSize, dateModified: record.dateModified, to: track)
                if let checksum { track.checksum = checksum }
                try link(track, artwork: metadata.artworkData ?? record.folderArtwork)
            case let .insert(checksum):
                guard let metadata = record.metadata else { continue }
                let path = livePath
                if let existing = try track(at: path) {
                    apply(
                        metadata,
                        fileSize: record.fileSize,
                        dateModified: record.dateModified,
                        to: existing
                    )
                    existing.checksum = checksum
                    try link(existing, artwork: metadata.artworkData ?? record.folderArtwork)
                    continue
                }
                let track = Track(
                    path: path,
                    title: metadata.title,
                    artist: metadata.artist,
                    album: metadata.album
                )
                apply(metadata, fileSize: record.fileSize, dateModified: record.dateModified, to: track)
                track.checksum = checksum
                context.insert(track)
                tracksByPath[path] = track
                try link(track, artwork: metadata.artworkData ?? record.folderArtwork)
                added += 1
            }
        }
        try context.save()
        return added
    }

    private func apply(
        _ metadata: AudioMetadata,
        fileSize: Int64,
        dateModified: Date,
        to track: Track
    ) {
        track.title = metadata.title
        track.artist = metadata.artist
        track.album = metadata.album
        track.albumArtist = metadata.albumArtist
        track.genre = metadata.genre
        track.composer = metadata.composer
        track.comment = metadata.comment
        track.year = metadata.year
        track.trackNumber = metadata.trackNumber
        track.trackTotal = metadata.trackTotal
        track.discNumber = metadata.discNumber
        track.discTotal = metadata.discTotal
        track.beatsPerMinute = metadata.beatsPerMinute
        track.duration = metadata.duration
        track.bitrate = metadata.bitrate
        track.sampleRate = metadata.sampleRate
        track.fileSize = fileSize
        track.dateModified = dateModified
        track.artworkData = nil
    }

    private static func canonicalAlbumArtist(for track: Track) -> String {
        let albumArtist = track.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !albumArtist.isEmpty, albumArtist != "Unknown Artist" {
            return albumArtist
        }
        return track.artist.isEmpty ? "Unknown Artist" : track.artist
    }
}

public enum LibraryImportPipeline {
    public static let metadataConcurrency = 4
    public static let commitBatchSize = 64
    private static let admissionGate = LibraryImportAdmissionGate()

    static func acquireExclusiveMaintenanceAccess() async throws {
        guard await admissionGate.acquire() else { throw CancellationError() }
    }

    static func releaseExclusiveMaintenanceAccess() async {
        await admissionGate.release()
    }

    public static func discoverAudioURLs(from roots: [URL]) async -> [URL] {
        await Task.detached(priority: .utility) {
            var seen = Set<String>()
            var files: [URL] = []
            for root in roots {
                if Task.isCancelled { break }
                for url in TrackImporter.collectAudioURLs(from: root) {
                    if Task.isCancelled { break }
                    let path = Track.standardizedPath(url.path)
                    if seen.insert(path).inserted {
                        files.append(URL(fileURLWithPath: path))
                    }
                }
            }
            return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }.value
    }

    public static func run(
        roots: [URL],
        container: ModelContainer,
        progress: @escaping (Int, Int) async -> Void
    ) async -> LibraryImportResult {
        await runDeliberate(
            roots: roots,
            container: container,
            exclusionStore: .shared,
            progress: progress
        )
    }

    static func runDeliberate(
        roots: [URL],
        container: ModelContainer,
        exclusionStore: LibraryImportExclusionStore,
        progress: @escaping (Int, Int) async -> Void
    ) async -> LibraryImportResult {
        await run(
            roots: roots,
            container: container,
            automatic: false,
            exclusionStore: exclusionStore,
            progress: progress
        )
    }

    static func runAutomatic(
        roots: [URL],
        container: ModelContainer,
        exclusionStore: LibraryImportExclusionStore = .shared,
        progress: @escaping (Int, Int) async -> Void
    ) async -> LibraryImportResult {
        await run(
            roots: roots,
            container: container,
            automatic: true,
            exclusionStore: exclusionStore,
            progress: progress
        )
    }

    private static func run(
        roots: [URL],
        container: ModelContainer,
        automatic: Bool,
        exclusionStore: LibraryImportExclusionStore,
        progress: @escaping (Int, Int) async -> Void
    ) async -> LibraryImportResult {
        guard await admissionGate.acquire() else {
            return LibraryImportResult(
                discovered: 0,
                processed: 0,
                added: 0,
                cancelled: true,
                failureMessage: nil
            )
        }
        if Task.isCancelled {
            await admissionGate.release()
            return LibraryImportResult(
                discovered: 0,
                processed: 0,
                added: 0,
                cancelled: true,
                failureMessage: nil
            )
        }

        let result = await runExclusively(
            roots: roots,
            container: container,
            automatic: automatic,
            exclusionStore: exclusionStore,
            progress: progress
        )
        await admissionGate.release()
        return result
    }

    private static func runExclusively(
        roots: [URL],
        container: ModelContainer,
        automatic: Bool,
        exclusionStore: LibraryImportExclusionStore,
        progress: @escaping (Int, Int) async -> Void
    ) async -> LibraryImportResult {
        var files = await discoverAudioURLs(from: roots)
        if automatic {
            files.removeAll { exclusionStore.contains($0.path) }
        }
        if Task.isCancelled {
            return LibraryImportResult(
                discovered: files.count,
                processed: 0,
                added: 0,
                cancelled: true,
                failureMessage: nil
            )
        }

        let store = LibraryImportStore(container: container)
        let existing: [String: ExistingTrackSnapshot]
        do {
            existing = try await store.preload()
        } catch {
            return LibraryImportResult(
                discovered: files.count,
                processed: 0,
                added: 0,
                cancelled: false,
                failureMessage: "Could not read the library before importing: \(error.localizedDescription)"
            )
        }
        let artworkCache = FolderArtworkCache()
        let resume = await partitionForResume(files: files, existing: existing, artworkCache: artworkCache)
        var processed = resume.completed
        var added = 0
        var failureMessage: String?
        await progress(processed, files.count)

        for start in stride(from: 0, to: resume.pending.count, by: commitBatchSize) {
            if Task.isCancelled { break }
            let end = min(start + commitBatchSize, resume.pending.count)
            let batch = Array(resume.pending[start..<end])
            let prepared = await prepare(
                batch,
                existing: existing,
                artworkCache: artworkCache
            ) { batchProgress in
                await progress(processed + batchProgress, files.count)
            }
            if prepared.isEmpty, Task.isCancelled { break }
            do {
                added += try await store.apply(prepared)
            } catch {
                // Earlier batches remain committed; the failed batch is isolated
                // in its own context and must not be reported as processed.
                failureMessage = "Could not save imported tracks: \(error.localizedDescription)"
                break
            }
            processed += prepared.count
        }

        if failureMessage == nil, processed > resume.completed {
            do {
                _ = try await AlbumRelationshipReconciler.reconcile(in: container)
            } catch {
                failureMessage = "Tracks were imported, but albums could not be organized: \(error.localizedDescription)"
            }
        }

        let result = LibraryImportResult(
            discovered: files.count,
            processed: processed,
            added: added,
            cancelled: Task.isCancelled,
            failureMessage: failureMessage
        )
        if automatic == false,
           result.cancelled == false,
           result.failureMessage == nil {
            exclusionStore.allow(paths: files.map(\.path))
        }
        return result
    }

    private static func partitionForResume(
        files: [URL],
        existing: [String: ExistingTrackSnapshot],
        artworkCache: FolderArtworkCache
    ) async -> (completed: Int, pending: [URL]) {
        await Task.detached(priority: .utility) {
            var completed = 0
            var pending: [URL] = []
            pending.reserveCapacity(files.count)
            for url in files {
                guard !Task.isCancelled else { break }
                guard let snapshot = existing[LibraryPathIdentity.key(url.path)] else {
                    pending.append(url)
                    continue
                }
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attributes?[.size] as? Int64) ?? 0
                let modified = (attributes?[.modificationDate] as? Date) ?? .distantPast
                if LibraryPathIdentity.hasSameScalarSpelling(
                    Track.standardizedPath(url.path),
                    snapshot.path
                ),
                   size == snapshot.fileSize,
                   abs(modified.timeIntervalSince(snapshot.dateModified)) < 1 {
                    if snapshot.needsArtwork, await artworkCache.artwork(for: url) != nil {
                        pending.append(url)
                    } else {
                        completed += 1
                    }
                } else {
                    pending.append(url)
                }
            }
            return (completed, pending)
        }.value
    }

    private static func prepare(
        _ urls: [URL],
        existing: [String: ExistingTrackSnapshot],
        artworkCache: FolderArtworkCache,
        progress: @escaping (Int) async -> Void
    ) async -> [PreparedImport] {
        await withTaskGroup(of: (Int, PreparedImport?).self) { group in
            var nextIndex = 0
            var results: [(Int, PreparedImport)] = []
            var completed = 0

            func submit(_ index: Int) {
                let url = urls[index]
                let snapshot = existing[LibraryPathIdentity.key(url.path)]
                group.addTask {
                    guard !Task.isCancelled else { return (index, nil) }
                    return (
                        index,
                        await prepareOne(
                            url,
                            existing: snapshot,
                            artworkCache: artworkCache
                        )
                    )
                }
            }

            while nextIndex < min(metadataConcurrency, urls.count) {
                submit(nextIndex)
                nextIndex += 1
            }
            while let result = await group.next() {
                if let record = result.1 {
                    results.append((result.0, record))
                    completed += 1
                    await progress(completed)
                }
                if nextIndex < urls.count, !Task.isCancelled {
                    submit(nextIndex)
                    nextIndex += 1
                }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func prepareOne(
        _ url: URL,
        existing: ExistingTrackSnapshot?,
        artworkCache: FolderArtworkCache
    ) async -> PreparedImport? {
        guard !Task.isCancelled else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? Int64) ?? 0
        let modified = (attributes?[.modificationDate] as? Date) ?? .distantPast

        if let existing {
            let unchanged = size == existing.fileSize
                && abs(modified.timeIntervalSince(existing.dateModified)) < 1
            if unchanged {
                return PreparedImport(
                    url: url, existingPath: existing.path,
                    fileSize: size, dateModified: modified,
                    metadata: nil,
                    folderArtwork: existing.needsArtwork
                        ? await artworkCache.artwork(for: url) : nil,
                    action: .skip
                )
            }
            if !unchanged, !existing.checksum.isEmpty {
                let checksum = Track.contentChecksum(at: url.path)
                if checksum == existing.checksum {
                    return PreparedImport(
                        url: url, existingPath: existing.path,
                        fileSize: size, dateModified: modified,
                        metadata: nil,
                        folderArtwork: existing.needsArtwork
                            ? await artworkCache.artwork(for: url) : nil,
                        action: .touch(checksum: checksum)
                    )
                }
                let metadata = normalized(await MetadataReader.read(from: url))
                let artwork = metadata?.artworkData == nil
                    ? await artworkCache.artwork(for: url)
                    : nil
                return PreparedImport(
                    url: url, existingPath: existing.path,
                    fileSize: size, dateModified: modified,
                    metadata: metadata, folderArtwork: artwork,
                    action: .refresh(checksum: checksum)
                )
            }

            let metadata = normalized(await MetadataReader.read(from: url))
            let artwork = metadata?.artworkData == nil
                ? await artworkCache.artwork(for: url)
                : nil
            let checksum = unchanged ? nil : Track.contentChecksum(at: url.path)
            return PreparedImport(
                url: url, existingPath: existing.path,
                fileSize: size, dateModified: modified,
                metadata: metadata, folderArtwork: artwork,
                action: .refresh(checksum: checksum)
            )
        }

        let metadata = normalized(await MetadataReader.read(from: url))
        let artwork = metadata?.artworkData == nil
            ? await artworkCache.artwork(for: url)
            : nil
        let checksum = Track.contentChecksum(at: url.path)
        return PreparedImport(
            url: url, existingPath: nil,
            fileSize: size, dateModified: modified,
            metadata: metadata, folderArtwork: artwork,
            action: .insert(checksum: checksum)
        )
    }

    private static func normalized(_ metadata: AudioMetadata?) -> AudioMetadata? {
        guard var metadata else { return nil }
        metadata.artworkData = metadata.artworkData.map(ArtworkStorage.normalized)
        return metadata
    }
}
