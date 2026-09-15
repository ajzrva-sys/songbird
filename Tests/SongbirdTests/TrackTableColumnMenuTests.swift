import AppKit
import SwiftUI
import XCTest
@testable import SongbirdLib

final class TrackTableColumnMenuTests: XCTestCase {
    @MainActor
    private func header(preferences: Binding<String>) -> TrackTableColumnHeader {
        _ = NSApplication.shared
        return TrackTableColumnHeader(
            columnPrefsRaw: preferences,
            sortColumnRaw: .constant(TrackSortColumn.title.rawValue),
            sortAscending: .constant(true),
            usePlaylistOrder: .constant(false),
            resizePreviewWidths: .constant([:]),
            showsPlaylistOrderOption: false
        )
    }

    @MainActor
    func testHeaderMenuExposesColumnChoicesDirectly() throws {
        guard #available(macOS 14.4, *) else {
            throw XCTSkip("NSHostingMenu requires macOS 14.4")
        }
        let header = header(preferences: .constant(
            TrackTableColumnPrefs.encode(TrackTableColumnPrefs.defaults)
        ))
        let menu = NSHostingMenu(rootView: header.contextMenuItems(for: .album))
        menu.update()
        let labels = Set(menu.items.map(\.title))
        for preference in TrackTableColumnPrefs.defaults {
            if let column = preference.column, column.isSupported {
                XCTAssertTrue(labels.contains(column.label), column.label)
            }
        }
        let title = try XCTUnwrap(menu.items.first { $0.title == "Title" })
        XCTAssertFalse(title.isEnabled)
        XCTAssertEqual(title.state, .on)
        XCTAssertEqual(menu.items.filter { $0.title == "Reset Columns" }.count, 1)
        XCTAssertTrue(labels.isSuperset(of: ["Move Left", "Move Right"]))
    }

    @MainActor
    func testNativeColumnChoicePersistsAndResetRestoresDefaults() throws {
        guard #available(macOS 14.4, *) else {
            throw XCTSkip("NSHostingMenu requires macOS 14.4")
        }
        var preferences = TrackTableColumnPrefs.defaults
        preferences[2].width = 317
        let before = preferences
        var raw = TrackTableColumnPrefs.encode(preferences)
        let header = header(preferences: Binding(get: { raw }, set: { raw = $0 }))
        let menu = NSHostingMenu(rootView: header.contextMenuItems(for: .genre))
        menu.update()
        let genreIndex = try XCTUnwrap(menu.items.firstIndex { $0.title == "Genre" })
        XCTAssertEqual(menu.items[genreIndex].state, .on)
        menu.performActionForItem(at: genreIndex)
        let changed = TrackTableColumnPrefs.decode(raw)
        XCTAssertEqual(changed.first { $0.column == .genre }?.visible, false)
        XCTAssertEqual(changed.first { $0.column == .title }?.visible, true)
        XCTAssertEqual(changed.map(\.id), before.map(\.id))
        XCTAssertEqual(changed.map(\.width), before.map(\.width))

        let reopened = NSHostingMenu(rootView: header.contextMenuItems(for: .album))
        reopened.update()
        XCTAssertEqual(reopened.items.first { $0.title == "Genre" }?.state, .off)
        let resetIndex = try XCTUnwrap(reopened.items.firstIndex { $0.title == "Reset Columns" })
        reopened.performActionForItem(at: resetIndex)
        XCTAssertEqual(TrackTableColumnPrefs.decode(raw), TrackTableColumnPrefs.defaults)
    }
}
