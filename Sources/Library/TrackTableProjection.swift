import Foundation
import OSLog

public enum TrackCollectionDescriptor: Hashable, Sendable {
    case allTracks
    case artist(String)
    case genre(String)
    case recentlyAdded(limit: Int = 200)
    case topPlayed
    case playlist(UUID)
    case orderedTrackIDs([UUID])
}

public struct TrackTableRequest: Hashable, Sendable {
    public var collection: TrackCollectionDescriptor
    public var searchText: String
    public var selectedArtist: String?
    public var selectedAlbumIDs: Set<String>
    public var selectedGenre: String?
    public var sortColumn: TrackSortColumn
    public var sortAscending: Bool
    public var usePlaylistOrder: Bool
    public var includesFacets: Bool
    public var columnPreferencesJSON: String

    public init(
        collection: TrackCollectionDescriptor,
        searchText: String = "",
        selectedArtist: String? = nil,
        selectedAlbumID: String? = nil,
        selectedAlbumIDs: Set<String> = [],
        selectedGenre: String? = nil,
        sortColumn: TrackSortColumn = .dateAdded,
        sortAscending: Bool = false,
        usePlaylistOrder: Bool = true,
        includesFacets: Bool = true,
        columnPreferencesJSON: String = TrackTableColumnPrefs.encode(TrackTableColumnPrefs.defaults)
    ) {
        self.collection = collection
        self.searchText = searchText
        self.selectedArtist = selectedArtist
        self.selectedAlbumIDs = selectedAlbumIDs.isEmpty
            ? Set(selectedAlbumID.map { [$0] } ?? [])
            : selectedAlbumIDs
        self.selectedGenre = selectedGenre
        self.sortColumn = sortColumn
        self.sortAscending = sortAscending
        self.usePlaylistOrder = usePlaylistOrder
        self.includesFacets = includesFacets
        self.columnPreferencesJSON = columnPreferencesJSON
    }
}

public struct TrackTableAlbumFacet: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let detail: String?
    public let albumIDs: [UUID]
    public let trackIDs: [UUID]

    public init(
        id: String,
        title: String,
        detail: String? = nil,
        albumIDs: [UUID],
        trackIDs: [UUID]
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.albumIDs = albumIDs
        self.trackIDs = trackIDs
    }
}

public struct TrackTableColumnDefinition: Identifiable, Hashable, Sendable {
    public let preference: TrackColumnPref
    public let column: TrackSortColumn
    public let width: Double

    public var id: TrackSortColumn { column }
}

public struct TrackTableFacets: Equatable, Sendable {
    public let artists: [String]
    public let albums: [TrackTableAlbumFacet]
    public let genres: [String]

    public static let empty = TrackTableFacets(artists: [], albums: [], genres: [])
}

public struct TrackTableDisplayValues: Equatable, Sendable {
    private let values: [TrackSortColumn: String]

    public static let fallback = TrackTableDisplayValues(values: [
        .title: "Unknown",
        .albumRating: "—",
        .duration: "0:00",
        .playCount: "0",
        .dateAdded: "—",
        .dateModified: "—",
        .lastPlayed: "—",
        .bitRate: "—",
        .sampleRate: "—",
        .kind: "—",
        .releaseDate: "—",
        .year: "—",
        .size: "—",
        .trackNumber: "—",
        .discNumber: "—",
        .beatsPerMinute: "—",
    ])

    private init(values: [TrackSortColumn: String]) {
        self.values = values
    }

    public init(track: LibraryTrackSnapshot, columns: [TrackSortColumn] = TrackSortColumn.allCases) {
        // Hidden date/size columns must not format every track at startup.
        // Changing visible columns requests a fresh projection.
        var values: [TrackSortColumn: String] = [:]
        for column in columns {
            switch column {
            case .title: values[column] = track.title.isEmpty ? "Unknown" : track.title
            case .albumRating: values[column] = track.albumRating > 0 ? String(track.albumRating) : "—"
            case .duration: values[column] = Self.duration(track.duration)
            case .playCount: values[column] = String(track.playCount)
            case .dateAdded: values[column] = track.dateAdded.formatted(date: .abbreviated, time: .omitted)
            case .dateModified: values[column] = track.dateModified.formatted(date: .abbreviated, time: .omitted)
            case .lastPlayed: values[column] = track.lastPlayed?.formatted(date: .abbreviated, time: .omitted) ?? "—"
            case .bitRate: values[column] = track.bitrate > 0 ? "\(track.bitrate) kbps" : "—"
            case .sampleRate: values[column] = track.sampleRate > 0 ? "\(track.sampleRate) Hz" : "—"
            case .kind: values[column] = track.fileKind.isEmpty ? "—" : track.fileKind
            case .releaseDate, .year: values[column] = track.year > 0 ? String(track.year) : "—"
            case .size:
                values[column] = track.fileSize > 0
                    ? ByteCountFormatter.string(fromByteCount: track.fileSize, countStyle: .file) : "—"
            case .trackNumber: values[column] = track.trackNumber > 0 ? String(track.trackNumber) : "—"
            case .discNumber: values[column] = track.discNumber > 0 ? String(track.discNumber) : "—"
            case .beatsPerMinute: values[column] = track.beatsPerMinute > 0 ? String(track.beatsPerMinute) : "—"
            default: break // These columns render their snapshot value directly.
            }
        }
        self.values = values
    }

    public func text(for column: TrackSortColumn) -> String? {
        values[column]
    }

    private static func duration(_ duration: TimeInterval) -> String {
        "\(Int(duration) / 60):" + String(format: "%02d", Int(duration) % 60)
    }
}

public struct TrackTableProjection: Equatable, Sendable {
    public let sourceRevision: Int
    public let rows: [LibraryTrackSnapshot]
    public let orderedIDs: [UUID]
    public let indexByID: [UUID: Int]
    public let displayValuesByID: [UUID: TrackTableDisplayValues]
    public let facets: TrackTableFacets
    public let totalDuration: TimeInterval
    public let columns: [TrackTableColumnDefinition]
    public let sourceWasEmpty: Bool

    public static let empty = TrackTableProjection(
        sourceRevision: 0,
        rows: [],
        orderedIDs: [],
        indexByID: [:],
        displayValuesByID: [:],
        facets: .empty,
        totalDuration: 0,
        columns: [],
        sourceWasEmpty: true
    )

    public func selectionRange(anchorID: UUID, targetID: UUID) -> Set<UUID> {
        guard let anchor = indexByID[anchorID], let target = indexByID[targetID] else {
            return [targetID]
        }
        return Set(orderedIDs[min(anchor, target)...max(anchor, target)])
    }

    public func selectedIDsInDisplayOrder(_ selected: Set<UUID>) -> [UUID] {
        orderedIDs.filter(selected.contains)
    }

    /// Album-detail rows are already ordered and indexed in the in-memory
    /// library snapshot. Build that tiny projection synchronously so opening
    /// an album never needs an artificial loading screen.
    static func immediateOrdered(
        snapshot: LibrarySnapshot,
        trackIDs: [UUID],
        columnPreferencesJSON: String
    ) -> TrackTableProjection {
        let rows = trackIDs.compactMap { snapshot.tracksByID[$0] }
        let orderedIDs = rows.map(\.id)
        let indexByID = Dictionary(
            uniqueKeysWithValues: orderedIDs.enumerated().map { ($1, $0) }
        )
        let columns = TrackTableColumnPrefs.decode(columnPreferencesJSON).compactMap {
            preference -> TrackTableColumnDefinition? in
            guard preference.visible, let column = preference.column, column.isSupported else { return nil }
            return TrackTableColumnDefinition(
                preference: preference,
                column: column,
                width: Double(TrackTableColumnPrefs.resolvedWidth(for: preference))
            )
        }
        let displayColumns = columns.map(\.column)
        return TrackTableProjection(
            sourceRevision: snapshot.revision,
            rows: rows,
            orderedIDs: orderedIDs,
            indexByID: indexByID,
            displayValuesByID: Dictionary(
                uniqueKeysWithValues: rows.map { ($0.id, TrackTableDisplayValues(track: $0, columns: displayColumns)) }
            ),
            facets: .empty,
            totalDuration: rows.reduce(0) { $0 + $1.duration },
            columns: columns,
            sourceWasEmpty: rows.isEmpty
        )
    }
}

public actor TrackTableProjectionWorker {
    private struct FacetCacheKey: Hashable {
        let collection: TrackCollectionDescriptor
        let selectedArtist: String?
        let selectedAlbumIDs: Set<String>
        let albumProjectionRevision: Int
    }

    private struct CachedFacets {
        let facets: TrackTableFacets
        let selectedAlbumTrackIDs: Set<UUID>?
    }

    private static let signposter = OSSignposter(
        subsystem: "com.songbird.player",
        category: "TrackTableProjection"
    )

    public init() {}
    private var completedProjectionCount = 0
    private var completedSortCount = 0
    private var completedCollectionBuildCount = 0
    private var completedFacetBuildCount = 0
    private var cacheRevision: Int?
    private var collectionCache: [TrackCollectionDescriptor: [LibraryTrackSnapshot]] = [:]
    private var facetCache: [FacetCacheKey: CachedFacets] = [:]

    public func projectionCount() -> Int { completedProjectionCount }
    public func sortCount() -> Int { completedSortCount }
    public func collectionCacheCount() -> Int { collectionCache.count }
    public func facetCacheCount() -> Int { facetCache.count }
    public func collectionBuildCount() -> Int { completedCollectionBuildCount }
    public func facetBuildCount() -> Int { completedFacetBuildCount }

    public func project(
        snapshot: LibrarySnapshot,
        request: TrackTableRequest,
        albumGroups: [LibraryAlbumGroupSnapshot] = [],
        albumProjectionRevision: Int = 0
    ) throws -> TrackTableProjection {
        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval("Table projection", id: signpostID)
        defer { Self.signposter.endInterval("Table projection", state) }

        resetCachesIfNeeded(for: snapshot.revision)
        let source = try collection(snapshot: snapshot, descriptor: request.collection)
        try Task.checkCancellation()

        let needsFacets = request.includesFacets
            || request.selectedArtist != nil
            || request.selectedAlbumIDs.isEmpty == false
            || request.selectedGenre != nil
        let cachedFacets: CachedFacets
        if needsFacets {
            let key = FacetCacheKey(
                collection: request.collection,
                selectedArtist: request.selectedArtist,
                selectedAlbumIDs: request.selectedAlbumIDs,
                albumProjectionRevision: albumProjectionRevision
            )
            if let cached = facetCache[key] {
                cachedFacets = cached
            } else {
                let artists = uniqueSorted(source.lazy.map(\.albumArtist))
                let albumSource = request.selectedArtist.map { artist in
                    source.filter { $0.albumArtist == artist }
                } ?? source
                let albums = albumFacets(source: albumSource, groups: albumGroups)
                let selectedAlbumTrackIDs: Set<UUID>? = request.selectedAlbumIDs.isEmpty
                    ? nil
                    : Set(
                        albums
                            .filter { request.selectedAlbumIDs.contains($0.id) }
                            .flatMap(\.trackIDs)
                    )
                let genreSource = selectedAlbumTrackIDs.map { trackIDs in
                    albumSource.filter { trackIDs.contains($0.id) }
                } ?? albumSource
                let genres = uniqueSorted(genreSource.lazy.map(\.genre))
                let built = CachedFacets(
                    facets: TrackTableFacets(artists: artists, albums: albums, genres: genres),
                    selectedAlbumTrackIDs: selectedAlbumTrackIDs
                )
                facetCache[key] = built
                completedFacetBuildCount += 1
                cachedFacets = built
            }
        } else {
            cachedFacets = CachedFacets(facets: .empty, selectedAlbumTrackIDs: nil)
        }
        let selectedAlbumTrackIDs = cachedFacets.selectedAlbumTrackIDs

        var rows = source
        if let artist = request.selectedArtist {
            rows.removeAll { $0.albumArtist != artist }
        }
        if let trackIDs = selectedAlbumTrackIDs {
            rows.removeAll { !trackIDs.contains($0.id) }
        }
        if let genre = request.selectedGenre {
            rows.removeAll { $0.genre.localizedCaseInsensitiveCompare(genre) != .orderedSame }
        }
        if request.searchText.isEmpty == false {
            let search = request.searchText
            rows.removeAll {
                $0.title.localizedCaseInsensitiveContains(search) == false
                    && $0.artist.localizedCaseInsensitiveContains(search) == false
                    && $0.album.localizedCaseInsensitiveContains(search) == false
                    && $0.genre.localizedCaseInsensitiveContains(search) == false
            }
        }
        try Task.checkCancellation()

        if shouldSort(snapshot: snapshot, request: request) {
            rows.sort { compare($0, $1, column: request.sortColumn, ascending: request.sortAscending) }
        }
        try Task.checkCancellation()

        let ids = rows.map(\.id)
        let lookup = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let prefs = TrackTableColumnPrefs.decode(request.columnPreferencesJSON)
        let columns = prefs.compactMap { pref -> TrackTableColumnDefinition? in
            guard pref.visible, let column = pref.column, column.isSupported else { return nil }
            return TrackTableColumnDefinition(
                preference: pref,
                column: column,
                width: Double(TrackTableColumnPrefs.resolvedWidth(for: pref))
            )
        }

        let displayColumns = columns.map(\.column)
        let projection = TrackTableProjection(
            sourceRevision: snapshot.revision,
            rows: rows,
            orderedIDs: ids,
            indexByID: lookup,
            displayValuesByID: Dictionary(
                uniqueKeysWithValues: rows.map { ($0.id, TrackTableDisplayValues(track: $0, columns: displayColumns)) }
            ),
            facets: cachedFacets.facets,
            totalDuration: rows.reduce(0) { $0 + $1.duration },
            columns: columns,
            sourceWasEmpty: source.isEmpty
        )
        completedProjectionCount += 1
        return projection
    }

    public func sort(
        projection: TrackTableProjection,
        column: TrackSortColumn,
        ascending: Bool
    ) throws -> TrackTableProjection {
        try Task.checkCancellation()
        var rows = projection.rows
        rows.sort { compare($0, $1, column: column, ascending: ascending) }
        try Task.checkCancellation()
        let ids = rows.map(\.id)
        completedSortCount += 1
        return TrackTableProjection(
            sourceRevision: projection.sourceRevision,
            rows: rows,
            orderedIDs: ids,
            indexByID: Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) }),
            displayValuesByID: projection.displayValuesByID,
            facets: projection.facets,
            totalDuration: projection.totalDuration,
            columns: projection.columns,
            sourceWasEmpty: projection.sourceWasEmpty
        )
    }

    private func resetCachesIfNeeded(for revision: Int) {
        guard cacheRevision != revision else { return }
        cacheRevision = revision
        collectionCache.removeAll(keepingCapacity: true)
        facetCache.removeAll(keepingCapacity: true)
    }

    private func collection(
        snapshot: LibrarySnapshot,
        descriptor: TrackCollectionDescriptor
    ) throws -> [LibraryTrackSnapshot] {
        if let cached = collectionCache[descriptor] { return cached }
        let result: [LibraryTrackSnapshot]
        switch descriptor {
        case .allTracks:
            result = snapshot.tracks
        case .artist(let artist):
            result = snapshot.tracks.filter { $0.artist == artist }
        case .genre(let genre):
            result = snapshot.tracks.filter { $0.genre.localizedCaseInsensitiveCompare(genre) == .orderedSame }
        case .recentlyAdded(let limit):
            result = Array(snapshot.tracks.prefix(max(0, limit)))
        case .topPlayed:
            result = snapshot.tracks.filter { $0.playCount > 0 }
                .sorted { $0.playCount > $1.playCount }
        case .playlist(let playlistID):
            guard let playlist = snapshot.playlistsByID[playlistID] else {
                return []
            }
            if playlist.isSmart, let rules = playlist.rules {
                result = try snapshot.tracks.enumerated().compactMap { index, track in
                    if index.isMultiple(of: 256) { try Task.checkCancellation() }
                    return rules.matches(track) ? track : nil
                }
            } else {
                result = playlist.trackIDs.compactMap { snapshot.tracksByID[$0] }
            }
        case .orderedTrackIDs(let trackIDs):
            result = trackIDs.compactMap { snapshot.tracksByID[$0] }
        }
        collectionCache[descriptor] = result
        completedCollectionBuildCount += 1
        return result
    }

    private func shouldSort(snapshot: LibrarySnapshot, request: TrackTableRequest) -> Bool {
        switch request.collection {
        case .playlist(let id):
            guard let playlist = snapshot.playlistsByID[id],
                  playlist.isSmart == false else { return true }
            return request.usePlaylistOrder == false
        case .orderedTrackIDs:
            return false
        default:
            return true
        }
    }

    private func uniqueSorted<S: Sequence>(_ strings: S) -> [String] where S.Element == String {
        LibrarySnapshot.normalizedGenreList(Array(strings.filter { $0.isEmpty == false }))
    }

    private func albumFacets(
        source: [LibraryTrackSnapshot],
        groups: [LibraryAlbumGroupSnapshot]
    ) -> [TrackTableAlbumFacet] {
        let sourceIDs = Set(source.map(\.id))
        var candidates: [(group: LibraryAlbumGroupSnapshot, trackIDs: [UUID])] = groups.compactMap {
            let trackIDs = $0.trackIDs.filter(sourceIDs.contains)
            return trackIDs.isEmpty ? nil : ($0, trackIDs)
        }

        if candidates.isEmpty, !source.isEmpty {
            let fallback = Dictionary(grouping: source) { track in
                AlbumPhysicalIdentity(
                    title: track.album,
                    path: track.path,
                    performer: track.albumArtist.isEmpty ? track.artist : track.albumArtist
                )
            }
            candidates = fallback.map { identity, tracks in
                let title = tracks.first?.album.isEmpty == false
                    ? tracks.first!.album
                    : "Unknown Album"
                let group = LibraryAlbumGroupSnapshot(
                    id: "fallback:\(identity.stableKey)",
                    title: title,
                    artist: tracks.first?.albumArtist ?? tracks.first?.artist ?? "Unknown Artist",
                    year: tracks.first?.year ?? 0,
                    dateAdded: tracks.map(\.dateAdded).max() ?? .distantPast,
                    albumIDs: Array(Set(tracks.compactMap(\.albumID))),
                    trackIDs: tracks.map(\.id),
                    artworkReference: tracks.lazy.compactMap(\.artworkReference).first,
                    discCount: 1,
                    partCount: 1,
                    editionLabel: identity.folderName.isEmpty ? nil : identity.folderName,
                    isFavorite: false
                )
                return (group, tracks.map(\.id))
            }
        }

        let details = LibraryAlbumDisplayDetail.details(for: candidates.map(\.group))

        return candidates.map { candidate in
            let group = candidate.group
            return TrackTableAlbumFacet(
                id: group.id,
                title: group.title,
                detail: details[group.id],
                albumIDs: group.albumIDs,
                trackIDs: candidate.trackIDs
            )
        }.sorted {
            let title = $0.title.localizedCaseInsensitiveCompare($1.title)
            return title != .orderedSame
                ? title == .orderedAscending
                : ($0.detail ?? "").localizedCaseInsensitiveCompare($1.detail ?? "")
                    == .orderedAscending
        }
    }

    func compare(
        _ lhs: LibraryTrackSnapshot,
        _ rhs: LibraryTrackSnapshot,
        column: TrackSortColumn,
        ascending: Bool
    ) -> Bool {
        let result: ComparisonResult
        switch column {
        case .title, .sortTitle: result = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        case .artist, .sortArtist: result = lhs.artist.localizedCaseInsensitiveCompare(rhs.artist)
        case .album, .sortAlbum: result = lhs.album.localizedCaseInsensitiveCompare(rhs.album)
        case .albumArtist, .sortAlbumArtist:
            result = lhs.albumArtist.localizedCaseInsensitiveCompare(rhs.albumArtist)
        case .albumRating: result = order(lhs.albumRating, rhs.albumRating)
        case .genre: result = lhs.genre.localizedCaseInsensitiveCompare(rhs.genre)
        case .comments, .description: result = lhs.comment.localizedCaseInsensitiveCompare(rhs.comment)
        case .composer, .sortComposer: result = lhs.composer.localizedCaseInsensitiveCompare(rhs.composer)
        case .duration: result = order(lhs.duration, rhs.duration)
        case .rating, .starRating: result = order(lhs.rating, rhs.rating)
        case .playCount: result = order(lhs.playCount, rhs.playCount)
        case .dateAdded: result = order(lhs.dateAdded, rhs.dateAdded)
        case .dateModified: result = order(lhs.dateModified, rhs.dateModified)
        case .lastPlayed: result = order(lhs.lastPlayed ?? .distantPast, rhs.lastPlayed ?? .distantPast)
        case .bitRate: result = order(lhs.bitrate, rhs.bitrate)
        case .sampleRate: result = order(lhs.sampleRate, rhs.sampleRate)
        case .kind: result = lhs.fileKind.localizedCaseInsensitiveCompare(rhs.fileKind)
        case .releaseDate, .year: result = order(lhs.year, rhs.year)
        case .size: result = order(lhs.fileSize, rhs.fileSize)
        case .trackNumber: result = order(lhs.trackNumber, rhs.trackNumber)
        case .discNumber: result = order(lhs.discNumber, rhs.discNumber)
        case .beatsPerMinute: result = order(lhs.beatsPerMinute, rhs.beatsPerMinute)
        case .lastSkipped, .movementNumber,
             .skipCount, .grouping, .movementName, .work:
            result = .orderedSame
        }
        if result == .orderedSame { return lhs.id.uuidString < rhs.id.uuidString }
        return ascending ? result == .orderedAscending : result == .orderedDescending
    }

    private func order<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : lhs > rhs ? .orderedDescending : .orderedSame
    }
}
