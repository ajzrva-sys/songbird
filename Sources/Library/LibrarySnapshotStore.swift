import Combine
import Foundation
import OSLog
import SwiftData

public struct LibrarySnapshotChangeSet: Sendable {
    public var inserted: Set<PersistentIdentifier>
    public var updated: Set<PersistentIdentifier>
    public var deleted: Set<PersistentIdentifier>
    public var invalidatedAll: Bool
    public var isUnknown: Bool

    public init(
        inserted: Set<PersistentIdentifier> = [],
        updated: Set<PersistentIdentifier> = [],
        deleted: Set<PersistentIdentifier> = [],
        invalidatedAll: Bool = false,
        isUnknown: Bool = false
    ) {
        self.inserted = inserted
        self.updated = updated
        self.deleted = deleted
        self.invalidatedAll = invalidatedAll
        self.isUnknown = isUnknown
    }

    public var identifiers: Set<PersistentIdentifier> {
        inserted.union(updated).union(deleted)
    }

    public var count: Int { identifiers.count }

    mutating func formUnion(_ other: LibrarySnapshotChangeSet) {
        inserted.formUnion(other.inserted)
        updated.formUnion(other.updated)
        deleted.formUnion(other.deleted)
        invalidatedAll = invalidatedAll || other.invalidatedAll
        isUnknown = isUnknown || other.isUnknown
    }
}

public protocol LibrarySnapshotBuilding: Sendable {
    func buildSnapshot(revision: Int) async throws -> LibrarySnapshot
    func apply(
        changeSet: LibrarySnapshotChangeSet,
        to snapshot: LibrarySnapshot,
        revision: Int
    ) async throws -> LibrarySnapshot?
}

public extension LibrarySnapshotBuilding {
    func apply(
        changeSet: LibrarySnapshotChangeSet,
        to snapshot: LibrarySnapshot,
        revision: Int
    ) async throws -> LibrarySnapshot? {
        nil
    }
}

/// Create the ModelContext on a worker, even when the store is UI-owned.
/// A model actor created on the main thread otherwise inherits its main queue.
actor BackgroundLibrarySnapshotBuilder: LibrarySnapshotBuilding {
    private let worker: Task<any LibrarySnapshotBuilding, Never>

    init(modelContainer: ModelContainer) {
        worker = Task.detached {
            LibrarySnapshotModelActor(modelContainer: modelContainer)
        }
    }

    init(makeWorker: @escaping @Sendable () -> any LibrarySnapshotBuilding) {
        worker = Task.detached { makeWorker() }
    }

    func buildSnapshot(revision: Int) async throws -> LibrarySnapshot {
        try await worker.value.buildSnapshot(revision: revision)
    }

    func apply(changeSet: LibrarySnapshotChangeSet, to snapshot: LibrarySnapshot,
               revision: Int) async throws -> LibrarySnapshot? {
        try await worker.value.apply(changeSet: changeSet, to: snapshot, revision: revision)
    }
}

@ModelActor
public actor LibrarySnapshotModelActor: LibrarySnapshotBuilding {
    private struct TrackStructureKey: Equatable {
        let title: String
        let artist: String
        let album: String
        let albumArtist: String
        let year: Int
        let trackNumber: Int
        let discNumber: Int
        let path: String
        let dateAdded: Date
        let albumID: UUID?
    }

    private struct AlbumStructureKey: Equatable {
        let title: String
        let artist: String
        let year: Int
        let trackIDs: [UUID]
    }

    private struct AlbumPresentationKey: Equatable {
        let dateAdded: Date
        let artworkReference: ArtworkReference?
        let isFavorite: Bool
    }

    private static let signposter = OSSignposter(
        subsystem: "com.songbird.player",
        category: "LibrarySnapshot"
    )

    public func buildSnapshot(revision: Int) async throws -> LibrarySnapshot {
        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval("Snapshot rebuild", id: signpostID)
        defer { Self.signposter.endInterval("Snapshot rebuild", state) }

        var trackDescriptor = FetchDescriptor<Track>(
            sortBy: [SortDescriptor(\Track.dateAdded, order: .reverse)]
        )
        trackDescriptor.relationshipKeyPathsForPrefetching = [\Track.albumRelation]
        let tracks = try modelContext.fetch(trackDescriptor)
        try Task.checkCancellation()

        let albums = try modelContext.fetch(
            FetchDescriptor<Album>(sortBy: [SortDescriptor(\Album.title)])
        )
        try Task.checkCancellation()

        let playlists = try modelContext.fetch(
            FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\Playlist.dateCreated)])
        )
        try Task.checkCancellation()

        let favoriteAlbumIDs = Set(
            try modelContext.fetch(FetchDescriptor<AlbumFavorite>()).map(\.albumID)
        )
        try Task.checkCancellation()

        let lovedTrackIDs = Set(
            try modelContext.fetch(FetchDescriptor<TrackFavorite>()).map(\.trackID)
        )
        try Task.checkCancellation()

        var albumRatings: [UUID: Int] = [:]
        let albumsWithArtwork = Set(albums.compactMap { album in
            album.artworkData == nil ? nil : album.id
        })
        albumRatings.reserveCapacity(albums.count)
        for (index, track) in tracks.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            guard let albumID = track.albumRelation?.id else { continue }
            albumRatings[albumID] = max(albumRatings[albumID] ?? 0, track.rating)
        }

        return LibrarySnapshot(
            revision: revision,
            tracks: try tracks.enumerated().map { index, track in
                if index.isMultiple(of: 256) { try Task.checkCancellation() }
                return LibraryTrackSnapshot(
                    track: track,
                    albumRating: track.albumRelation.flatMap { albumRatings[$0.id] } ?? track.rating,
                    albumsWithArtwork: albumsWithArtwork,
                    lovedTrackIDs: lovedTrackIDs
                )
            },
            albums: albums.map { LibraryAlbumSnapshot(album: $0, favoriteAlbumIDs: favoriteAlbumIDs) },
            playlists: playlists.map(LibraryPlaylistSnapshot.init)
        )
    }

    public func apply(
        changeSet: LibrarySnapshotChangeSet,
        to snapshot: LibrarySnapshot,
        revision: Int
    ) async throws -> LibrarySnapshot? {
        let supported = Set(["Track", "Album", "Playlist", "AlbumFavorite", "TrackFavorite"])
        guard changeSet.invalidatedAll == false,
              changeSet.isUnknown == false,
              changeSet.count <= 256,
              changeSet.identifiers.allSatisfy({ supported.contains($0.entityName) }) else {
            return nil
        }

        // A fresh read context avoids publishing registered values retained by the
        // actor's long-lived context before the main-context save notification.
        let readContext = ModelContext(modelContainer)
        readContext.autosaveEnabled = false

        let favoriteAlbumIDs = Set(
            try readContext.fetch(FetchDescriptor<AlbumFavorite>()).map(\.albumID)
        )
        let lovedTrackIDs = Set(
            try readContext.fetch(FetchDescriptor<TrackFavorite>()).map(\.trackID)
        )
        try Task.checkCancellation()

        var albums = snapshot.albums
        var tracks = snapshot.tracks
        var playlists = snapshot.playlists
        var trackChanged = false
        var albumStructureChanged = false
        var albumPresentationChanged = false
        var playlistChanged = false
        var affectedAlbumIDs: Set<UUID> = []

        let deletedAlbums = changeSet.deleted.filter { $0.entityName == "Album" }
        for identifier in deletedAlbums {
            guard let id = snapshot.albumIDByPersistentIdentifier[identifier] else { continue }
            albums.removeAll { $0.id == id }
            affectedAlbumIDs.insert(id)
            albumStructureChanged = true
            albumPresentationChanged = true
        }

        let currentAlbumIdentifiers = changeSet.inserted.union(changeSet.updated).filter {
            $0.entityName == "Album" && changeSet.deleted.contains($0) == false
        }
        for identifier in currentAlbumIdentifiers {
            guard let album = readContext.model(for: identifier) as? Album else { return nil }
            let current = LibraryAlbumSnapshot(album: album, favoriteAlbumIDs: favoriteAlbumIDs)
            let old = snapshot.albumsByID[current.id]
            albumStructureChanged = albumStructureChanged
                || old.map(Self.albumStructureKey) != Self.albumStructureKey(current)
            albumPresentationChanged = albumPresentationChanged
                || old.map(Self.albumPresentationKey) != Self.albumPresentationKey(current)
            affectedAlbumIDs.insert(current.id)
            albums.removeAll { $0.id == current.id }
            albums.append(current)
        }

        let favoriteChanged = changeSet.identifiers.contains { $0.entityName == "AlbumFavorite" }
        if favoriteChanged {
            albums = albums.map { album in
                let updated = album.withFavorite(favoriteAlbumIDs.contains(album.id))
                if updated.isFavorite != album.isFavorite { albumPresentationChanged = true }
                return updated
            }
        }
        albums.sort {
            let comparison = $0.title.localizedCaseInsensitiveCompare($1.title)
            return comparison == .orderedSame ? $0.id.uuidString < $1.id.uuidString : comparison == .orderedAscending
        }

        let deletedTracks = changeSet.deleted.filter { $0.entityName == "Track" }
        for identifier in deletedTracks {
            guard let id = snapshot.trackIDByPersistentIdentifier[identifier],
                  let old = snapshot.tracksByID[id] else { continue }
            affectedAlbumIDs.formUnion([old.albumID].compactMap { $0 })
            tracks.removeAll { $0.id == id }
            trackChanged = true
            albumStructureChanged = true
        }

        let albumsWithArtwork = Set(albums.compactMap { album in
            album.artworkReference == nil ? nil : album.id
        })
        let currentTrackIdentifiers = changeSet.inserted.union(changeSet.updated).filter {
            $0.entityName == "Track" && changeSet.deleted.contains($0) == false
        }
        for identifier in currentTrackIdentifiers {
            guard let track = readContext.model(for: identifier) as? Track else { return nil }
            let old = snapshot.tracksByID[track.id]
            let current = LibraryTrackSnapshot(
                track: track,
                albumRating: track.rating,
                albumsWithArtwork: albumsWithArtwork,
                lovedTrackIDs: lovedTrackIDs
            )
            affectedAlbumIDs.formUnion([old?.albumID, current.albumID].compactMap { $0 })
            albumStructureChanged = albumStructureChanged
                || old.map(Self.trackStructureKey) != Self.trackStructureKey(current)
            tracks.removeAll { $0.id == current.id }
            tracks.append(current)
            trackChanged = true
        }

        let loveChanged = changeSet.identifiers.contains { $0.entityName == "TrackFavorite" }
        if loveChanged {
            tracks = tracks.map { track in
                let updated = track.withLoved(lovedTrackIDs.contains(track.id))
                if updated.isLoved != track.isLoved { trackChanged = true }
                return updated
            }
        }

        if affectedAlbumIDs.isEmpty == false {
            var ratings: [UUID: Int] = [:]
            for track in tracks where track.albumID.map(affectedAlbumIDs.contains) == true {
                guard let albumID = track.albumID else { continue }
                ratings[albumID] = max(ratings[albumID] ?? 0, track.rating)
            }
            let albumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
            tracks = tracks.map { track in
                guard let albumID = track.albumID, affectedAlbumIDs.contains(albumID) else {
                    return track
                }
                let rating = ratings[albumID] ?? track.rating
                let artwork = albumsByID[albumID]?.artworkReference
                return track.withAlbumRating(rating).withArtworkReference(artwork)
            }
            trackChanged = true
        }
        tracks.sort {
            $0.dateAdded == $1.dateAdded
                ? $0.id.uuidString < $1.id.uuidString
                : $0.dateAdded > $1.dateAdded
        }
        if affectedAlbumIDs.isEmpty == false {
            let trackIDsByAlbum = Dictionary(grouping: tracks.compactMap { track in
                track.albumID.map { ($0, track.id) }
            }, by: { $0.0 }).mapValues { $0.map(\.1) }
            albums = albums.map { album in
                guard affectedAlbumIDs.contains(album.id) else { return album }
                let updated = album.withTrackIDs(trackIDsByAlbum[album.id] ?? [])
                if updated.trackIDs != album.trackIDs { albumStructureChanged = true }
                return updated
            }
        }

        let deletedPlaylists = changeSet.deleted.filter { $0.entityName == "Playlist" }
        for identifier in deletedPlaylists {
            guard let id = snapshot.playlistIDByPersistentIdentifier[identifier] else { continue }
            playlists.removeAll { $0.id == id }
            playlistChanged = true
        }
        let currentPlaylistIdentifiers = changeSet.inserted.union(changeSet.updated).filter {
            $0.entityName == "Playlist" && changeSet.deleted.contains($0) == false
        }
        for identifier in currentPlaylistIdentifiers {
            guard let playlist = readContext.model(for: identifier) as? Playlist else { return nil }
            let current = LibraryPlaylistSnapshot(playlist: playlist)
            playlists.removeAll { $0.id == current.id }
            playlists.append(current)
            playlistChanged = true
        }
        playlists.sort {
            $0.dateCreated == $1.dateCreated
                ? $0.id.uuidString < $1.id.uuidString
                : $0.dateCreated < $1.dateCreated
        }

        return LibrarySnapshot(
            revision: revision,
            trackRevision: trackChanged ? revision : snapshot.trackRevision,
            albumStructureRevision: albumStructureChanged ? revision : snapshot.albumStructureRevision,
            albumPresentationRevision: albumPresentationChanged ? revision : snapshot.albumPresentationRevision,
            playlistRevision: playlistChanged ? revision : snapshot.playlistRevision,
            tracks: tracks,
            albums: albums,
            playlists: playlists
        )
    }

    private nonisolated static func trackStructureKey(
        _ track: LibraryTrackSnapshot
    ) -> TrackStructureKey {
        TrackStructureKey(
            title: track.title,
            artist: track.artist,
            album: track.album,
            albumArtist: track.albumArtist,
            year: track.year,
            trackNumber: track.trackNumber,
            discNumber: track.discNumber,
            path: track.path,
            dateAdded: track.dateAdded,
            albumID: track.albumID
        )
    }

    private nonisolated static func albumStructureKey(
        _ album: LibraryAlbumSnapshot
    ) -> AlbumStructureKey {
        AlbumStructureKey(
            title: album.title,
            artist: album.artist,
            year: album.year,
            trackIDs: album.trackIDs
        )
    }

    private nonisolated static func albumPresentationKey(
        _ album: LibraryAlbumSnapshot
    ) -> AlbumPresentationKey {
        AlbumPresentationKey(
            dateAdded: album.dateAdded,
            artworkReference: album.artworkReference,
            isFavorite: album.isFavorite
        )
    }
}

/// Publishes value-only catalog snapshots and is the sole invalidation bridge from SwiftData saves.
@MainActor
public final class LibrarySnapshotStore: ObservableObject {
    public private(set) static weak var active: LibrarySnapshotStore?
    @Published public private(set) var snapshot: LibrarySnapshot = .empty
    @Published public private(set) var rebuildError: String?

    public let modelContainer: ModelContainer
    private let worker: any LibrarySnapshotBuilding
    private let artworkService: ArtworkThumbnailService?
    private let relevantEntities: Set<String>
    private var storeIdentifiers: Set<String> = []
    private var observers: [NSObjectProtocol] = []
    private var rebuildTask: Task<Void, Never>?
    private var mutationRefreshTask: Task<Void, Never>?
    private var artworkInvalidationTask: Task<Void, Never>?
    private var rebuildingRevision: Int?
    private var observedSaveGeneration = 0
    private var mutationRefreshSaveGeneration = 0
    private var requestedRevision = 0
    private var bulkUpdateDepth = 0
    private var pendingChangeSet: LibrarySnapshotChangeSet?
    private var lastPublication = ContinuousClock.now - .seconds(1)

    var refreshRequestCount: Int { requestedRevision }
    private(set) var fullRebuildCount = 0
    private(set) var patchPublicationCount = 0

    public init(
        modelContainer: ModelContainer,
        startsImmediately: Bool = true,
        snapshotBuilder: (any LibrarySnapshotBuilding)? = nil,
        artworkService: ArtworkThumbnailService? = nil
    ) {
        self.modelContainer = modelContainer
        self.artworkService = artworkService
        worker = snapshotBuilder ?? BackgroundLibrarySnapshotBuilder(modelContainer: modelContainer)
        // SwiftData exposes Schema.entityName(for:) only on macOS 15. The schema
        // names for these non-inherited models are stable on the macOS 14 target.
        relevantEntities = ["Track", "Album", "Playlist", "AlbumFavorite", "TrackFavorite"]
        Self.active = self
        observeSaves()
        if startsImmediately {
            scheduleRefresh(immediate: true, forceFullRebuild: true)
        }
    }

    isolated deinit {
        rebuildTask?.cancel()
        mutationRefreshTask?.cancel()
        artworkInvalidationTask?.cancel()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func refresh() async {
        rebuildTask?.cancel()
        rebuildTask = nil
        requestedRevision += 1
        let revision = requestedRevision
        await rebuild(revision: revision, forceFullRebuild: true)
    }

    /// Flushes categorized saves through the bounded patch path. Missing save
    /// evidence and bulk/unknown changes retain the correctness-first full read.
    public func refreshAfterMutation() async {
        if let mutationRefreshTask {
            await mutationRefreshTask.value
            return
        }
        let task = Task<Void, Never> { [weak self] in
            await self?.flushMutationChanges()
            await self?.artworkInvalidationTask?.value
        }
        mutationRefreshTask = task
        await task.value
        mutationRefreshTask = nil
    }

    private func flushMutationChanges() async {
        // Join work already reading, rather than cancel and repeat that read.
        if rebuildingRevision != nil { await rebuildTask?.value }
        if pendingChangeSet == nil, rebuildError == nil, snapshot.revision > 0,
           observedSaveGeneration > mutationRefreshSaveGeneration {
            mutationRefreshSaveGeneration = observedSaveGeneration
            return
        }
        if pendingChangeSet == nil {
            // An external save can leave artwork identity unchanged too. With no
            // identifier evidence, the full catalog read alone cannot refresh it.
            invalidateArtwork(for: LibrarySnapshotChangeSet(isUnknown: true))
        }
        scheduleRefresh(
            immediate: true,
            forceFullRebuild: bulkUpdateDepth > 0 || pendingChangeSet == nil
        )
        // Saves arriving during this read can supersede it. Wait for their
        // coalesced successor too, without starting another catalog rebuild.
        while let task = rebuildTask {
            let revision = requestedRevision
            await task.value
            if revision == requestedRevision { break }
        }
        if pendingChangeSet == nil, rebuildError == nil {
            mutationRefreshSaveGeneration = observedSaveGeneration
        }
    }

    /// Coalesces intermediate import/maintenance saves to at most two catalog publications per second.
    public func beginBulkUpdates() {
        bulkUpdateDepth += 1
    }

    /// Always schedules an unconditional final catalog rebuild.
    public func endBulkUpdates() {
        bulkUpdateDepth = max(0, bulkUpdateDepth - 1)
        if bulkUpdateDepth == 0 {
            scheduleRefresh(immediate: true, forceFullRebuild: true)
        }
    }

    public func trackSnapshot(id: UUID) -> LibraryTrackSnapshot? {
        snapshot.tracksByID[id]
    }

    public func resolveTrack(id: UUID) -> Track? {
        guard snapshot.tracksByID[id] != nil else { return nil }
        var descriptor = FetchDescriptor<Track>(
            predicate: #Predicate { track in track.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContainer.mainContext.fetch(descriptor).first
    }

    public func resolveTracks(ids: some Sequence<UUID>) -> [Track] {
        let requestedIDs = Array(ids)
        guard !requestedIDs.isEmpty else { return [] }
        let fetchIDs = Array(Set(requestedIDs).filter { snapshot.tracksByID[$0] != nil })
        guard !fetchIDs.isEmpty else { return [] }

        let descriptor = FetchDescriptor<Track>(
            predicate: #Predicate { track in fetchIDs.contains(track.id) }
        )
        guard let tracks = try? modelContainer.mainContext.fetch(descriptor) else { return [] }
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return requestedIDs.compactMap { tracksByID[$0] }
    }

    /// Optimistically update track ratings in the local snapshot without a full rebuild.
    /// The next scheduled rebuild will reconcile with the persisted state.
    public func updateTrackRatings(_ ratings: [UUID: Int]) {
        guard ratings.isEmpty == false else { return }
        var updatedTracks = snapshot.tracks
        let affectedAlbumIDs = Set(ratings.keys.compactMap { snapshot.tracksByID[$0]?.albumID })
        for (index, track) in updatedTracks.enumerated() {
            if let newRating = ratings[track.id] {
                updatedTracks[index] = track.withRating(newRating)
            }
        }
        var albumRatings: [UUID: Int] = [:]
        for track in updatedTracks where track.albumID.map(affectedAlbumIDs.contains) == true {
            guard let albumID = track.albumID else { continue }
            albumRatings[albumID] = max(albumRatings[albumID] ?? 0, track.rating)
        }
        updatedTracks = updatedTracks.map { track in
            guard let albumID = track.albumID,
                  let albumRating = albumRatings[albumID] else { return track }
            return track.withAlbumRating(albumRating)
        }
        requestedRevision += 1
        let revision = requestedRevision
        snapshot = LibrarySnapshot(
            revision: revision,
            trackRevision: revision,
            albumStructureRevision: snapshot.albumStructureRevision,
            albumPresentationRevision: snapshot.albumPresentationRevision,
            playlistRevision: snapshot.playlistRevision,
            tracks: updatedTracks,
            albums: snapshot.albums,
            playlists: snapshot.playlists
        )
    }

    public func resolveAlbum(id: UUID) -> Album? {
        guard snapshot.albumsByID[id] != nil else { return nil }
        var descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { album in album.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContainer.mainContext.fetch(descriptor).first
    }

    public func resolvePlaylist(id: UUID) -> Playlist? {
        guard snapshot.playlistsByID[id] != nil else { return nil }
        var descriptor = FetchDescriptor<Playlist>(
            predicate: #Predicate { playlist in playlist.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContainer.mainContext.fetch(descriptor).first
    }

    private func observeSaves() {
        let observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let savingContext = notification.object as? ModelContext,
                      savingContext.container === self.modelContainer else {
                    return
                }
                let changeSet = Self.changeSet(in: notification)
                self.handleSave(changeSet: changeSet)
            }
        }
        observers.append(observer)
    }

    private func handleSave(changeSet: LibrarySnapshotChangeSet) {
        let relevant = filtered(changeSet)
        guard relevant.isUnknown || relevant.invalidatedAll || relevant.identifiers.isEmpty == false else {
            return
        }
        observedSaveGeneration += 1
        invalidateArtwork(for: relevant)
        if pendingChangeSet == nil {
            pendingChangeSet = relevant
        } else {
            pendingChangeSet?.formUnion(relevant)
        }
        scheduleRefresh(immediate: false)
    }

    private func invalidateArtwork(for changeSet: LibrarySnapshotChangeSet) {
        guard let artworkService else { return }
        let albumIDs = Set(changeSet.identifiers.compactMap {
            snapshot.albumIDByPersistentIdentifier[$0]
        })
        let allAlbums = changeSet.isUnknown || changeSet.invalidatedAll
        guard allAlbums || albumIDs.isEmpty == false else { return }
        let event = ArtworkInvalidation(albumIDs: allAlbums ? nil : albumIDs)
        let previous = artworkInvalidationTask
        artworkInvalidationTask = Task {
            await previous?.value
            if allAlbums {
                await artworkService.invalidateAll()
            } else {
                await artworkService.invalidate(albumIDs: albumIDs)
            }
            guard Task.isCancelled == false else { return }
            // Consumers must never race their reload ahead of cache invalidation.
            event.post()
        }
    }

    private func isRelevant(_ identifier: PersistentIdentifier) -> Bool {
        guard relevantEntities.contains(identifier.entityName) else { return false }
        guard let storeIdentifier = identifier.storeIdentifier else { return true }
        return storeIdentifiers.isEmpty || storeIdentifiers.contains(storeIdentifier)
    }

    private func filtered(_ changeSet: LibrarySnapshotChangeSet) -> LibrarySnapshotChangeSet {
        LibrarySnapshotChangeSet(
            inserted: Set(changeSet.inserted.filter(isRelevant(_:))),
            updated: Set(changeSet.updated.filter(isRelevant(_:))),
            deleted: Set(changeSet.deleted.filter(isRelevant(_:))),
            invalidatedAll: changeSet.invalidatedAll,
            isUnknown: changeSet.isUnknown
        )
    }

    private nonisolated static func changeSet(
        in notification: Notification
    ) -> LibrarySnapshotChangeSet {
        func identifiers(for key: ModelContext.NotificationKey) -> Set<PersistentIdentifier> {
            if let values = notification.userInfo?[key.rawValue] as? [PersistentIdentifier] {
                return Set(values)
            } else if let values = notification.userInfo?[key.rawValue] as? Set<PersistentIdentifier> {
                return values
            }
            return []
        }
        let inserted = identifiers(for: .insertedIdentifiers)
        let updated = identifiers(for: .updatedIdentifiers)
        let deleted = identifiers(for: .deletedIdentifiers)
        let invalidated = identifiers(for: .invalidatedAllIdentifiers)
        let hasKnownKeys = [
            ModelContext.NotificationKey.insertedIdentifiers,
            .updatedIdentifiers,
            .deletedIdentifiers,
            .invalidatedAllIdentifiers,
        ].contains { notification.userInfo?[$0.rawValue] != nil }
        return LibrarySnapshotChangeSet(
            inserted: inserted,
            updated: updated,
            deleted: deleted,
            invalidatedAll: invalidated.isEmpty == false,
            isUnknown: hasKnownKeys == false
        )
    }

    private func scheduleRefresh(immediate: Bool, forceFullRebuild: Bool = false) {
        requestedRevision += 1
        let revision = requestedRevision
        rebuildTask?.cancel()
        let isBulk = bulkUpdateDepth > 0
        let elapsed = lastPublication.duration(to: .now)
        let delay: Duration
        if immediate {
            delay = .zero
        } else if isBulk {
            delay = max(.zero, .milliseconds(500) - elapsed)
        } else {
            delay = .milliseconds(100)
        }

        rebuildTask = Task { [weak self] in
            do {
                if delay > .zero { try await Task.sleep(for: delay) }
                guard let self else { return }
                await self.rebuild(
                    revision: revision,
                    forceFullRebuild: forceFullRebuild || isBulk
                )
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func rebuild(revision: Int, forceFullRebuild: Bool = false) async {
        rebuildingRevision = revision
        defer {
            if rebuildingRevision == revision { rebuildingRevision = nil }
        }
        do {
            let rebuilt: LibrarySnapshot
            if forceFullRebuild == false,
               snapshot.revision > 0,
               let changeSet = pendingChangeSet,
               changeSet.count <= 256,
               changeSet.invalidatedAll == false,
               changeSet.isUnknown == false {
                do {
                    if let patched = try await worker.apply(
                        changeSet: changeSet,
                        to: snapshot,
                        revision: revision
                    ) {
                        rebuilt = patched
                        patchPublicationCount += 1
                    } else {
                        rebuilt = try await worker.buildSnapshot(revision: revision)
                        fullRebuildCount += 1
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    rebuilt = try await worker.buildSnapshot(revision: revision)
                    fullRebuildCount += 1
                }
            } else {
                rebuilt = try await worker.buildSnapshot(revision: revision)
                fullRebuildCount += 1
            }
            try Task.checkCancellation()
            guard revision == requestedRevision else { return }
            snapshot = rebuilt
            pendingChangeSet = nil
            storeIdentifiers = Set(
                rebuilt.tracks.compactMap(\.persistentIdentifier.storeIdentifier)
                    + rebuilt.albums.compactMap(\.persistentIdentifier.storeIdentifier)
                    + rebuilt.playlists.compactMap(\.persistentIdentifier.storeIdentifier)
            )
            rebuildError = nil
            lastPublication = .now
        } catch is CancellationError {
            return
        } catch {
            guard revision == requestedRevision else { return }
            // Keep the last known-good catalog visible.
            rebuildError = error.localizedDescription
        }
    }
}
