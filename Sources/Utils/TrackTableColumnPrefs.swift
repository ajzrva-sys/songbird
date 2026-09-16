import Foundation

/// Persisted column visibility/order/width for the track table (artwork gutter always on).
public struct TrackColumnPref: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var visible: Bool
    public var width: Double?

    public init(id: String, visible: Bool, width: Double? = nil) {
        self.id = id
        self.visible = visible
        self.width = width
    }

    public var column: TrackSortColumn? {
        TrackSortColumn(rawValue: id)
    }
}

public enum TrackTableColumnPrefs {
    public static let storageKey = "trackTable.columnPrefs"
    public static let albumArtistDefaultMigrationKey = "trackTable.albumArtistDefaultMigrated"
    public static let primaryColumnOrderMigrationKey = "trackTable.primaryColumnOrderMigrated"
    public static let favoriteColumnWidth: CGFloat = 32

    public static let defaults: [TrackColumnPref] = [
        .init(id: TrackSortColumn.rating.rawValue, visible: true, width: Double(favoriteColumnWidth)),
        .init(id: TrackSortColumn.albumArtist.rawValue, visible: true, width: 140),
        .init(id: TrackSortColumn.title.rawValue, visible: true, width: 220),
        .init(id: TrackSortColumn.album.rawValue, visible: true, width: 140),
        .init(id: TrackSortColumn.duration.rawValue, visible: true, width: 56),
        .init(id: TrackSortColumn.genre.rawValue, visible: true, width: 100),
        .init(id: TrackSortColumn.playCount.rawValue, visible: true, width: 56),
        .init(id: TrackSortColumn.artist.rawValue, visible: false, width: 140),
        .init(id: TrackSortColumn.albumRating.rawValue, visible: false, width: 90),
        .init(id: TrackSortColumn.beatsPerMinute.rawValue, visible: false, width: 110),
        .init(id: TrackSortColumn.bitRate.rawValue, visible: false, width: 80),
        .init(id: TrackSortColumn.comments.rawValue, visible: false, width: 180),
        .init(id: TrackSortColumn.composer.rawValue, visible: false, width: 140),
        .init(id: TrackSortColumn.dateAdded.rawValue, visible: false, width: 90),
        .init(id: TrackSortColumn.dateModified.rawValue, visible: false, width: 90),
        .init(id: TrackSortColumn.discNumber.rawValue, visible: false, width: 84),
        .init(id: TrackSortColumn.kind.rawValue, visible: false, width: 70),
        .init(id: TrackSortColumn.lastPlayed.rawValue, visible: false, width: 110),
        .init(id: TrackSortColumn.starRating.rawValue, visible: false, width: 70),
        .init(id: TrackSortColumn.sampleRate.rawValue, visible: false, width: 90),
        .init(id: TrackSortColumn.size.rawValue, visible: false, width: 80),
        .init(id: TrackSortColumn.trackNumber.rawValue, visible: false, width: 60),
        .init(id: TrackSortColumn.year.rawValue, visible: false, width: 56),
    ]

    public static func defaultWidth(for column: TrackSortColumn) -> CGFloat {
        switch column {
        case .title: return 220
        case .artist, .album, .albumArtist, .composer, .movementName, .sortAlbum,
             .sortAlbumArtist, .sortArtist, .sortComposer, .work:
            return 140
        case .comments, .description, .sortTitle: return 180
        case .genre, .grouping, .releaseDate: return 100
        case .beatsPerMinute, .lastPlayed, .lastSkipped, .movementNumber:
            return 110
        case .duration, .skipCount, .year: return 56
        case .rating: return favoriteColumnWidth
        case .starRating, .kind: return 70
        case .playCount: return 48
        case .trackNumber: return 60
        case .dateAdded, .dateModified, .albumRating, .sampleRate:
            return 90
        case .bitRate, .size: return 80
        case .discNumber: return 84
        }
    }

    public static func minimumWidth(for column: TrackSortColumn) -> CGFloat {
        switch column {
        case .title: return 120
        case .artist, .album, .albumArtist, .composer, .comments, .description,
             .movementName, .sortAlbum, .sortAlbumArtist, .sortArtist, .sortComposer,
             .sortTitle, .work:
            return 80
        case .genre, .grouping:
            return 60
        case .trackNumber: return 30
        case .duration, .playCount, .kind, .skipCount, .year,
             .discNumber, .movementNumber, .beatsPerMinute:
            return 40
        case .rating: return favoriteColumnWidth
        case .starRating, .albumRating: return 48
        case .dateAdded, .dateModified, .lastPlayed, .lastSkipped,
             .releaseDate:
            return 70
        case .bitRate, .sampleRate, .size: return 56
        }
    }

    public static func resolvedWidth(for pref: TrackColumnPref) -> CGFloat {
        // The icon-only Favorite column stays compact, including with older saved widths.
        if pref.column == .rating { return favoriteColumnWidth }
        if let width = pref.width, width > 0 {
            return CGFloat(width)
        }
        if let column = pref.column {
            return defaultWidth(for: column)
        }
        return 100
    }

    public static func clampedWidth(_ width: CGFloat, for column: TrackSortColumn) -> CGFloat {
        if column == .rating { return favoriteColumnWidth }
        return max(minimumWidth(for: column), min(600, width))
    }

    public static func decode(_ raw: String) -> [TrackColumnPref] {
        guard let data = raw.data(using: .utf8),
              let prefs = try? JSONDecoder().decode([TrackColumnPref].self, from: data),
              !prefs.isEmpty else {
            return defaults
        }
        var byID = Dictionary(uniqueKeysWithValues: prefs.map { ($0.id, $0) })
        for def in defaults where byID[def.id] == nil {
            byID[def.id] = def
        }
        // Backfill missing widths from defaults.
        for def in defaults {
            guard var pref = byID[def.id] else { continue }
            if pref.width == nil || (pref.width ?? 0) <= 0 {
                pref.width = def.width
                byID[def.id] = pref
            }
        }
        let order = prefs.map(\.id) + defaults.map(\.id).filter { !prefs.map(\.id).contains($0) }
        var seen = Set<String>()
        return order.compactMap { id -> TrackColumnPref? in
            guard seen.insert(id).inserted, let pref = byID[id] else { return nil }
            guard let column = pref.column, column.isSupported else {
                var hidden = pref
                hidden.visible = false
                return hidden
            }
            return pref
        }
    }

    public static func encode(_ prefs: [TrackColumnPref]) -> String {
        guard let data = try? JSONEncoder().encode(prefs),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    public static func preferringAlbumArtist(_ prefs: [TrackColumnPref]) -> [TrackColumnPref] {
        var result = prefs
        guard let artistIndex = result.firstIndex(where: { $0.column == .artist }),
              let albumArtistIndex = result.firstIndex(where: { $0.column == .albumArtist }) else {
            return result
        }
        result[artistIndex].visible = false
        result[albumArtistIndex].visible = true
        if albumArtistIndex != artistIndex {
            let albumArtist = result.remove(at: albumArtistIndex)
            result.insert(albumArtist, at: min(artistIndex, result.endIndex))
        }
        return result
    }

    public static func preferringPlayCount(_ prefs: [TrackColumnPref]) -> [TrackColumnPref] {
        var result = prefs
        guard let playCountIndex = result.firstIndex(where: { $0.column == .playCount }) else {
            return result
        }
        result[playCountIndex].visible = true
        return result
    }

    /// Places the primary library columns in their standard reading order while preserving
    /// every column's visibility and user-selected width.
    public static func preferringPrimaryColumnOrder(
        _ prefs: [TrackColumnPref]
    ) -> [TrackColumnPref] {
        let primaryColumns: [TrackSortColumn] = [
            .rating, .albumArtist, .title, .album, .duration, .genre, .playCount,
        ]
        let primaryIDs = Set(primaryColumns.map(\.rawValue))
        let preferencesByID = Dictionary(uniqueKeysWithValues: prefs.map { ($0.id, $0) })
        let primaryPreferences = primaryColumns.compactMap { preferencesByID[$0.rawValue] }
        return primaryPreferences + prefs.filter { !primaryIDs.contains($0.id) }
    }

    public static func move(_ prefs: inout [TrackColumnPref], id: String, direction: Int) {
        guard let idx = prefs.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + direction
        guard prefs.indices.contains(target) else { return }
        prefs.swapAt(idx, target)
    }

    static func reorder(
        _ prefs: inout [TrackColumnPref],
        movingID: String,
        relativeTo targetID: String,
        placeAfter: Bool
    ) {
        guard movingID != targetID,
              let sourceIndex = prefs.firstIndex(where: { $0.id == movingID }) else { return }
        let moving = prefs.remove(at: sourceIndex)
        guard let targetIndex = prefs.firstIndex(where: { $0.id == targetID }) else {
            prefs.insert(moving, at: sourceIndex)
            return
        }
        let insertionIndex = targetIndex + (placeAfter ? 1 : 0)
        prefs.insert(moving, at: min(insertionIndex, prefs.endIndex))
    }

    public static func setWidth(_ prefs: inout [TrackColumnPref], id: String, width: CGFloat) {
        guard let idx = prefs.firstIndex(where: { $0.id == id }),
              let column = TrackSortColumn(rawValue: id) else { return }
        prefs[idx].width = Double(clampedWidth(width, for: column))
    }
}
