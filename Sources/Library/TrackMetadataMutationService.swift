import Foundation
import SwiftData

@ModelActor
actor TrackMetadataMutationService {
    func captureArtworkScope(
        groups: [LibraryAlbumGroupSnapshot], snapshot: LibrarySnapshot
    ) throws -> TrackArtworkScope {
        let groupByTrackID = Dictionary(
            groups.flatMap { group in group.trackIDs.map { ($0, group.id) } },
            uniquingKeysWith: { first, _ in first }
        )
        let ids = Array(groupByTrackID.keys)
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let tracks = try context.fetch(FetchDescriptor<Track>(predicate: #Predicate { ids.contains($0.id) }))
        guard tracks.count == ids.count else { throw TrackMetadataMutationError.artworkScopeChanged }
        let targets = try tracks.map { track in
            guard let expected = snapshot.tracksByID[track.id], let groupID = groupByTrackID[track.id],
                  expected.albumID == track.albumRelation?.id,
                  expected.path == track.path, expected.album == track.album,
                  expected.albumArtist == track.albumArtist, expected.artist == track.artist else {
                throw TrackMetadataMutationError.artworkScopeChanged
            }
            return TrackArtworkTarget(
                trackID: track.id, albumID: track.albumRelation?.id,
                groupID: groupID, title: track.title,
                identity: AlbumRelationshipReconciler.physicalIdentity(for: track),
                artworkData: track.resolvedArtworkData
            )
        }.sorted { $0.trackID.uuidString < $1.trackID.uuidString }
        return TrackArtworkScope(targets: targets, sourceStructureRevision: snapshot.albumStructureRevision)
    }

    func apply(
        _ changeSet: TrackMetadataChangeSet,
        decisions: [TrackMetadataConflictDecision]
    ) throws -> TrackMetadataApplyOutcome {
        try applyWithReceipt(changeSet, decisions: decisions).outcome
    }

    func applyWithReceipt(
        _ changeSet: TrackMetadataChangeSet,
        decisions: [TrackMetadataConflictDecision]
    ) throws -> TrackMetadataMutationResult {
        guard changeSet.baselines.isEmpty == false else {
            throw TrackMetadataMutationError.emptySelection
        }
        try Task.checkCancellation()

        var baselineByID: [UUID: TrackMetadataBaseline] = [:]
        for baseline in changeSet.baselines {
            guard baselineByID.updateValue(baseline, forKey: baseline.trackID) == nil else {
                throw TrackMetadataMutationError.duplicateTarget(baseline.trackID)
            }
        }
        let artworkTargets = changeSet.edits[.artwork] == nil ? [] : changeSet.artworkScope?.targets ?? []
        let artworkTargetIDs = artworkTargets.isEmpty
            ? Array(baselineByID.keys) : artworkTargets.map(\.trackID)
        guard Set(artworkTargetIDs).count == artworkTargetIDs.count else {
            throw TrackMetadataMutationError.artworkScopeChanged
        }
        let targetIDs = Array(Set(baselineByID.keys).union(artworkTargets.map(\.trackID)))
        let modelContext = ModelContext(modelContainer)
        modelContext.autosaveEnabled = false
        let tracks = try modelContext.fetch(FetchDescriptor<Track>(
            predicate: #Predicate { track in targetIDs.contains(track.id) }
        ))
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        for id in targetIDs where tracksByID[id] == nil {
            throw TrackMetadataMutationError.missingTarget(id)
        }
        for target in artworkTargets {
            guard let track = tracksByID[target.trackID], track.albumRelation?.id == target.albumID,
                  AlbumRelationshipReconciler.physicalIdentity(for: track) == target.identity else {
                throw TrackMetadataMutationError.artworkScopeChanged
            }
        }

        let favoriteRecords = try modelContext.fetch(FetchDescriptor<TrackFavorite>())
        let favoriteIDs = Set(favoriteRecords.map(\.trackID))
        let currentValues = Dictionary(uniqueKeysWithValues: tracks.map { track in
            (track.id, Self.values(for: track, isFavorite: favoriteIDs.contains(track.id)))
        })
        let conflicts = changeSet.conflicts(currentValues: currentValues)

        var decisionByID: [String: TrackMetadataConflictDecision] = [:]
        for decision in decisions {
            guard decisionByID.updateValue(decision, forKey: decision.id) == nil else {
                throw TrackMetadataMutationError.invalidDecision(decision.id)
            }
        }
        var unresolved = conflicts.filter { conflict in
            guard let decision = decisionByID[conflict.id] else { return true }
            return decision.expectedCurrent != conflict.current
        }
        for decision in decisions {
            guard let opening = changeSet.openingValue(trackID: decision.trackID, field: decision.field),
                  let current = currentValues[decision.trackID]?[decision.field],
                  let proposed = changeSet.edits[decision.field] else {
                throw TrackMetadataMutationError.invalidDecision(decision.id)
            }
            if current != decision.expectedCurrent,
               unresolved.contains(where: { $0.id == decision.id }) == false {
                unresolved.append(TrackMetadataConflict(
                    trackID: decision.trackID,
                    field: decision.field,
                    opening: opening,
                    current: current,
                    proposed: proposed
                ))
            }
        }
        guard unresolved.isEmpty else {
            return TrackMetadataMutationResult(
                outcome: .conflicts(unresolved.sorted { $0.id < $1.id }), fileWrites: []
            )
        }

        try validateArtworkDecisions(
            tracks: tracks,
            conflicts: conflicts,
            decisions: decisionByID
        )
        try Task.checkCancellation()

        let favoriteByID = Dictionary(
            favoriteRecords.map { ($0.trackID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var relationshipTrackIDs = Set<UUID>()
        var changedTrackIDs = Set<UUID>()
        var pendingArtwork: [(trackID: UUID, data: Data?)] = []
        var appliedFields: [UUID: [TrackMetadataField: TrackMetadataValue]] = [:]

        do {
            for baseline in changeSet.baselines {
                guard let track = tracksByID[baseline.trackID] else {
                    throw TrackMetadataMutationError.missingTarget(baseline.trackID)
                }
                for field in changeSet.edits.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                    guard let proposed = changeSet.edits[field] else { continue }
                    let conflictID = "\(track.id.uuidString)|\(field.rawValue)"
                    if decisionByID[conflictID]?.resolution == .useCurrent {
                        continue
                    }
                    guard currentValues[track.id]?[field] != proposed else { continue }
                    if field == .artwork { continue }
                    try apply(proposed, field: field, to: track, favoriteByID: favoriteByID, in: modelContext)
                    appliedFields[track.id, default: [:]][field] = proposed
                    if Self.relationshipFields.contains(field) {
                        relationshipTrackIDs.insert(track.id)
                    }
                    changedTrackIDs.insert(track.id)
                }
            }

            for id in relationshipTrackIDs {
                guard let track = tracksByID[id] else { continue }
                try linkRelations(for: track, in: modelContext)
            }
            if relationshipTrackIDs.isEmpty == false {
                _ = try AlbumRelationshipReconciler.reconcile(
                    in: modelContext,
                    affectedTrackIDs: relationshipTrackIDs
                )
            }

            if let proposed = changeSet.edits[.artwork] {
                guard case .artwork(let data) = proposed else {
                    throw TrackMetadataMutationError.invalidValue(.artwork)
                }
                let groupByTrackID = Dictionary(uniqueKeysWithValues: artworkTargets.map { ($0.trackID, $0.groupID) })
                func groupID(_ id: UUID) -> String {
                    groupByTrackID[id] ?? tracksByID[id]?.albumRelation?.id.uuidString ?? id.uuidString
                }
                let keptGroups = Set(decisions.filter {
                    $0.field == .artwork && $0.resolution == .useCurrent
                }.map { groupID($0.trackID) })
                let proposedGroups = Set(decisions.filter {
                    $0.field == .artwork && $0.resolution == .useProposed
                }.map { groupID($0.trackID) })
                guard keptGroups.isDisjoint(with: proposedGroups) else {
                    throw TrackMetadataMutationError.artworkScopeChanged
                }
                pendingArtwork = artworkTargetIDs.compactMap { id in
                    guard !keptGroups.contains(groupID(id)), currentValues[id]?[.artwork] != proposed else { return nil }
                    return (id, data)
                }
                let scopeIDs = Set(artworkTargetIDs)
                if pendingArtwork.contains(where: { pending in
                    guard let album = tracksByID[pending.trackID]?.albumRelation else { return true }
                    return album.tracks.contains { !scopeIDs.contains($0.id) }
                }) {
                    _ = try AlbumRelationshipReconciler.reconcile(in: modelContext, affectedTrackIDs: scopeIDs)
                }
            }

            var artworkByAlbumID: [UUID: TrackMetadataValue] = [:]
            var artworkAlbums: [UUID: Album] = [:]
            for pending in pendingArtwork {
                guard let track = tracksByID[pending.trackID] else { continue }
                if track.albumRelation == nil {
                    try linkRelations(for: track, in: modelContext)
                }
                guard let album = track.albumRelation else { continue }
                let proposed = TrackMetadataValue.artwork(pending.data)
                if let prior = artworkByAlbumID[album.id], prior != proposed {
                    throw TrackMetadataMutationError.inconsistentAlbumArtwork(album.id)
                }
                artworkByAlbumID[album.id] = proposed
                artworkAlbums[album.id] = album
            }
            let normalizedArtwork = pendingArtwork.first?.data.map(ArtworkStorage.normalized)
            for album in artworkAlbums.values {
                album.artworkData = normalizedArtwork
            }
            for track in tracks where track.albumRelation.map({ artworkAlbums[$0.id] != nil }) == true {
                changedTrackIDs.insert(track.id)
                appliedFields[track.id, default: [:]][.artwork] = .artwork(normalizedArtwork)
            }

            let modifiedAt = Date()
            for id in changedTrackIDs { tracksByID[id]?.dateModified = modifiedAt }
            try Task.checkCancellation()
            if changedTrackIDs.isEmpty == false { try modelContext.save() }
        } catch let error as TrackMetadataMutationError {
            modelContext.rollback()
            throw error
        } catch is CancellationError {
            modelContext.rollback()
            throw CancellationError()
        } catch {
            modelContext.rollback()
            throw TrackMetadataMutationError.persistence(error.localizedDescription)
        }

        return TrackMetadataMutationResult(
            outcome: .saved(trackCount: changedTrackIDs.count),
            fileWrites: appliedFields.compactMap { id, fields in
                guard let track = tracksByID[id] else { return nil }
                return TrackMetadataFileWrite(trackID: id, path: track.path, fields: fields)
            }
        )
    }

    private static let relationshipFields: Set<TrackMetadataField> = [
        .artist, .album, .albumArtist, .year,
    ]

    private func apply(
        _ value: TrackMetadataValue,
        field: TrackMetadataField,
        to track: Track,
        favoriteByID: [UUID: TrackFavorite],
        in modelContext: ModelContext
    ) throws {
        switch (field, value) {
        case (.title, .text(let value)): track.title = value
        case (.artist, .text(let value)): track.artist = value
        case (.album, .text(let value)): track.album = value
        case (.albumArtist, .text(let value)): track.albumArtist = value
        case (.genre, .text(let value)): track.genre = GenreMetadata.normalized(value)
        case (.composer, .text(let value)): track.composer = value
        case (.comment, .text(let value)): track.comment = value
        case (.year, .number(let value)): track.year = value
        case (.trackNumber, .number(let value)): track.trackNumber = value
        case (.trackTotal, .number(let value)): track.trackTotal = value
        case (.discNumber, .number(let value)): track.discNumber = value
        case (.discTotal, .number(let value)): track.discTotal = value
        case (.beatsPerMinute, .number(let value)): track.beatsPerMinute = value
        case (.rating, .number(let value)): track.rating = value
        case (.favorite, .flag(let value)):
            if value, favoriteByID[track.id] == nil {
                modelContext.insert(TrackFavorite(trackID: track.id))
            } else if value == false, let favorite = favoriteByID[track.id] {
                modelContext.delete(favorite)
            }
        default:
            throw TrackMetadataMutationError.invalidValue(field)
        }
    }

    private func validateArtworkDecisions(
        tracks: [Track],
        conflicts: [TrackMetadataConflict],
        decisions: [String: TrackMetadataConflictDecision]
    ) throws {
        let artworkConflicts = conflicts.filter { $0.field == .artwork }
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        var resolutionByAlbumID: [UUID: TrackMetadataConflictResolution] = [:]
        for conflict in artworkConflicts {
            guard let albumID = tracksByID[conflict.trackID]?.albumRelation?.id,
                  let resolution = decisions[conflict.id]?.resolution else { continue }
            if let prior = resolutionByAlbumID[albumID], prior != resolution {
                throw TrackMetadataMutationError.inconsistentAlbumArtwork(albumID)
            }
            resolutionByAlbumID[albumID] = resolution
        }
    }

    /// Relationship linking must execute in this service's model context. The
    /// importer's public helper is main-actor isolated because import itself is
    /// UI coordinated, so metadata mutation keeps the same identity policy here
    /// without moving persistent models across actors.
    private func linkRelations(for track: Track, in modelContext: ModelContext) throws {
        let artistName = track.artist.isEmpty ? "Unknown Artist" : track.artist
        let albumTitle = track.album.isEmpty ? "Unknown Album" : track.album
        let rawAlbumArtist = track.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let albumArtistName = rawAlbumArtist.isEmpty || rawAlbumArtist == "Unknown Artist"
            ? artistName
            : rawAlbumArtist

        var artistDescriptor = FetchDescriptor<Artist>(
            predicate: #Predicate { $0.name == artistName }
        )
        artistDescriptor.fetchLimit = 1
        let artist = try modelContext.fetch(artistDescriptor).first ?? {
            let created = Artist(name: artistName)
            modelContext.insert(created)
            return created
        }()
        track.artistRelation = artist

        let identity = AlbumPhysicalIdentity(
            title: albumTitle,
            path: track.path,
            performer: albumArtistName
        )
        let albums = try modelContext.fetch(FetchDescriptor<Album>())
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
        if let existing = matchingAlbum ?? reusableCurrentAlbum {
            album = existing
        } else {
            album = Album(title: albumTitle, artist: albumArtistName, year: track.year)
            modelContext.insert(album)
        }
        album.title = albumTitle
        track.albumRelation = album
        track.artworkData = nil
    }

    private static func values(
        for track: Track,
        isFavorite: Bool
    ) -> [TrackMetadataField: TrackMetadataValue] {
        [
            .title: .text(track.title), .artist: .text(track.artist),
            .album: .text(track.album), .albumArtist: .text(track.albumArtist),
            .genre: .text(GenreMetadata.normalized(track.genre)),
            .composer: .text(track.composer), .comment: .text(track.comment),
            .year: .number(track.year), .trackNumber: .number(track.trackNumber),
            .trackTotal: .number(track.trackTotal), .discNumber: .number(track.discNumber),
            .discTotal: .number(track.discTotal), .beatsPerMinute: .number(track.beatsPerMinute),
            .rating: .number(track.rating), .favorite: .flag(isFavorite),
            .artwork: .artwork(track.albumRelation?.artworkData),
        ]
    }
}
