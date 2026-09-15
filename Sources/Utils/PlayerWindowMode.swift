import AppKit

/// Coordinates main ↔ mini player window visibility (Apple Music–style replace).
/// Call from the main thread / MainActor.
@MainActor
public enum PlayerWindowMode {
    public static let miniModeKey = "player.miniMode"

    public static var isMiniMode: Bool {
        get { UserDefaults.standard.bool(forKey: miniModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: miniModeKey) }
    }

    public static func mainWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.identifier?.rawValue == "songbird-main" }
    }

    public static func miniWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.identifier?.rawValue == "mini-player" }
    }

    public static func enterMiniMode() {
        isMiniMode = true
        for window in mainWindows() {
            window.orderOut(nil)
        }
        // Ensure mini is key once it exists (may still be opening).
        Task { @MainActor in
            await Task.yield()
            if let mini = miniWindows().first {
                mini.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public static func enterFullMode(closeMini: Bool = true) {
        isMiniMode = false
        let mains = mainWindows()
        for window in mains {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
        if closeMini {
            for window in miniWindows() {
                window.close()
            }
            for window in NSApp.windows where window.title == "Mini Player" {
                window.close()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
