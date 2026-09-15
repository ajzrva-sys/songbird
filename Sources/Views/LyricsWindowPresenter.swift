import AppKit
import SwiftUI

@MainActor
public enum LyricsWindowPresenter {
    private static var windows: [UUID: NSWindow] = [:]
    private static var delegates: [UUID: LyricsWindowDelegate] = [:]

    public static func show(track: Track) {
        let target = LyricsTrackTarget(track: track)
        let trackID = target.id
        if let existing = windows[trackID] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lyrics — \(target.title)"
        window.contentView = NSHostingView(rootView: LyricsPaneView(target: target))
        window.center()
        window.isReleasedWhenClosed = false
        let delegate = LyricsWindowDelegate(trackID: trackID)
        delegate.onClose = {
            windows.removeValue(forKey: trackID)
            delegates.removeValue(forKey: trackID)
        }
        window.delegate = delegate
        delegates[trackID] = delegate
        windows[trackID] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class LyricsWindowDelegate: NSObject, NSWindowDelegate {
    let trackID: UUID
    var onClose: (() -> Void)?

    init(trackID: UUID) {
        self.trackID = trackID
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
