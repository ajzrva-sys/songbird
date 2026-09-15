import AppKit
import Testing
@testable import SongbirdLib

@Suite("Window configuration ownership", .serialized)
@MainActor
struct PlayerWindowConfigurationTests {
    @Test("Mini updates preserve chrome until style or floating preference changes")
    func unchangedMiniUpdates() {
        let window = CountedWindow()
        let owner = PlayerWindowConfigurationOwner()
        for _ in 0..<100 {
            owner.configureMini(window, autosaveName: "FixtureMini", floatOnTop: false, style: .modern)
        }
        #expect(window.writes["autosave"] == 1)
        #expect(window.writes["style"] == 1)
        #expect(window.writes["invalidateShadow"] == 1)
        let writes = window.writes
        owner.configureMini(window, autosaveName: "FixtureMini", floatOnTop: true, style: .modern)
        #expect(window.level == .floating)
        #expect(window.writes.filter { $0.key != "level" } == writes.filter { $0.key != "level" })
        owner.configureMini(window, autosaveName: "FixtureMini", floatOnTop: true, style: .glass)
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == NSColor.clear)
        #expect(window.writes["invalidateShadow"] == 2)
        #expect(window.writes["autosave"] == 1)
        #expect(window.writes["style"] == 1)
    }

    @Test("Changed pane sizing does not restore the frame or repeat chrome setup")
    func mainPaneChangesAndReattachment() {
        let window = CountedWindow()
        let owner = PlayerWindowConfigurationOwner()
        var chromePasses = 0
        owner.configureMain(window, autosaveName: "FixtureMain", isMain: true,
                            sidebarShown: false, rightPaneShown: false) { chromePasses += 1 }
        let writes = window.writes
        owner.configureMain(window, autosaveName: "FixtureMain", isMain: true,
                            sidebarShown: true, rightPaneShown: true) { chromePasses += 1 }
        #expect(window.contentMinSize.width == PlayerWindowLayoutPolicy.minimumWidth(
            sidebarShown: true, rightPaneShown: true))
        #expect(window.writes.filter { $0.key != "minimum" } == writes.filter { $0.key != "minimum" })
        #expect(chromePasses == 1)
        let replacement = CountedWindow()
        owner.configureMain(replacement, autosaveName: "FixtureMain", isMain: true,
                            sidebarShown: true, rightPaneShown: true) { chromePasses += 1 }
        #expect(replacement.writes["autosave"] == 1)
        #expect(replacement.contentMinSize == window.contentMinSize)
        #expect(chromePasses == 2)
        let newOwner = PlayerWindowConfigurationOwner()
        let beforeRecreation = window.writes
        newOwner.configureMain(window, autosaveName: "FixtureMain", isMain: true,
                               sidebarShown: true, rightPaneShown: true) {}
        #expect(window.writes == beforeRecreation)
    }

    @Test("Reentrant layout callbacks see configuration intent before setters finish")
    func reentrantMainUpdate() {
        let window = CountedWindow()
        let owner = PlayerWindowConfigurationOwner()
        var chromePasses = 0
        owner.configureMain(window, autosaveName: "FixtureMain", isMain: true,
                            sidebarShown: true, rightPaneShown: false) {
            chromePasses += 1
            owner.configureMain(window, autosaveName: "FixtureMain", isMain: true,
                                sidebarShown: true, rightPaneShown: false) { chromePasses += 1 }
        }
        #expect(chromePasses == 1)
        #expect(window.writes["autosave"] == 1)
        #expect(window.writes["minimum"] == 1)
    }

    @Test("Unchanged main updates perform no setters or chrome work")
    func unchangedMainUpdates() {
        let window = CountedWindow()
        let owner = PlayerWindowConfigurationOwner()
        var chromePasses = 0
        for _ in 0..<100 {
            owner.configureMain(window, autosaveName: "FixtureMain", isMain: true,
                                sidebarShown: true, rightPaneShown: false) { chromePasses += 1 }
        }
        #expect(window.writes["autosave"] == 1)
        #expect(window.writes["minimum"] == 1)
        #expect(window.writes["style"] == 1)
        #expect(window.writes["toolbar", default: 0] == 0)
        #expect(chromePasses == 1)
        #expect(window.contentMinSize.width == PlayerWindowLayoutPolicy.minimumWidth(
            sidebarShown: true, rightPaneShown: false))
        let writes = window.writes
        owner.configureMain(window, autosaveName: "FixtureMain", isMain: true,
                            sidebarShown: true, rightPaneShown: false) { chromePasses += 1 }
        #expect(window.writes == writes)
    }
}

/// No NSApplication, real window, defaults, or display server is needed. Every
/// setter at the production AppKit boundary is counted, including equal writes.
@MainActor
private final class CountedWindow: PlayerWindowConfigurationTarget {
    var writes: [String: Int] = [:]
    var identifier: NSUserInterfaceItemIdentifier? { didSet { count("identifier") } }
    var frameAutosaveName: String = ""
    func setFrameAutosaveName(_ name: String) -> Bool {
        count("autosave")
        frameAutosaveName = name
        return true
    }
    var titleVisibility: NSWindow.TitleVisibility = .visible { didSet { count("title") } }
    var titlebarAppearsTransparent = false { didSet { count("transparent") } }
    var styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable] { didSet { count("style") } }
    var toolbar: NSToolbar? { didSet { count("toolbar") } }
    var isMovableByWindowBackground = true { didSet { count("movable") } }
    var contentMinSize = NSSize.zero { didSet { count("minimum") } }
    var titlebarSeparatorStyle: NSTitlebarSeparatorStyle = .automatic { didSet { count("separator") } }
    var hasShadow = false { didSet { count("shadow") } }
    var level: NSWindow.Level = .normal { didSet { count("level") } }
    var collectionBehavior: NSWindow.CollectionBehavior = [] { didSet { count("collection") } }
    var isOpaque = false { didSet { count("opaque") } }
    var backgroundColor: NSColor! = .clear { didSet { count("background") } }
    var contentView: NSView? { nil }
    func invalidateShadow() { count("invalidateShadow") }
    private func count(_ key: String) { writes[key, default: 0] += 1 }
}
