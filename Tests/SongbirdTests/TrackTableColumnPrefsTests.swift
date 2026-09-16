import XCTest
@testable import SongbirdLib

final class TrackTableColumnPrefsTests: XCTestCase {
    func testColumnCatalogIncludesRequestedMetadataFields() {
        let labels = Set(TrackTableColumnPrefs.defaults.compactMap { $0.column?.label })

        XCTAssertEqual(labels, Set([
            "Album", "Album Artist", "Album Rating", "Artist", "BPM",
            "Bit Rate", "Comments", "Composer", "Date Added", "Date Modified",
            "Disc Number", "Favorite", "Genre", "Kind", "Last Played",
            "Plays", "Rating", "Sample Rate", "Size", "Time", "Title", "Track", "Year",
        ]))
    }

    func testUnsupportedLegacyColumnRemainsDecodableButHidden() {
        let raw = TrackTableColumnPrefs.encode([
            TrackColumnPref(id: TrackSortColumn.title.rawValue, visible: true),
            TrackColumnPref(id: TrackSortColumn.grouping.rawValue, visible: true),
        ])
        let restored = TrackTableColumnPrefs.decode(raw)

        XCTAssertEqual(restored.first(where: { $0.column == .grouping })?.visible, false)
        XCTAssertFalse(TrackSortColumn.grouping.isSupported)
        XCTAssertTrue(TrackSortColumn.discNumber.isSupported)
    }

    func testLegacyColumnPreferencesBackfillNewColumns() {
        let legacy = [
            TrackColumnPref(id: TrackSortColumn.title.rawValue, visible: true, width: 220),
            TrackColumnPref(id: TrackSortColumn.artist.rawValue, visible: true, width: 140),
        ]

        let restored = TrackTableColumnPrefs.decode(TrackTableColumnPrefs.encode(legacy))

        XCTAssertEqual(restored.first?.column, .title)
        XCTAssertEqual(restored.dropFirst().first?.column, .artist)
        XCTAssertEqual(Set(restored.map(\.id)), Set(TrackTableColumnPrefs.defaults.map(\.id)))
    }

    func testAlbumArtistIsTheDefaultVisibleArtistColumn() {
        let prefs = TrackTableColumnPrefs.defaults

        XCTAssertEqual(prefs.first(where: { $0.column == .albumArtist })?.visible, true)
        XCTAssertEqual(prefs.first(where: { $0.column == .artist })?.visible, false)
    }

    func testPrimaryColumnsUseTheRequestedReadingOrder() {
        XCTAssertEqual(
            Array(TrackTableColumnPrefs.defaults.prefix(7).map(\.column)),
            [.rating, .albumArtist, .title, .album, .duration, .genre, .playCount]
        )
    }

    func testExistingPreferencesMigrateOrderWithoutLosingCustomization() {
        var oldPreferences = TrackTableColumnPrefs.defaults
        oldPreferences.reverse()
        let customTitleWidth = 317.0
        oldPreferences[oldPreferences.firstIndex(where: { $0.column == .title })!].width = customTitleWidth

        let migrated = TrackTableColumnPrefs.preferringPrimaryColumnOrder(oldPreferences)

        XCTAssertEqual(
            Array(migrated.prefix(7).map(\.column)),
            [.rating, .albumArtist, .title, .album, .duration, .genre, .playCount]
        )
        XCTAssertEqual(migrated.first(where: { $0.column == .title })?.width, customTitleWidth)
    }

    func testExistingPreferencesMigrateFromArtistToAlbumArtist() {
        let oldDefaults = [
            TrackColumnPref(id: TrackSortColumn.title.rawValue, visible: true, width: 220),
            TrackColumnPref(id: TrackSortColumn.artist.rawValue, visible: true, width: 140),
            TrackColumnPref(id: TrackSortColumn.album.rawValue, visible: true, width: 140),
            TrackColumnPref(id: TrackSortColumn.albumArtist.rawValue, visible: false, width: 140),
        ]

        let migrated = TrackTableColumnPrefs.preferringAlbumArtist(oldDefaults)

        XCTAssertEqual(migrated.map(\.column), [.title, .albumArtist, .artist, .album])
        XCTAssertEqual(migrated.first(where: { $0.column == .artist })?.visible, false)
        XCTAssertEqual(migrated.first(where: { $0.column == .albumArtist })?.visible, true)
    }

    func testTopPlayedPreferencesRevealPlayCountWithoutChangingOrder() {
        let preferences = TrackTableColumnPrefs.preferringPlayCount([
            TrackColumnPref(id: TrackSortColumn.title.rawValue, visible: true, width: 220),
            TrackColumnPref(id: TrackSortColumn.album.rawValue, visible: true, width: 140),
            TrackColumnPref(id: TrackSortColumn.playCount.rawValue, visible: false, width: 56),
        ])

        XCTAssertEqual(preferences.map(\.column), [.title, .album, .playCount])
        XCTAssertTrue(preferences[2].visible)
    }

    func testDraggedColumnCanMoveBeforeTarget() {
        var prefs = TrackTableColumnPrefs.defaults

        TrackTableColumnPrefs.reorder(
            &prefs,
            movingID: TrackSortColumn.genre.rawValue,
            relativeTo: TrackSortColumn.albumArtist.rawValue,
            placeAfter: false
        )

        XCTAssertEqual(
            Array(prefs.prefix(4).map(\.id)),
            ["rating", "genre", "albumArtist", "title"]
        )
    }

    func testDraggedColumnCanMoveAfterTargetAndPersist() {
        var prefs = TrackTableColumnPrefs.defaults

        TrackTableColumnPrefs.reorder(
            &prefs,
            movingID: TrackSortColumn.title.rawValue,
            relativeTo: TrackSortColumn.album.rawValue,
            placeAfter: true
        )
        let restored = TrackTableColumnPrefs.decode(TrackTableColumnPrefs.encode(prefs))

        XCTAssertEqual(
            Array(restored.prefix(4).map(\.id)),
            ["rating", "albumArtist", "album", "title"]
        )
    }

    func testColumnWidthsClampToSupportedRange() {
        XCTAssertEqual(
            TrackTableColumnPrefs.clampedWidth(20, for: .title),
            TrackTableColumnPrefs.minimumWidth(for: .title)
        )
        XCTAssertEqual(TrackTableColumnPrefs.clampedWidth(240, for: .title), 240)
        XCTAssertEqual(TrackTableColumnPrefs.clampedWidth(900, for: .title), 600)
    }

    func testFavoriteStaysCompactWithLegacyWidthsWithoutResettingOtherColumns() {
        let prefs = TrackTableColumnPrefs.decode(TrackTableColumnPrefs.encode([
            TrackColumnPref(id: "rating", visible: true, width: 100),
            TrackColumnPref(id: "title", visible: true, width: 317),
        ]))

        XCTAssertEqual(TrackTableColumnPrefs.resolvedWidth(for: prefs[0]), 32)
        XCTAssertEqual(TrackTableColumnPrefs.resolvedWidth(for: prefs[1]), 317)
        XCTAssertEqual(TrackTableColumnPrefs.defaultWidth(for: .rating), 32)
        XCTAssertEqual(TrackTableColumnPrefs.clampedWidth(100, for: .rating), 32)
        XCTAssertEqual(prefs.map(\.id).prefix(2), ["rating", "title"])
        XCTAssertTrue(prefs[0].visible)
    }

    func testSharedTableWidthAccountsForInsetsArtworkColumnsAndGaps() {
        let columns = [
            TrackTableColumnDefinition(
                preference: TrackColumnPref(id: "title", visible: true, width: 200),
                column: .title,
                width: 200
            ),
            TrackTableColumnDefinition(
                preference: TrackColumnPref(id: "discNumber", visible: true, width: 60),
                column: .discNumber,
                width: 60
            ),
        ]

        XCTAssertEqual(
            TrackTableLayout.contentWidth(columns: columns, presentation: .classic),
            16 + 200 + 60 + 8
        )
        XCTAssertEqual(
            TrackTableLayout.contentWidth(
                columns: columns,
                presentation: .comfortable,
                previewWidths: [.title: 240]
            ),
            16 + 36 + 240 + 60 + 8
        )
    }
}
