import Foundation
import SwiftData

public struct AlbumReconciliationOutcome: Equatable, Sendable {
    public let splitAlbums: Int
    public let mergedAlbums: Int
    public let reassignedTracks: Int
    public let unchangedGroups: Int

    public init(
        splitAlbums: Int,
        mergedAlbums: Int,
        reassignedTracks: Int,
        unchangedGroups: Int
    ) {
        self.splitAlbums = splitAlbums
        self.mergedAlbums = mergedAlbums
        self.reassignedTracks = reassignedTracks
        self.unchangedGroups = unchangedGroups
    }
}

public enum AlbumRelationshipReconciler {
    public static func reconcile(
        in container: ModelContainer,
        affectedTrackIDs: Set<UUID>? = nil
    ) async throws -> AlbumReconciliationOutcome {
        try await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            do {
                let outcome = try reconcile(
                    in: context,
                    affectedTrackIDs: affectedTrackIDs
                )
                try context.save()
                return outcome
            } catch {
                context.rollback()
                throw error
            }
        }.value
    }

    static func reconcile(
        in context: ModelContext,
        affectedTrackIDs: Set<UUID>? = nil
    ) throws -> AlbumReconciliationOutcome {
        let tracks = try context.fetch(FetchDescriptor<Track>())
        let albums = try context.fetch(FetchDescriptor<Album>())
        let favorites = try context.fetch(FetchDescriptor<AlbumFavorite>())
        var favoritesByAlbumID = Dictionary(
            favorites.map { ($0.albumID, $0) },
            uniquingKeysWith: { first, duplicate in
                context.delete(duplicate)
                return first
            }
        )

        var tracksByIdentity: [AlbumPhysicalIdentity: [Track]] = [:]
        var identitiesByAlbumID: [UUID: Set<AlbumPhysicalIdentity>] = [:]
        for track in tracks {
            let identity = physicalIdentity(for: track)
            tracksByIdentity[identity, default: []].append(track)
            if let albumID = track.albumRelation?.id {
                identitiesByAlbumID[albumID, default: []].insert(identity)
            }
        }

        var targetIdentities: Set<AlbumPhysicalIdentity>
        if let affectedTrackIDs {
            targetIdentities = Set(tracks.filter { affectedTrackIDs.contains($0.id) }.map(physicalIdentity))
            var changed = true
            while changed {
                let relatedAlbumIDs = Set(targetIdentities.flatMap { identity in
                    tracksByIdentity[identity, default: []].compactMap { $0.albumRelation?.id }
                })
                let expanded = Set(relatedAlbumIDs.flatMap { identitiesByAlbumID[$0, default: []] })
                let previousCount = targetIdentities.count
                targetIdentities.formUnion(expanded)
                changed = targetIdentities.count != previousCount
            }
        } else {
            targetIdentities = Set(tracksByIdentity.keys)
        }
        let deletionCandidateAlbumIDs: Set<UUID>? = affectedTrackIDs == nil ? nil : Set(
            targetIdentities.flatMap { identity in
                tracksByIdentity[identity, default: []].compactMap { $0.albumRelation?.id }
            }
        )

        var preferredIdentityByAlbumID: [UUID: AlbumPhysicalIdentity] = [:]
        for (albumID, identities) in identitiesByAlbumID {
            preferredIdentityByAlbumID[albumID] = identities.sorted { lhs, rhs in
                let leftCount = tracksByIdentity[lhs, default: []].count
                let rightCount = tracksByIdentity[rhs, default: []].count
                return leftCount != rightCount
                    ? leftCount > rightCount
                    : lhs.stableKey < rhs.stableKey
            }.first
        }

        let splitAlbums = identitiesByAlbumID.values.filter { $0.count > 1 }.count
        var reassignedTracks = 0
        var unchangedGroups = 0
        var survivorIDs: Set<UUID> = []

        for identity in targetIdentities.sorted(by: { $0.stableKey < $1.stableKey }) {
            let identityTracks = tracksByIdentity[identity, default: []]
            guard !identityTracks.isEmpty else { continue }
            let sourceAlbums = unique(
                identityTracks.compactMap(\.albumRelation),
                by: \.id
            )
            let candidates = sourceAlbums.filter {
                preferredIdentityByAlbumID[$0.id] == identity
            }.sorted(by: survivorOrder)
            let survivor: Album
            if let existing = candidates.first {
                survivor = existing
            } else {
                survivor = Album(
                    title: preferredTitle(identityTracks),
                    artist: preferredArtist(identityTracks),
                    year: preferredYear(identityTracks)
                )
                if let oldestDate = sourceAlbums.map(\.dateAdded).min() {
                    survivor.dateAdded = oldestDate
                }
                context.insert(survivor)
            }

            survivor.title = preferredTitle(identityTracks)
            survivor.artist = preferredArtist(identityTracks)
            survivor.year = preferredYear(identityTracks)
            if survivor.artworkData == nil {
                survivor.artworkData = sourceAlbums.lazy.compactMap(\.artworkData).first
            }

            let shouldFavorite = sourceAlbums.contains {
                favoritesByAlbumID[$0.id] != nil
            }
            if shouldFavorite, favoritesByAlbumID[survivor.id] == nil {
                let favorite = AlbumFavorite(albumID: survivor.id)
                context.insert(favorite)
                favoritesByAlbumID[survivor.id] = favorite
            }

            var groupChanged = sourceAlbums.count != 1 || sourceAlbums.first?.id != survivor.id
            for track in identityTracks where track.albumRelation?.id != survivor.id {
                track.albumRelation = survivor
                reassignedTracks += 1
                groupChanged = true
            }
            if !groupChanged { unchangedGroups += 1 }
            survivorIDs.insert(survivor.id)
        }

        let usedAlbumIDs = Set(tracks.compactMap { $0.albumRelation?.id })
        let deletedAlbums = albums.filter {
            !usedAlbumIDs.contains($0.id)
                && (deletionCandidateAlbumIDs?.contains($0.id) ?? true)
        }
        for album in deletedAlbums {
            if let favorite = favoritesByAlbumID.removeValue(forKey: album.id) {
                context.delete(favorite)
            }
            context.delete(album)
        }

        for favorite in favorites where !usedAlbumIDs.contains(favorite.albumID)
            && (deletionCandidateAlbumIDs?.contains(favorite.albumID) ?? true)
            && !survivorIDs.contains(favorite.albumID) {
            context.delete(favorite)
        }

        return AlbumReconciliationOutcome(
            splitAlbums: splitAlbums,
            mergedAlbums: deletedAlbums.count,
            reassignedTracks: reassignedTracks,
            unchangedGroups: unchangedGroups
        )
    }

    static func physicalIdentity(for track: Track) -> AlbumPhysicalIdentity {
        let albumTitle = AlbumPhysicalIdentity.isMeaningfulAlbumTitle(track.album)
            ? track.album
            : track.albumRelation?.title ?? track.album
        let albumArtist = track.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        return AlbumPhysicalIdentity(
            title: albumTitle,
            path: track.path,
            performer: albumArtist.isEmpty ? track.artist : albumArtist
        )
    }

    private static func survivorOrder(_ lhs: Album, _ rhs: Album) -> Bool {
        if lhs.tracks.count != rhs.tracks.count { return lhs.tracks.count > rhs.tracks.count }
        if lhs.dateAdded != rhs.dateAdded { return lhs.dateAdded < rhs.dateAdded }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func preferredTitle(_ tracks: [Track]) -> String {
        mostCommon(
            tracks.map(\.album).filter(AlbumPhysicalIdentity.isMeaningfulAlbumTitle)
        ) ?? "Unknown Album"
    }

    private static func preferredArtist(_ tracks: [Track]) -> String {
        let albumArtists = tracks.map(\.albumArtist).filter(isMeaningfulArtist)
        if let value = dominant(albumArtists) { return value }
        let performers = tracks.map(\.artist).filter(isMeaningfulArtist)
        return dominant(performers) ?? "Unknown Artist"
    }

    private static func preferredYear(_ tracks: [Track]) -> Int {
        let years = tracks.map(\.year).filter { $0 > 0 }
        return Dictionary(grouping: years, by: { $0 })
            .max(by: { $0.value.count < $1.value.count })?.key ?? 0
    }

    private static func dominant(_ values: [String]) -> String? {
        let groups = Dictionary(grouping: values, by: AlbumPhysicalIdentity.normalized)
            .values.sorted { $0.count > $1.count }
        guard let first = groups.first else { return nil }
        return groups.count == 1 || first.count > groups[1].count
            ? first[0]
            : "Various Artists"
    }

    private static func mostCommon(_ values: [String]) -> String? {
        Dictionary(grouping: values, by: AlbumPhysicalIdentity.normalized)
            .values.max(by: { $0.count < $1.count })?.first
    }

    private static func isMeaningfulArtist(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && AlbumPhysicalIdentity.normalized(trimmed)
                != AlbumPhysicalIdentity.normalized("Unknown Artist")
    }

    private static func unique<Value, Key: Hashable>(
        _ values: [Value],
        by keyPath: KeyPath<Value, Key>
    ) -> [Value] {
        var seen: Set<Key> = []
        return values.filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
