import AppKit
import SwiftUI
import XCTest
@testable import SongbirdLib

final class AlbumCardButtonTests: XCTestCase {
    @MainActor
    func testExplicitPlayAndOpenButtonsInvokeOnlyTheirOwnAction() throws {
        guard #available(macOS 14.4, *) else {
            throw XCTSkip("NSHostingMenu requires macOS 14.4")
        }
        _ = NSApplication.shared
        var playCount = 0
        var openCount = 0
        var selectionCount = 0
        let play = NSHostingMenu(rootView: AlbumCardPlayButton(
            title: "Example",
            action: { playCount += 1 },
            isRevealed: true
        ))
        play.update()
        let playIndex = try XCTUnwrap(play.items.firstIndex { $0.isEnabled && !$0.isSeparatorItem })
        play.performActionForItem(at: playIndex)
        XCTAssertEqual(playCount, 1)
        XCTAssertEqual(openCount, 0)

        let open = NSHostingMenu(rootView: AlbumCardOpenButton(
            title: "Example",
            textColor: .primary,
            action: { openCount += 1 },
            selectionAction: { _ in selectionCount += 1 }
        ))
        open.update()
        let openIndex = try XCTUnwrap(open.items.firstIndex { $0.isEnabled && !$0.isSeparatorItem })
        open.performActionForItem(at: openIndex)
        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(playCount, 1)
        XCTAssertEqual(selectionCount, 0)
    }

    @MainActor
    func testPlayButtonReservesItsFortyFourPointTarget() {
        _ = NSApplication.shared
        let hosted = NSHostingView(rootView: AlbumCardPlayButton(title: "Example", action: {}, isRevealed: true))
        XCTAssertEqual(hosted.fittingSize.width, 44, accuracy: 0.5)
        XCTAssertEqual(hosted.fittingSize.height, 44, accuracy: 0.5)
    }

    @MainActor
    func testModifiedTitleMouseClicksSelectWithoutOpening() throws {
        var openCount = 0
        var selections: [NSEvent.ModifierFlags] = []
        let button = AlbumCardOpenButton(
            title: "Example",
            textColor: .primary,
            action: { openCount += 1 },
            selectionAction: { selections.append($0) }
        )
        let modifiers: [NSEvent.ModifierFlags] = [.command, .shift, [.command, .shift, .option]]
        for flags in modifiers {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            ))
            button.activate(event: event)
        }
        XCTAssertEqual(selections, modifiers)
        XCTAssertEqual(openCount, 0)
    }

    @MainActor
    func testPlainMouseAndKeyboardTitleActivationOpen() throws {
        var openCount = 0
        var selectionCount = 0
        let button = AlbumCardOpenButton(
            title: "Example",
            textColor: .primary,
            action: { openCount += 1 },
            selectionAction: { _ in selectionCount += 1 }
        )
        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        let key = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
        button.activate(event: click)
        button.activate(event: key)
        button.activate(event: nil)
        XCTAssertEqual(openCount, 3)
        XCTAssertEqual(selectionCount, 0)
    }

}
