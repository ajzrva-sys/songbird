import AppKit

/// The AppKit setter boundary, also usable without creating a native window.
@MainActor
public protocol PlayerWindowConfigurationTarget: AnyObject {
    var identifier: NSUserInterfaceItemIdentifier? { get set }
    var frameAutosaveName: String { get }
    @discardableResult func setFrameAutosaveName(_ name: String) -> Bool
    var titleVisibility: NSWindow.TitleVisibility { get set }
    var titlebarAppearsTransparent: Bool { get set }
    var styleMask: NSWindow.StyleMask { get set }
    var toolbar: NSToolbar? { get set }
    var isMovableByWindowBackground: Bool { get set }
    var contentMinSize: NSSize { get set }
    var titlebarSeparatorStyle: NSTitlebarSeparatorStyle { get set }
    var hasShadow: Bool { get set }
    var level: NSWindow.Level { get set }
    var collectionBehavior: NSWindow.CollectionBehavior { get set }
    var isOpaque: Bool { get set }
    var backgroundColor: NSColor! { get set }
    var contentView: NSView? { get }
    func invalidateShadow()
}

extension NSWindow: PlayerWindowConfigurationTarget {}

@MainActor
public final class PlayerWindowConfigurationOwner {
    private weak var window: (any PlayerWindowConfigurationTarget)?
    private var mainConfiguration: MainConfiguration?
    private var miniConfiguration: MiniConfiguration?

    private struct MiniConfiguration: Equatable {
        let autosaveName: String
        let floatOnTop: Bool
        let style: MiniPlayerStyle
    }

    private struct MainConfiguration: Equatable {
        let autosaveName: String
        let isMain: Bool
        let minimumSize: NSSize?
    }

    public init() {}

    public func configureMini(
        _ window: any PlayerWindowConfigurationTarget,
        autosaveName: String,
        floatOnTop: Bool,
        style: MiniPlayerStyle
    ) {
        let configuration = MiniConfiguration(autosaveName: autosaveName, floatOnTop: floatOnTop, style: style)
        let previous = self.window === window ? miniConfiguration : nil
        guard previous != configuration else { return }
        self.window = window
        miniConfiguration = configuration
        mainConfiguration = nil
        if previous?.autosaveName != autosaveName, window.frameAutosaveName != autosaveName {
            window.setFrameAutosaveName(autosaveName)
        }
        if previous == nil {
            let identifier = NSUserInterfaceItemIdentifier("mini-player")
            if window.identifier != identifier { window.identifier = identifier }
            // Borderless chrome; closable/miniaturizable so ⌘W and Minimize work.
            let mask: NSWindow.StyleMask = [.borderless, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            if window.styleMask != mask { window.styleMask = mask }
            if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
            if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
            if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
            if !window.isMovableByWindowBackground { window.isMovableByWindowBackground = true }
            if !window.hasShadow { window.hasShadow = true }
            if !window.collectionBehavior.contains(.fullScreenAuxiliary) {
                window.collectionBehavior.insert(.fullScreenAuxiliary)
            }
        }
        let level: NSWindow.Level = floatOnTop ? .floating : .normal
        if previous?.floatOnTop != floatOnTop, window.level != level { window.level = level }
        guard previous?.style != style else { return }
        switch style {
        case .glass:
            window.isOpaque = false
            window.backgroundColor = .clear
            applyCornerRadius(window, 16)
        case .classic:
            window.isOpaque = true
            window.backgroundColor = NSColor(calibratedWhite: 0.58, alpha: 1)
            applyCornerRadius(window, 6)
        case .strip:
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            applyCornerRadius(window, 6)
        case .modern:
            window.isOpaque = true
            window.backgroundColor = NSColor(calibratedWhite: 0.90, alpha: 1)
            applyCornerRadius(window, 10)
        }
        window.invalidateShadow()
    }

    private func applyCornerRadius(_ window: any PlayerWindowConfigurationTarget, _ radius: CGFloat) {
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = radius
        window.contentView?.layer?.masksToBounds = true
        if let themeFrame = window.contentView?.superview {
            themeFrame.wantsLayer = true
            themeFrame.layer?.cornerRadius = radius
            themeFrame.layer?.masksToBounds = true
        }
    }

    public func configureMain(
        _ window: any PlayerWindowConfigurationTarget,
        autosaveName: String,
        isMain: Bool,
        sidebarShown: Bool,
        rightPaneShown: Bool,
        prepareChrome: () -> Void
    ) {
        let configuration = MainConfiguration(
            autosaveName: autosaveName,
            isMain: isMain,
            minimumSize: isMain ? NSSize(
                width: PlayerWindowLayoutPolicy.minimumWidth(
                    sidebarShown: sidebarShown, rightPaneShown: rightPaneShown
                ),
                height: PlayerWindowMetrics.mainMinimumHeight
            ) : nil
        )
        let previous = self.window === window ? mainConfiguration : nil
        guard previous != configuration else { return }
        self.window = window
        // Record intent before setters that may trigger another layout/update.
        mainConfiguration = configuration
        let identifier = NSUserInterfaceItemIdentifier(isMain ? "songbird-main" : autosaveName)
        if window.identifier != identifier { window.identifier = identifier }
        if previous?.autosaveName != autosaveName, window.frameAutosaveName != autosaveName {
            window.setFrameAutosaveName(autosaveName)
        }
        if previous == nil {
            if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
            if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
            if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
            // NavigationStack owns the native toolbar. Never remove it in an
            // AppKit update; implicit Back is suppressed at the route boundary.
            if window.isMovableByWindowBackground { window.isMovableByWindowBackground = false }
            if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
            prepareChrome()
            if let content = window.contentView {
                if !content.wantsLayer { content.wantsLayer = true }
                if content.layer?.borderWidth != 0 { content.layer?.borderWidth = 0 }
            }
        }
        if let minimumSize = configuration.minimumSize,
           previous?.minimumSize != minimumSize, window.contentMinSize != minimumSize {
            window.contentMinSize = minimumSize
        }
    }
}
