import AppKit
import SwiftUI

/// Owns the first-run importer as a standard resizable macOS panel.
@MainActor
public enum ImportSetupWindowPresenter {
    private static var coordinator: ImportSetupWindowCoordinator?

    public static func show() {
        if let panel = coordinator?.panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let coordinator = ImportSetupWindowCoordinator()
        coordinator.onWindowClose = { [weak coordinator] in
            guard let coordinator else { return }
            windowDidClose(coordinator)
        }
        let rootView = ImportSetupView {
            close()
        }
        .modelContainer(MediaLibrary.shared.container)

        let hostingController = NSHostingController(rootView: rootView)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.title = "Songbird Setup"
        panel.setContentSize(NSSize(width: 560, height: 520))
        panel.minSize = NSSize(width: 480, height: 440)
        panel.maxSize = NSSize(width: 900, height: 760)
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = true
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .modalPanel

        coordinator.panel = panel
        coordinator.parentWindow = PlayerWindowMode.mainWindows().first ?? NSApp.mainWindow
        panel.delegate = coordinator
        self.coordinator = coordinator

        if let parent = coordinator.parentWindow {
            let origin = NSPoint(
                x: parent.frame.midX - panel.frame.width / 2,
                y: parent.frame.midY - panel.frame.height / 2
            )
            panel.setFrameOrigin(origin)
            parent.addChildWindow(panel, ordered: .above)
        } else {
            panel.center()
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public static func close() {
        guard let coordinator else { return }
        self.coordinator = nil
        coordinator.dismiss()
    }

    private static func windowDidClose(_ closedCoordinator: ImportSetupWindowCoordinator) {
        guard coordinator === closedCoordinator else { return }
        coordinator = nil
    }
}

@MainActor
final class ImportSetupWindowCoordinator: NSObject, NSWindowDelegate {
    var panel: NSPanel?
    weak var parentWindow: NSWindow?
    var onWindowClose: (() -> Void)?

    func dismiss() {
        guard let panel else { return }
        detachPanel()
        panel.delegate = nil
        self.panel = nil
        onWindowClose = nil

        // Avoid tearing down the hosting view from inside the SwiftUI button
        // action that requested dismissal.
        panel.orderOut(nil)
        DispatchQueue.main.async {
            panel.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        detachPanel()
        panel = nil
        let callback = onWindowClose
        onWindowClose = nil
        callback?()
    }

    private func detachPanel() {
        if let parentWindow, let panel, panel.parent === parentWindow {
            parentWindow.removeChildWindow(panel)
        }
        parentWindow = nil
    }
}
