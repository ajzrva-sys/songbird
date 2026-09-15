import CryptoKit
import Foundation
import SwiftData

public enum LibraryHealthMutationError: Error, LocalizedError, Equatable, Sendable {
    case emptyPlan
    case duplicateTarget(UUID)
    case missingTarget(UUID)
    case unsupportedField(LibraryHealthField)
    case invalidValue(field: LibraryHealthField, value: String)
    case driftedTarget(trackID: UUID, expected: String, actual: String)
    case sourceRevisionDrift(expected: Int, actual: Int)
    case fileAvailabilityChanged(trackID: UUID)
    case relocationCandidateChanged(path: String)
    case pathCollision(String)
    case missingAlbum(UUID)
    case artworkChanged(UUID)
    case invalidArtwork
    case remoteEvidenceExpired
    case catalogRecordStillPresent(UUID)
    case currentlyPlaying(UUID)
    case crossDomainDrift(String)
    case duplicateContentChanged
    case persistence(String)
    case noUndoAvailable

    public var errorDescription: String? {
        switch self {
        case .emptyPlan:
            "No applicable Health suggestions were selected."
        case .duplicateTarget(let id):
            "The Health plan contains more than one change for track \(id.uuidString)."
        case .missingTarget(let id):
            "A track in the Health plan no longer exists: \(id.uuidString)."
        case .unsupportedField(let field):
            "Library Health cannot apply changes to \(field.rawValue)."
        case .invalidValue(let field, let value):
            "“\(value)” is not a valid value for \(field.rawValue)."
        case .driftedTarget(let id, let expected, let actual):
            "Track \(id.uuidString) changed from “\(expected)” to “\(actual)” after this plan was created."
        case .sourceRevisionDrift(let expected, let actual):
            "The library changed after this file check (revision \(expected) → \(actual)). Check again before relocating files."
        case .fileAvailabilityChanged(let id):
            "The original file state changed for track \(id.uuidString). Check again before relocating it."
        case .relocationCandidateChanged(let path):
            "The proposed replacement changed or disappeared: \(path)"
        case .pathCollision(let path):
            "Another library track already uses the proposed path: \(path)"
        case .missingAlbum(let id):
            "An album in the artwork review no longer exists: \(id.uuidString)."
        case .artworkChanged(let id):
            "Artwork for album \(id.uuidString) changed after this review was created."
        case .remoteEvidenceExpired:
            "Discogs results expired. Search again."
        case .invalidArtwork:
            "The selected file is not a supported image."
        case .catalogRecordStillPresent(let id):
            "Track \(id.uuidString) is still in the catalog, so this Undo cannot be applied."
        case .currentlyPlaying(let id):
            "Track \(id.uuidString) is currently being decoded and cannot be removed from the catalog."
        case .crossDomainDrift(let domain):
            "\(domain) changed after this Health operation. Undo refused without making partial changes."
        case .duplicateContentChanged:
            "The candidate files are no longer byte-identical. Analyze duplicates again."
        case .persistence(let message):
            message
        case .noUndoAvailable:
            "There is no Library Health change to undo."
        }
    }
}

public struct LibraryPathChange: Equatable, Sendable {
    public let trackID: UUID
    public let expectedOldPath: String
    public let candidatePath: String
    public let expectedCandidateChecksum: String
    public let sourceRevision: Int

    public init(
        trackID: UUID,
        expectedOldPath: String,
        candidatePath: String,
        expectedCandidateChecksum: String,
        sourceRevision: Int
    ) {
        self.trackID = trackID
        self.expectedOldPath = expectedOldPath
        self.candidatePath = candidatePath
        self.expectedCandidateChecksum = expectedCandidateChecksum
        self.sourceRevision = sourceRevision
    }
}

public struct LibraryArtworkChange: Equatable, Sendable {
    public let albumID: UUID
    public let expectedArtworkDigest: String?
    public let imageData: Data
    public let discogsEvidence: DiscogsContentEvidence?

    public init(albumID: UUID, expectedArtworkDigest: String?, imageData: Data, discogsEvidence: DiscogsContentEvidence? = nil) {
        self.albumID = albumID
        self.expectedArtworkDigest = expectedArtworkDigest
        self.imageData = imageData
        self.discogsEvidence = discogsEvidence
    }

    public static func digest(_ data: Data?) -> String? {
        guard let data else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct LibraryMissingRecordRemoval: Equatable, Sendable {
    public let trackID: UUID
    public let expectedPath: String
    public let sourceRevision: Int

    public init(trackID: UUID, expectedPath: String, sourceRevision: Int) {
        self.trackID = trackID
        self.expectedPath = expectedPath
        self.sourceRevision = sourceRevision
    }
}

public struct LibraryDuplicateConsolidation: Equatable, Sendable {
    public let trackIDs: [UUID]
    public let keeperID: UUID
    public let expectedChecksum: String

    public init(trackIDs: [UUID], keeperID: UUID, expectedChecksum: String) {
        self.trackIDs = trackIDs
        self.keeperID = keeperID
        self.expectedChecksum = expectedChecksum
    }
}

public struct LibraryHealthMutationOutcome: Equatable, Sendable {
    public let affectedTrackCount: Int
    public let affectedAlbumCount: Int

    public init(affectedTrackCount: Int, affectedAlbumCount: Int = 0) {
        self.affectedTrackCount = affectedTrackCount
        self.affectedAlbumCount = affectedAlbumCount
    }
}

struct LibraryTrackPathReceiptState: Equatable, Sendable {
    let trackID: UUID
    let path: String
    let checksum: String
    let fileSize: Int64
    let dateModified: Date
}

enum LibraryHealthMutationReceiptBody: Sendable {
    case metadata(reverseChanges: [LibraryRemediationChange])
    case relocations(before: [LibraryTrackPathReceiptState], after: [LibraryTrackPathReceiptState])
    case artwork(before: [LibraryAlbumArtworkReceiptState], after: [LibraryAlbumArtworkReceiptState])
    case catalogRemoval([LibraryRemovedTrackReceiptState])
    case duplicate(LibraryDuplicateReceiptState)
}

struct LibraryAlbumArtworkReceiptState: Equatable, Sendable {
    let albumID: UUID
    let artworkData: Data?
}

struct LibraryRemovedTrackPlaylistState: Equatable, Sendable {
    let playlistID: UUID
    let dateModified: Date
}

struct LibraryRemovedTrackReceiptState: Equatable, Sendable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let albumArtist: String
    let genre: String
    let composer: String
    let comment: String
    let year: Int
    let trackNumber: Int
    let trackTotal: Int
    let discNumber: Int
    let discTotal: Int
    let beatsPerMinute: Int
    let duration: TimeInterval
    let fileSize: Int64
    let path: String
    let dateAdded: Date
    let dateModified: Date
    let lastPlayed: Date?
    let playCount: Int
    let rating: Int
    let bitrate: Int
    let sampleRate: Int
    let artworkData: Data?
    let checksum: String
    let albumRelationID: UUID?
    let artistRelationID: UUID?
    let favoriteDate: Date?
    let playlists: [LibraryRemovedTrackPlaylistState]
}

struct LibraryPlaylistMembershipReceiptState: Equatable, Sendable {
    let playlistID: UUID
    let trackIDs: [UUID]
    let dateModified: Date
}

struct LibraryDuplicateReceiptState: Equatable, Sendable {
    let keeperBefore: LibraryRemovedTrackReceiptState
    let keeperAfter: LibraryRemovedTrackReceiptState
    let removed: [LibraryRemovedTrackReceiptState]
    let playlistsBefore: [LibraryPlaylistMembershipReceiptState]
    let playlistsAfter: [LibraryPlaylistMembershipReceiptState]
}

struct LibraryHealthCrossDomainReceipt: Equatable, Sendable {
    let queueBefore: PlaybackQueueIdentitySnapshot
    let queueAfter: PlaybackQueueIdentitySnapshot
    let playlistOrderBefore: [UUID: [UUID]]
    let playlistOrderAfter: [UUID: [UUID]]
    let exclusionsBefore: Set<String>
    let exclusionsAfter: Set<String>
}

struct LibraryHealthMutationReceipt: Sendable {
    let id: UUID
    let body: LibraryHealthMutationReceiptBody
    let crossDomain: LibraryHealthCrossDomainReceipt?

    init(
        id: UUID,
        body: LibraryHealthMutationReceiptBody,
        crossDomain: LibraryHealthCrossDomainReceipt? = nil
    ) {
        self.id = id
        self.body = body
        self.crossDomain = crossDomain
    }

    func withCrossDomain(_ value: LibraryHealthCrossDomainReceipt) -> Self {
        Self(id: id, body: body, crossDomain: value)
    }
}

@ModelActor
actor LibraryHealthMutationService {
    private let pathResolver = FilesystemPathResolver()

    func apply(
        _ plan: LibraryRemediationPlan
    ) throws -> (LibraryHealthMutationOutcome, LibraryHealthMutationReceipt) {
        try mutate(plan.changes, receiptID: UUID())
    }

    func undo(
        _ receipt: LibraryHealthMutationReceipt
    ) throws -> LibraryHealthMutationOutcome {
        switch receipt.body {
        case .metadata(let reverseChanges):
            try mutate(reverseChanges, receiptID: receipt.id).0
        case .relocations(let before, let after):
            try restoreRelocations(before: before, expectedAfter: after)
        case .artwork(let before, let after):
            try restoreArtwork(before: before, expectedAfter: after)
        case .catalogRemoval(let tracks):
            try restoreRemovedTracks(tracks)
        case .duplicate(let state):
            try restoreDuplicate(state)
        }
    }

    func consolidateDuplicateTracks(
        _ request: LibraryDuplicateConsolidation
    ) throws -> (LibraryHealthMutationOutcome, LibraryHealthMutationReceipt) {
        var seen = Set<UUID>()
        let ids = request.trackIDs.filter { seen.insert($0).inserted }
        guard ids.count > 1, ids.contains(request.keeperID), request.expectedChecksum.isEmpty == false else {
            throw LibraryHealthMutationError.emptyPlan
        }
        let allTracks = try modelContext.fetch(FetchDescriptor<Track>())
        let tracksByID = Dictionary(uniqueKeysWithValues: allTracks.map { ($0.id, $0) })
        let tracks = try ids.map { id -> Track in
            guard let track = tracksByID[id] else { throw LibraryHealthMutationError.missingTarget(id) }
            guard track.checksum == request.expectedChecksum else {
                throw LibraryHealthMutationError.driftedTarget(
                    trackID: id,
                    expected: request.expectedChecksum,
                    actual: track.checksum
                )
            }
            return track
        }
        let fullDigests = try tracks.map { track -> String in
            guard case .available(let url) = pathResolver.resolve(track.path) else {
                throw LibraryHealthMutationError.duplicateContentChanged
            }
            return try Self.fullFileDigest(url)
        }
        guard Set(fullDigests).count == 1 else {
            throw LibraryHealthMutationError.duplicateContentChanged
        }
        guard let keeper = tracks.first(where: { $0.id == request.keeperID }) else {
            throw LibraryHealthMutationError.missingTarget(request.keeperID)
        }
        let redundant = tracks.filter { $0.id != keeper.id }
        let redundantIDs = Set(redundant.map(\.id))
        let favorites = try modelContext.fetch(FetchDescriptor<TrackFavorite>())
        let favoriteByID = Dictionary(uniqueKeysWithValues: favorites.map { ($0.trackID, $0) })
        let playlists = try modelContext.fetch(FetchDescriptor<Playlist>())
        let affectedPlaylists = playlists.filter { playlist in
            playlist.smartPlaylist == false && playlist.tracks.contains { ids.contains($0.id) }
        }
        let playlistBefore = affectedPlaylists.map(Self.playlistState)
        let keeperBefore = Self.removedTrackState(keeper, favorite: favoriteByID[keeper.id], playlists: playlists)
        let removed = redundant.map {
            Self.removedTrackState($0, favorite: favoriteByID[$0.id], playlists: playlists)
        }
        do {
            let groupFavorites = favorites.filter { ids.contains($0.trackID) }
            for favorite in groupFavorites { modelContext.delete(favorite) }
            if let earliest = groupFavorites.map(\.dateAdded).min() {
                modelContext.insert(TrackFavorite(trackID: keeper.id, dateAdded: earliest))
            }
            keeper.rating = tracks.map(\.rating).max() ?? keeper.rating
            keeper.playCount = tracks.reduce(0) { partial, track in
                partial > Int.max - track.playCount ? Int.max : partial + track.playCount
            }
            keeper.dateAdded = tracks.map(\.dateAdded).min() ?? keeper.dateAdded
            keeper.dateModified = tracks.map(\.dateModified).max() ?? keeper.dateModified
            keeper.lastPlayed = tracks.compactMap(\.lastPlayed).max()
            for playlist in affectedPlaylists {
                var kept = Set<UUID>()
                playlist.tracks = playlist.tracks.map {
                    redundantIDs.contains($0.id) ? keeper : $0
                }.filter { kept.insert($0.id).inserted }
                playlist.dateModified = Date()
            }
            for track in redundant { modelContext.delete(track) }
            try Task.checkCancellation()
            try modelContext.save()
        } catch is CancellationError {
            modelContext.rollback()
            throw CancellationError()
        } catch {
            modelContext.rollback()
            throw LibraryHealthMutationError.persistence(error.localizedDescription)
        }
        let refreshedFavorites = try modelContext.fetch(FetchDescriptor<TrackFavorite>())
        let refreshedFavoriteByID = Dictionary(uniqueKeysWithValues: refreshedFavorites.map { ($0.trackID, $0) })
        let state = LibraryDuplicateReceiptState(
            keeperBefore: keeperBefore,
            keeperAfter: Self.removedTrackState(
                keeper,
                favorite: refreshedFavoriteByID[keeper.id],
                playlists: playlists
            ),
            removed: removed,
            playlistsBefore: playlistBefore,
            playlistsAfter: affectedPlaylists.map(Self.playlistState)
        )
        return (
            LibraryHealthMutationOutcome(affectedTrackCount: redundant.count),
            LibraryHealthMutationReceipt(id: UUID(), body: .duplicate(state))
        )
    }

    func removeMissingCatalogRecords(
        _ removals: [LibraryMissingRecordRemoval]
    ) throws -> (LibraryHealthMutationOutcome, LibraryHealthMutationReceipt) {
        guard removals.isEmpty == false else { throw LibraryHealthMutationError.emptyPlan }
        var byID: [UUID: LibraryMissingRecordRemoval] = [:]
        for removal in removals {
            guard byID.updateValue(removal, forKey: removal.trackID) == nil else {
                throw LibraryHealthMutationError.duplicateTarget(removal.trackID)
            }
        }
        let tracks = try modelContext.fetch(FetchDescriptor<Track>())
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let favorites = try modelContext.fetch(FetchDescriptor<TrackFavorite>())
        let favoriteByID = Dictionary(uniqueKeysWithValues: favorites.map { ($0.trackID, $0) })
        let playlists = try modelContext.fetch(FetchDescriptor<Playlist>())
        var states: [LibraryRemovedTrackReceiptState] = []
        for removal in byID.values.sorted(by: { $0.trackID.uuidString < $1.trackID.uuidString }) {
            guard let track = tracksByID[removal.trackID] else {
                throw LibraryHealthMutationError.missingTarget(removal.trackID)
            }
            guard track.path == Track.standardizedPath(removal.expectedPath),
                  case .missing = pathResolver.resolve(track.path) else {
                throw LibraryHealthMutationError.fileAvailabilityChanged(trackID: track.id)
            }
            states.append(Self.removedTrackState(
                track,
                favorite: favoriteByID[track.id],
                playlists: playlists
            ))
        }
        do {
            for state in states {
                if let favorite = favoriteByID[state.id] { modelContext.delete(favorite) }
                guard let track = tracksByID[state.id] else { continue }
                for playlist in playlists where playlist.tracks.contains(where: { $0.id == track.id }) {
                    playlist.tracks.removeAll { $0.id == track.id }
                }
                modelContext.delete(track)
            }
            try Task.checkCancellation()
            try modelContext.save()
        } catch is CancellationError {
            modelContext.rollback()
            throw CancellationError()
        } catch {
            modelContext.rollback()
            throw LibraryHealthMutationError.persistence(error.localizedDescription)
        }
        return (
            LibraryHealthMutationOutcome(affectedTrackCount: states.count),
            LibraryHealthMutationReceipt(id: UUID(), body: .catalogRemoval(states))
        )
    }

    func applyArtwork(
        _ changes: [LibraryArtworkChange],
        clock: @Sendable () -> DiscogsFetchStamp? = { DiscogsClock.sample() },
        normalize: @Sendable (Data) -> Data = { ArtworkStorage.normalized($0) }
    ) throws -> (LibraryHealthMutationOutcome, LibraryHealthMutationReceipt) {
        guard changes.isEmpty == false else { throw LibraryHealthMutationError.emptyPlan }
        try Task.checkCancellation()
        let evidence = changes.compactMap(\.discogsEvidence)
        try requireFreshDiscogsEvidence(evidence, clock: clock)
        var byID: [UUID: LibraryArtworkChange] = [:]
        for change in changes {
            guard byID.updateValue(change, forKey: change.albumID) == nil else {
                throw LibraryHealthMutationError.duplicateTarget(change.albumID)
            }
            guard ArtworkStorage.pixelSize(of: change.imageData) != nil else {
                throw LibraryHealthMutationError.invalidArtwork
            }
        }
        let albums = try modelContext.fetch(FetchDescriptor<Album>())
        let albumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
        var before: [LibraryAlbumArtworkReceiptState] = []
        var after: [LibraryAlbumArtworkReceiptState] = []
        for change in byID.values.sorted(by: { $0.albumID.uuidString < $1.albumID.uuidString }) {
            guard let album = albumsByID[change.albumID] else {
                throw LibraryHealthMutationError.missingAlbum(change.albumID)
            }
            guard LibraryArtworkChange.digest(album.artworkData) == change.expectedArtworkDigest else {
                throw LibraryHealthMutationError.artworkChanged(change.albumID)
            }
            try requireFreshDiscogsEvidence(evidence, clock: clock)
            let normalized = normalize(change.imageData)
            before.append(.init(albumID: album.id, artworkData: album.artworkData))
            after.append(.init(albumID: album.id, artworkData: normalized))
        }
        do {
            for state in after {
                try requireFreshDiscogsEvidence(evidence, clock: clock)
                albumsByID[state.albumID]?.artworkData = state.artworkData
            }
            try Task.checkCancellation()
            try requireFreshDiscogsEvidence(evidence, clock: clock)
            try modelContext.save()
        } catch is CancellationError {
            modelContext.rollback()
            throw CancellationError()
        } catch let error as LibraryHealthMutationError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw LibraryHealthMutationError.persistence(error.localizedDescription)
        }
        let trackCount = albums.filter { byID[$0.id] != nil }.reduce(0) { $0 + $1.tracks.count }
        return (
            LibraryHealthMutationOutcome(affectedTrackCount: trackCount, affectedAlbumCount: after.count),
            LibraryHealthMutationReceipt(id: UUID(), body: .artwork(before: before, after: after))
        )
    }

    func applyRelocations(
        _ changes: [LibraryPathChange]
    ) throws -> (LibraryHealthMutationOutcome, LibraryHealthMutationReceipt) {
        guard changes.isEmpty == false else { throw LibraryHealthMutationError.emptyPlan }
        try Task.checkCancellation()
        var changesByID: [UUID: LibraryPathChange] = [:]
        var candidatePaths = Set<String>()
        for change in changes {
            guard changesByID.updateValue(change, forKey: change.trackID) == nil else {
                throw LibraryHealthMutationError.duplicateTarget(change.trackID)
            }
            let candidate = Track.standardizedPath(change.candidatePath)
            guard candidatePaths.insert(candidate).inserted else {
                throw LibraryHealthMutationError.pathCollision(candidate)
            }
        }

        let tracks = try modelContext.fetch(FetchDescriptor<Track>())
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let targetIDs = Set(changesByID.keys)
        let occupiedPaths = Set(tracks.filter { targetIDs.contains($0.id) == false }.map { Track.standardizedPath($0.path) })
        var before: [LibraryTrackPathReceiptState] = []
        var prepared: [(track: Track, state: LibraryTrackPathReceiptState)] = []

        for change in changesByID.values.sorted(by: { $0.trackID.uuidString < $1.trackID.uuidString }) {
            guard let track = tracksByID[change.trackID] else {
                throw LibraryHealthMutationError.missingTarget(change.trackID)
            }
            guard track.path == Track.standardizedPath(change.expectedOldPath),
                  case .missing = pathResolver.resolve(track.path) else {
                throw LibraryHealthMutationError.fileAvailabilityChanged(trackID: track.id)
            }
            let candidate = Track.standardizedPath(change.candidatePath)
            guard occupiedPaths.contains(candidate) == false else {
                throw LibraryHealthMutationError.pathCollision(candidate)
            }
            guard case .available(let resolvedURL) = pathResolver.resolve(candidate),
                  Track.standardizedPath(resolvedURL.path) == candidate,
                  Track.contentChecksum(at: candidate) == change.expectedCandidateChecksum else {
                throw LibraryHealthMutationError.relocationCandidateChanged(path: candidate)
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: candidate)
            let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let modified = (attributes[.modificationDate] as? Date) ?? track.dateModified
            before.append(Self.pathState(track))
            prepared.append((track, LibraryTrackPathReceiptState(
                trackID: track.id,
                path: candidate,
                checksum: change.expectedCandidateChecksum,
                fileSize: fileSize,
                dateModified: modified
            )))
        }

        do {
            for (track, state) in prepared { Self.apply(state, to: track) }
            try Task.checkCancellation()
            try modelContext.save()
        } catch is CancellationError {
            modelContext.rollback()
            throw CancellationError()
        } catch {
            modelContext.rollback()
            throw LibraryHealthMutationError.persistence(error.localizedDescription)
        }
        let after = prepared.map(\.state)
        return (
            LibraryHealthMutationOutcome(affectedTrackCount: prepared.count),
            LibraryHealthMutationReceipt(
                id: UUID(),
                body: .relocations(before: before, after: after)
            )
        )
    }

    private func mutate(
        _ changes: [LibraryRemediationChange],
        receiptID: UUID
    ) throws -> (LibraryHealthMutationOutcome, LibraryHealthMutationReceipt) {
        guard !changes.isEmpty else { throw LibraryHealthMutationError.emptyPlan }
        try Task.checkCancellation()

        var changeByID: [UUID: LibraryRemediationChange] = [:]
        for change in changes {
            guard Self.mutableFields.contains(change.target.field) else {
                throw LibraryHealthMutationError.unsupportedField(change.target.field)
            }
            guard changeByID.updateValue(change, forKey: change.target.trackID) == nil else {
                throw LibraryHealthMutationError.duplicateTarget(change.target.trackID)
            }
        }
        let tracks = try modelContext.fetch(FetchDescriptor<Track>())
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })

        for change in changeByID.values {
            guard let track = tracksByID[change.target.trackID] else {
                throw LibraryHealthMutationError.missingTarget(change.target.trackID)
            }
            let actual = try currentValue(of: track, field: change.target.field)
            guard actual == change.expectedValue else {
                throw LibraryHealthMutationError.driftedTarget(
                    trackID: track.id,
                    expected: change.expectedValue,
                    actual: actual
                )
            }
        }

        do {
            for change in changeByID.values {
                guard let track = tracksByID[change.target.trackID] else { continue }
                try apply(change.proposedValue, field: change.target.field, to: track)
            }
            try Task.checkCancellation()

            // Resolve Artist relationships with one indexed fetch rather than one query per track.
            let artists = try modelContext.fetch(FetchDescriptor<Artist>())
            var artistsByName = Dictionary(
                artists.map { ($0.name, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for id in changeByID.keys {
                guard let track = tracksByID[id] else { continue }
                let name = track.artist.isEmpty ? "Unknown Artist" : track.artist
                let artist: Artist
                if let existing = artistsByName[name] {
                    artist = existing
                } else {
                    artist = Artist(name: name)
                    modelContext.insert(artist)
                    artistsByName[name] = artist
                }
                track.artistRelation = artist
            }

            _ = try AlbumRelationshipReconciler.reconcile(
                in: modelContext,
                affectedTrackIDs: Set(changeByID.keys)
            )
            try Task.checkCancellation()
            try modelContext.save()
        } catch let error as LibraryHealthMutationError {
            modelContext.rollback()
            throw error
        } catch is CancellationError {
            modelContext.rollback()
            throw CancellationError()
        } catch {
            modelContext.rollback()
            throw LibraryHealthMutationError.persistence(error.localizedDescription)
        }

        let reverse = changeByID.values.map {
            LibraryRemediationChange(
                target: $0.target,
                expectedValue: $0.proposedValue,
                proposedValue: $0.expectedValue
            )
        }.sorted { $0.target.trackID.uuidString < $1.target.trackID.uuidString }
        return (
            LibraryHealthMutationOutcome(affectedTrackCount: reverse.count),
            LibraryHealthMutationReceipt(id: receiptID, body: .metadata(reverseChanges: reverse))
        )
    }

    private func restoreRelocations(
        before: [LibraryTrackPathReceiptState],
        expectedAfter: [LibraryTrackPathReceiptState]
    ) throws -> LibraryHealthMutationOutcome {
        let tracks = try modelContext.fetch(FetchDescriptor<Track>())
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let beforeByID = Dictionary(uniqueKeysWithValues: before.map { ($0.trackID, $0) })
        for expected in expectedAfter {
            guard let track = tracksByID[expected.trackID] else {
                throw LibraryHealthMutationError.missingTarget(expected.trackID)
            }
            guard Self.pathState(track) == expected else {
                throw LibraryHealthMutationError.driftedTarget(
                    trackID: track.id,
                    expected: expected.path,
                    actual: track.path
                )
            }
        }
        do {
            for (id, state) in beforeByID {
                guard let track = tracksByID[id] else {
                    throw LibraryHealthMutationError.missingTarget(id)
                }
                Self.apply(state, to: track)
            }
            try Task.checkCancellation()
            try modelContext.save()
        } catch let error as LibraryHealthMutationError {
            modelContext.rollback()
            throw error
        } catch is CancellationError {
            modelContext.rollback()
            throw CancellationError()
        } catch {
            modelContext.rollback()
            throw LibraryHealthMutationError.persistence(error.localizedDescription)
        }
        return LibraryHealthMutationOutcome(affectedTrackCount: before.count)
    }

    private func restoreArtwork(
        before: [LibraryAlbumArtworkReceiptState],
        expectedAfter: [LibraryAlbumArtworkReceiptState]
    ) throws -> LibraryHealthMutationOutcome {
        let albums = try modelContext.fetch(FetchDescriptor<Album>())
        let byID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
        for state in expectedAfter {
            guard let album = byID[state.albumID] else {
                throw LibraryHealthMutationError.missingAlbum(state.albumID)
            }
            guard LibraryArtworkChange.digest(album.artworkData)
                    == LibraryArtworkChange.digest(state.artworkData) else {
                throw LibraryHealthMutationError.artworkChanged(state.albumID)
            }
        }
        do {
            for state in before { byID[state.albumID]?.artworkData = state.artworkData }
            try Task.checkCancellation()
            try modelContext.save()
        } catch is CancellationError {
            modelContext.rollback()
            throw CancellationError()
        } catch {
            modelContext.rollback()
            throw LibraryHealthMutationError.persistence(error.localizedDescription)
        }
        let trackCount = albums.filter { album in before.contains { $0.albumID == album.id } }
            .reduce(0) { $0 + $1.tracks.count }
        return LibraryHealthMutationOutcome(
            affectedTrackCount: trackCount,
            affectedAlbumCount: before.count
        )
    }

    private func restoreRemovedTracks(
        _ states: [LibraryRemovedTrackReceiptState]
    ) throws -> LibraryHealthMutationOutcome {
        let existingTracks = try modelContext.fetch(FetchDescriptor<Track>())
        let existingIDs = Set(existingTracks.map(\.id))
        for state in states where existingIDs.contains(state.id) {
            throw LibraryHealthMutationError.catalogRecordStillPresent(state.id)
        }
        let albums = try modelContext.fetch(FetchDescriptor<Album>())
        let albumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
        let artists = try modelContext.fetch(FetchDescriptor<Artist>())
        let artistsByID = Dictionary(uniqueKeysWithValues: artists.map { ($0.id, $0) })
        let playlists = try modelContext.fetch(FetchDescriptor<Playlist>())
        let playlistsByID = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0) })
        for state in states {
            if let id = state.albumRelationID, albumsByID[id] == nil {
                throw LibraryHealthMutationError.crossDomainDrift("Album relationships")
            }
            if let id = state.artistRelationID, artistsByID[id] == nil {
                throw LibraryHealthMutationError.crossDomainDrift("Artist relationships")
            }
            if state.playlists.contains(where: { playlistsByID[$0.playlistID] == nil }) {
                throw LibraryHealthMutationError.crossDomainDrift("Playlists")
            }
        }
        do {
            for state in states {
                let track = Track(path: state.path, title: state.title, artist: state.artist, album: state.album)
                Self.applyRemovedTrackState(state, to: track)
                track.albumRelation = state.albumRelationID.flatMap { albumsByID[$0] }
                track.artistRelation = state.artistRelationID.flatMap { artistsByID[$0] }
                modelContext.insert(track)
                if let favoriteDate = state.favoriteDate {
                    modelContext.insert(TrackFavorite(trackID: state.id, dateAdded: favoriteDate))
                }
                for membership in state.playlists {
                    guard let playlist = playlistsByID[membership.playlistID] else { continue }
                    playlist.tracks.append(track)
                    playlist.dateModified = membership.dateModified
                }
            }
            try Task.checkCancellation()
            try modelContext.save()
        } catch is CancellationError {
            modelContext.rollback()
            throw CancellationError()
        } catch {
            modelContext.rollback()
            throw LibraryHealthMutationError.persistence(error.localizedDescription)
        }
        return LibraryHealthMutationOutcome(affectedTrackCount: states.count)
    }

    private func restoreDuplicate(
        _ state: LibraryDuplicateReceiptState
    ) throws -> LibraryHealthMutationOutcome {
        let tracks = try modelContext.fetch(FetchDescriptor<Track>())
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        guard let keeper = tracksByID[state.keeperAfter.id] else {
            throw LibraryHealthMutationError.missingTarget(state.keeperAfter.id)
        }
        for removed in state.removed where tracksByID[removed.id] != nil {
            throw LibraryHealthMutationError.catalogRecordStillPresent(removed.id)
        }
        let favorites = try modelContext.fetch(FetchDescriptor<TrackFavorite>())
        let favoriteByID = Dictionary(uniqueKeysWithValues: favorites.map { ($0.trackID, $0) })
        let playlists = try modelContext.fetch(FetchDescriptor<Playlist>())
        let playlistsByID = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0) })
        guard Self.removedTrackState(
            keeper,
            favorite: favoriteByID[keeper.id],
            playlists: playlists
        ) == state.keeperAfter else {
            throw LibraryHealthMutationError.crossDomainDrift("The duplicate keeper")
        }
        for expected in state.playlistsAfter {
            guard let playlist = playlistsByID[expected.playlistID],
                  Self.playlistState(playlist) == expected else {
                throw LibraryHealthMutationError.crossDomainDrift("Playlist memberships")
            }
        }
        let albums = try modelContext.fetch(FetchDescriptor<Album>())
        let albumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
        let artists = try modelContext.fetch(FetchDescriptor<Artist>())
        let artistsByID = Dictionary(uniqueKeysWithValues: artists.map { ($0.id, $0) })
        let restoredStates = [state.keeperBefore] + state.removed
        for restored in restoredStates {
            if let id = restored.albumRelationID, albumsByID[id] == nil {
                throw LibraryHealthMutationError.crossDomainDrift("Album relationships")
            }
            if let id = restored.artistRelationID, artistsByID[id] == nil {
                throw LibraryHealthMutationError.crossDomainDrift("Artist relationships")
            }
        }
        do {
            for favorite in favorites where restoredStates.contains(where: { $0.id == favorite.trackID }) {
                modelContext.delete(favorite)
            }
            Self.applyRemovedTrackState(state.keeperBefore, to: keeper)
            keeper.albumRelation = state.keeperBefore.albumRelationID.flatMap { albumsByID[$0] }
            keeper.artistRelation = state.keeperBefore.artistRelationID.flatMap { artistsByID[$0] }
            var restoredByID = tracksByID
            restoredByID[keeper.id] = keeper
            for removed in state.removed {
                let track = Track(path: removed.path, title: removed.title, artist: removed.artist, album: removed.album)
                Self.applyRemovedTrackState(removed, to: track)
                track.albumRelation = removed.albumRelationID.flatMap { albumsByID[$0] }
                track.artistRelation = removed.artistRelationID.flatMap { artistsByID[$0] }
                modelContext.insert(track)
                restoredByID[track.id] = track
            }
            for restored in restoredStates {
                if let favoriteDate = restored.favoriteDate {
                    modelContext.insert(TrackFavorite(trackID: restored.id, dateAdded: favoriteDate))
                }
            }
            for before in state.playlistsBefore {
                guard let playlist = playlistsByID[before.playlistID] else {
                    throw LibraryHealthMutationError.crossDomainDrift("Playlists")
                }
                let members = try before.trackIDs.map { id -> Track in
                    guard let track = restoredByID[id] else {
                        throw LibraryHealthMutationError.missingTarget(id)
                    }
                    return track
                }
                playlist.tracks = members
                playlist.dateModified = before.dateModified
            }
            try Task.checkCancellation()
            try modelContext.save()
        } catch let error as LibraryHealthMutationError {
            modelContext.rollback()
            throw error
        } catch is CancellationError {
            modelContext.rollback()
            throw CancellationError()
        } catch {
            modelContext.rollback()
            throw LibraryHealthMutationError.persistence(error.localizedDescription)
        }
        return LibraryHealthMutationOutcome(affectedTrackCount: state.removed.count)
    }

    private static func playlistState(_ playlist: Playlist) -> LibraryPlaylistMembershipReceiptState {
        LibraryPlaylistMembershipReceiptState(
            playlistID: playlist.id,
            trackIDs: playlist.tracks.map(\.id),
            dateModified: playlist.dateModified
        )
    }

    private static func removedTrackState(
        _ track: Track,
        favorite: TrackFavorite?,
        playlists: [Playlist]
    ) -> LibraryRemovedTrackReceiptState {
        LibraryRemovedTrackReceiptState(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            albumArtist: track.albumArtist,
            genre: track.genre,
            composer: track.composer,
            comment: track.comment,
            year: track.year,
            trackNumber: track.trackNumber,
            trackTotal: track.trackTotal,
            discNumber: track.discNumber,
            discTotal: track.discTotal,
            beatsPerMinute: track.beatsPerMinute,
            duration: track.duration,
            fileSize: track.fileSize,
            path: track.path,
            dateAdded: track.dateAdded,
            dateModified: track.dateModified,
            lastPlayed: track.lastPlayed,
            playCount: track.playCount,
            rating: track.rating,
            bitrate: track.bitrate,
            sampleRate: track.sampleRate,
            artworkData: track.artworkData,
            checksum: track.checksum,
            albumRelationID: track.albumRelation?.id,
            artistRelationID: track.artistRelation?.id,
            favoriteDate: favorite?.dateAdded,
            playlists: playlists.filter { playlist in
                playlist.smartPlaylist == false && playlist.tracks.contains { $0.id == track.id }
            }.map { .init(playlistID: $0.id, dateModified: $0.dateModified) }
        )
    }

    private static func applyRemovedTrackState(
        _ state: LibraryRemovedTrackReceiptState,
        to track: Track
    ) {
        track.id = state.id
        track.albumArtist = state.albumArtist
        track.genre = state.genre
        track.composer = state.composer
        track.comment = state.comment
        track.year = state.year
        track.trackNumber = state.trackNumber
        track.trackTotal = state.trackTotal
        track.discNumber = state.discNumber
        track.discTotal = state.discTotal
        track.beatsPerMinute = state.beatsPerMinute
        track.duration = state.duration
        track.fileSize = state.fileSize
        track.dateAdded = state.dateAdded
        track.dateModified = state.dateModified
        track.lastPlayed = state.lastPlayed
        track.playCount = state.playCount
        track.rating = state.rating
        track.bitrate = state.bitrate
        track.sampleRate = state.sampleRate
        track.artworkData = state.artworkData
        track.checksum = state.checksum
    }

    private static func fullFileDigest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: 1024 * 1024), data.isEmpty == false else {
                break
            }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func pathState(_ track: Track) -> LibraryTrackPathReceiptState {
        LibraryTrackPathReceiptState(
            trackID: track.id,
            path: track.path,
            checksum: track.checksum,
            fileSize: track.fileSize,
            dateModified: track.dateModified
        )
    }

    private static func apply(_ state: LibraryTrackPathReceiptState, to track: Track) {
        track.path = state.path
        track.checksum = state.checksum
        track.fileSize = state.fileSize
        track.dateModified = state.dateModified
    }

    private static let mutableFields: Set<LibraryHealthField> = [
        .artist, .album, .albumArtist, .title, .genre, .year, .trackNumber, .comment,
    ]

    private func currentValue(of track: Track, field: LibraryHealthField) throws -> String {
        switch field {
        case .artist: track.artist
        case .album: track.album
        case .albumArtist: track.albumArtist
        case .title: track.title
        case .genre: track.genre
        case .year: String(track.year)
        case .trackNumber: String(track.trackNumber)
        case .comment: track.comment
        case .path, .albumArtwork, .catalogRecord:
            throw LibraryHealthMutationError.unsupportedField(field)
        }
    }

    private func apply(_ value: String, field: LibraryHealthField, to track: Track) throws {
        switch field {
        case .artist: track.artist = value
        case .album: track.album = value
        case .albumArtist: track.albumArtist = value
        case .title: track.title = value
        case .genre: track.genre = value
        case .year:
            guard let number = Int(value), number >= 0 else {
                throw LibraryHealthMutationError.invalidValue(field: field, value: value)
            }
            track.year = number
        case .trackNumber:
            guard let number = Int(value), number >= 0 else {
                throw LibraryHealthMutationError.invalidValue(field: field, value: value)
            }
            track.trackNumber = number
        case .comment: track.comment = value
        case .path, .albumArtwork, .catalogRecord:
            throw LibraryHealthMutationError.unsupportedField(field)
        }
    }
}
