import Foundation
import OSLog

public enum LibraryAlbumCollectionKind: String, Equatable, Sendable {
    case disc
    case volume
}

public struct LibraryAlbumGroupSnapshot: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let year: Int
    public let dateAdded: Date
    public let albumIDs: [UUID]
    public let trackIDs: [UUID]
    public let artworkReference: ArtworkReference?
    public let discCount: Int
    public let partCount: Int
    public let collectionKind: LibraryAlbumCollectionKind?
    public let editionLabel: String?
    public let isFavorite: Bool

    public init(
        id: String,
        title: String,
        artist: String,
        year: Int,
        dateAdded: Date,
        albumIDs: [UUID],
        trackIDs: [UUID],
        artworkReference: ArtworkReference?,
        discCount: Int,
        partCount: Int? = nil,
        collectionKind: LibraryAlbumCollectionKind? = nil,
        editionLabel: String? = nil,
        isFavorite: Bool
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.year = year
        self.dateAdded = dateAdded
        self.albumIDs = albumIDs
        self.trackIDs = trackIDs
        self.artworkReference = artworkReference
        self.discCount = discCount
        self.partCount = partCount ?? discCount
        self.collectionKind = collectionKind
        self.editionLabel = editionLabel
        self.isFavorite = isFavorite
    }
}

public enum LibraryAlbumDisplayDetail {
    public static func details(
        for groups: [LibraryAlbumGroupSnapshot]
    ) -> [String: String] {
        let titleCounts = Dictionary(grouping: groups, by: { normalized($0.title) })
            .mapValues(\.count)
        let editionCounts = Dictionary(grouping: groups.compactMap { group -> String? in
            guard titleCounts[normalized(group.title), default: 0] > 1,
                  let label = group.editionLabel else { return nil }
            return "\(normalized(group.title))\u{0}\(normalized(label))"
        }, by: { $0 }).mapValues(\.count)

        return Dictionary(uniqueKeysWithValues: groups.compactMap { group in
            let detail: String?
            if group.partCount > 1 {
                let unit = group.collectionKind == .volume ? "volumes" : "discs"
                let artist = group.artist == "Various Artists" ? " · Various Artists" : ""
                detail = "\(group.partCount) \(unit)\(artist)"
            } else if titleCounts[normalized(group.title), default: 0] > 1 {
                let edition = group.editionLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
                let collisionKey = edition.map {
                    "\(normalized(group.title))\u{0}\(normalized($0))"
                }
                if let edition, !edition.isEmpty,
                   collisionKey.map({ editionCounts[$0, default: 0] == 1 }) == true {
                    detail = edition
                } else {
                    let year = group.year > 0 ? " · \(group.year)" : ""
                    detail = "\(group.artist)\(year)"
                }
            } else {
                detail = nil
            }
            return detail.map { (group.id, $0) }
        })
    }

    private static func normalized(_ value: String) -> String {
        AlbumPhysicalIdentity.normalized(value)
    }
}

public actor LibraryAlbumProjectionWorker {
    private struct PhysicalGroup {
        let id: String
        let identity: AlbumPhysicalIdentity
        let title: String
        let artist: String
        let albums: [LibraryAlbumSnapshot]
        let tracks: [LibraryTrackSnapshot]
    }

    private struct LogicalGroup {
        let id: String
        let title: String
        let artist: String
        let physicalGroups: [PhysicalGroup]
        let partCount: Int
        let editionLabel: String?
        let collectionKind: LibraryAlbumCollectionKind?
    }

    private static let signposter = OSSignposter(
        subsystem: "com.songbird.player",
        category: "AlbumProjection"
    )

    public init() {}
    private var completedProjectionCount = 0

    public func projectionCount() -> Int { completedProjectionCount }

    public func project(_ snapshot: LibrarySnapshot) throws -> [LibraryAlbumGroupSnapshot] {
        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval("Album grouping", id: signpostID)
        defer { Self.signposter.endInterval("Album grouping", state) }

        let physicalGroups = try makePhysicalGroups(snapshot)
        var folderCollections: [String: [(PhysicalGroup, String, Int)]] = [:]
        var titleCandidates: [PhysicalGroup] = []

        for group in physicalGroups {
            try Task.checkCancellation()
            let locations = group.tracks.compactMap {
                MultiDiscAlbumTitle.collectionFolder(inPath: $0.path)
            }
            let grouped = Dictionary(grouping: locations, by: { $0.path.albumFoldingKey })
            guard let dominant = grouped.values.max(by: { $0.count < $1.count }),
                  dominant.count * 2 >= max(1, group.tracks.count),
                  let location = dominant.first else {
                titleCandidates.append(group)
                continue
            }
            folderCollections[location.path.albumFoldingKey, default: []].append(
                (group, location.name, location.discNumber)
            )
        }

        var logicalGroups: [LogicalGroup] = []
        for (folderPath, entries) in folderCollections {
            let numbers = Set(entries.map(\.2))
            guard numbers.count > 1, let first = entries.first else {
                titleCandidates.append(contentsOf: entries.map(\.0))
                continue
            }
            let sorted = entries.sorted {
                if $0.2 != $1.2 { return $0.2 < $1.2 }
                let title = $0.0.title.localizedCaseInsensitiveCompare($1.0.title)
                if title != .orderedSame { return title == .orderedAscending }
                return $0.0.id < $1.0.id
            }
            let inferred = sorted.compactMap { entry in
                MultiDiscAlbumTitle.infer(
                    title: entry.0.title,
                    year: mostCommonYear(entry.0),
                    trackPaths: entry.0.tracks.map(\.path)
                )?.baseTitle
            }
            let title = inferred.count == sorted.count
                && Set(inferred.map(\.albumFoldingKey)).count == 1
                ? inferred[0]
                : first.1
            let physical = sorted.map(\.0)
            logicalGroups.append(LogicalGroup(
                id: "folder:\(folderPath):\(numbers.sorted())",
                title: title,
                artist: collectionArtist(physical),
                physicalGroups: physical,
                partCount: numbers.count,
                editionLabel: first.1,
                collectionKind: physical.contains {
                    MultiDiscAlbumTitle.isNumberedVolumeTitle($0.title)
                } ? .volume : .disc
            ))
        }

        var multiDisc: [String: [(PhysicalGroup, MultiDiscAlbumTitle, Int)]] = [:]
        for group in titleCandidates {
            try Task.checkCancellation()
            let year = mostCommonYear(group)
            guard let parsed = MultiDiscAlbumTitle.infer(
                title: group.title,
                year: year,
                trackPaths: group.tracks.map(\.path)
            ) else {
                logicalGroups.append(singleLogicalGroup(group))
                continue
            }
            multiDisc[
                "\(parsed.baseTitle.albumFoldingKey)\u{0}\(group.artist.albumFoldingKey)\u{0}\(year)",
                default: []
            ].append((group, parsed, year))
        }

        for entries in multiDisc.values {
            guard entries.count > 1, let first = entries.first else {
                logicalGroups.append(contentsOf: entries.map { singleLogicalGroup($0.0) })
                continue
            }
            let sorted = entries.sorted {
                $0.1.discNumber != $1.1.discNumber
                    ? $0.1.discNumber < $1.1.discNumber
                    : $0.0.title.localizedCaseInsensitiveCompare($1.0.title) == .orderedAscending
            }
            let physical = sorted.map(\.0)
            logicalGroups.append(LogicalGroup(
                id: "multidisc:\(first.1.baseTitle.albumFoldingKey):\(first.0.artist.albumFoldingKey):\(first.2)",
                title: first.1.baseTitle,
                artist: collectionArtist(physical),
                physicalGroups: physical,
                partCount: Set(entries.map { $0.1.discNumber }).count,
                editionLabel: commonParentFolderName(physical),
                collectionKind: physical.contains {
                    MultiDiscAlbumTitle.isNumberedVolumeTitle($0.title)
                } ? .volume : .disc
            ))
        }

        let result = logicalGroups.map(makeSnapshot).sorted {
            let title = $0.title.localizedCaseInsensitiveCompare($1.title)
            if title != .orderedSame { return title == .orderedAscending }
            let artist = $0.artist.localizedCaseInsensitiveCompare($1.artist)
            if artist != .orderedSame { return artist == .orderedAscending }
            return ($0.editionLabel ?? "").localizedCaseInsensitiveCompare($1.editionLabel ?? "")
                == .orderedAscending
        }
        completedProjectionCount += 1
        return result
    }

    private func makePhysicalGroups(_ snapshot: LibrarySnapshot) throws -> [PhysicalGroup] {
        let albumsByID = snapshot.albumsByID
        var albumIDByTrackID: [UUID: UUID] = [:]
        for album in snapshot.albums {
            for trackID in album.trackIDs where albumIDByTrackID[trackID] == nil {
                albumIDByTrackID[trackID] = album.id
            }
        }
        var tracksByIdentity: [AlbumPhysicalIdentity: [LibraryTrackSnapshot]] = [:]
        var albumIDsByIdentity: [AlbumPhysicalIdentity: Set<UUID>] = [:]

        for (index, track) in snapshot.tracks.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            let resolvedAlbumID = track.albumID ?? albumIDByTrackID[track.id]
            let albumTitle = AlbumPhysicalIdentity.isMeaningfulAlbumTitle(track.album)
                ? track.album
                : resolvedAlbumID.flatMap { albumsByID[$0]?.title } ?? track.album
            let identity = AlbumPhysicalIdentity(
                title: albumTitle,
                path: track.path,
                performer: preferredArtist(for: track)
            )
            tracksByIdentity[identity, default: []].append(track)
            if let albumID = resolvedAlbumID {
                albumIDsByIdentity[identity, default: []].insert(albumID)
            }
        }

        var result = tracksByIdentity.map { identity, tracks -> PhysicalGroup in
            let albumIDs = albumIDsByIdentity[identity, default: []]
            let albums = albumIDs.compactMap { albumsByID[$0] }
            let title = mostCommonText(
                tracks.map(\.album).filter(AlbumPhysicalIdentity.isMeaningfulAlbumTitle)
                    + albums.map(\.title)
            ) ?? "Unknown Album"
            return PhysicalGroup(
                id: "physical:\(identity.stableKey)",
                identity: identity,
                title: title,
                artist: dominantArtist(tracks: tracks, albums: albums),
                albums: albums,
                tracks: tracks
            )
        }

        let assignedAlbumIDs = Set(albumIDsByIdentity.values.flatMap { $0 })
        for album in snapshot.albums where !assignedAlbumIDs.contains(album.id) {
            let identity = AlbumPhysicalIdentity(
                title: album.title,
                path: "/__songbird_orphans__/\(album.id.uuidString)/track",
                performer: album.artist
            )
            result.append(PhysicalGroup(
                id: "orphan:\(album.id.uuidString)",
                identity: identity,
                title: album.title,
                artist: album.artist,
                albums: [album],
                tracks: []
            ))
        }
        return result
    }

    private func singleLogicalGroup(_ group: PhysicalGroup) -> LogicalGroup {
        LogicalGroup(
            id: group.id,
            title: group.title,
            artist: group.artist,
            physicalGroups: [group],
            partCount: 1,
            editionLabel: group.identity.folderName.isEmpty ? nil : group.identity.folderName,
            collectionKind: nil
        )
    }

    private func makeSnapshot(_ group: LogicalGroup) -> LibraryAlbumGroupSnapshot {
        let albums = unique(group.physicalGroups.flatMap(\.albums), by: \.id)
        let tracks = unique(group.physicalGroups.flatMap(\.tracks), by: \.id).sorted {
            let leftDisc = MultiDiscAlbumTitle.discNumber(inPath: $0.path)
                ?? MultiDiscAlbumTitle.parse($0.album)?.discNumber ?? 1
            let rightDisc = MultiDiscAlbumTitle.discNumber(inPath: $1.path)
                ?? MultiDiscAlbumTitle.parse($1.album)?.discNumber ?? 1
            if leftDisc != rightDisc { return leftDisc < rightDisc }
            if $0.trackNumber != $1.trackNumber { return $0.trackNumber < $1.trackNumber }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        let discNumbers = Set(tracks.map {
            MultiDiscAlbumTitle.discNumber(inPath: $0.path)
                ?? MultiDiscAlbumTitle.parse($0.album)?.discNumber ?? 1
        })
        let partCount = max(1, group.partCount)
        return LibraryAlbumGroupSnapshot(
            id: group.id,
            title: group.title,
            artist: group.artist,
            year: mostCommonYear(group.physicalGroups),
            dateAdded: albums.map(\.dateAdded).max()
                ?? tracks.map(\.dateAdded).max()
                ?? .distantPast,
            albumIDs: albums.map(\.id),
            trackIDs: tracks.map(\.id),
            artworkReference: albums.lazy.compactMap(\.artworkReference).first
                ?? tracks.lazy.compactMap(\.artworkReference).first,
            discCount: max(partCount, discNumbers.count),
            partCount: partCount,
            collectionKind: partCount > 1 ? group.collectionKind : nil,
            editionLabel: group.editionLabel,
            isFavorite: !albums.isEmpty && albums.allSatisfy(\.isFavorite)
        )
    }

    private func preferredArtist(for track: LibraryTrackSnapshot) -> String {
        let albumArtist = track.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        return !albumArtist.isEmpty && albumArtist != "Unknown Artist" ? albumArtist : track.artist
    }

    private func dominantArtist(
        tracks: [LibraryTrackSnapshot],
        albums: [LibraryAlbumSnapshot]
    ) -> String {
        let albumArtists = tracks.map(\.albumArtist).filter(isMeaningfulArtist)
        if let artist = dominantText(albumArtists) { return artist }
        let performers = tracks.map(\.artist).filter(isMeaningfulArtist)
        if let artist = dominantText(performers) { return artist }
        return dominantText(albums.map(\.artist).filter(isMeaningfulArtist)) ?? "Unknown Artist"
    }

    private func collectionArtist(_ groups: [PhysicalGroup]) -> String {
        let artists = Dictionary(grouping: groups.map(\.artist), by: \.albumFoldingKey)
            .values.compactMap(\.first)
        return artists.count == 1 ? artists[0] : "Various Artists"
    }

    private func dominantText(_ values: [String]) -> String? {
        let groups = Dictionary(grouping: values, by: \.albumFoldingKey)
            .values.sorted { $0.count > $1.count }
        guard let first = groups.first else { return nil }
        guard groups.count == 1 || first.count > groups[1].count else { return "Various Artists" }
        return first[0]
    }

    private func mostCommonText(_ values: [String]) -> String? {
        Dictionary(grouping: values, by: \.albumFoldingKey)
            .values.max { $0.count < $1.count }?.first
    }

    private func isMeaningfulArtist(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.albumFoldingKey != "unknown artist".albumFoldingKey
    }

    private func mostCommonYear(_ group: PhysicalGroup) -> Int {
        mostCommonYear([group])
    }

    private func mostCommonYear(_ groups: [PhysicalGroup]) -> Int {
        let years = groups.flatMap { group in
            group.tracks.map(\.year) + group.albums.map(\.year)
        }.filter { $0 > 0 }
        return Dictionary(grouping: years, by: { $0 })
            .max(by: { $0.value.count < $1.value.count })?.key ?? 0
    }

    private func commonParentFolderName(_ groups: [PhysicalGroup]) -> String? {
        let parents = groups.compactMap { group -> String? in
            guard let track = group.tracks.first else { return nil }
            let trackFolder = (track.path as NSString).deletingLastPathComponent
            let parentFolder = (trackFolder as NSString).deletingLastPathComponent
            let folder = (parentFolder as NSString).lastPathComponent
            return folder.isEmpty ? nil : folder
        }
        guard let first = parents.first,
              parents.allSatisfy({ $0.albumFoldingKey == first.albumFoldingKey }) else {
            return nil
        }
        return first
    }

    private func unique<Value, Key: Hashable>(
        _ values: [Value],
        by keyPath: KeyPath<Value, Key>
    ) -> [Value] {
        var seen: Set<Key> = []
        return values.filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

private extension String {
    var albumFoldingKey: String {
        AlbumPhysicalIdentity.normalized(self)
    }
}
