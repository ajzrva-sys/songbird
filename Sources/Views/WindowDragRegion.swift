import AppKit
import SwiftUI

/// An explicit window-drag surface for custom titlebar chrome.
///
/// Keeping this behavior local prevents splitters and other content controls
/// from being mistaken for draggable window background.
struct WindowDragRegion: NSViewRepresentable {
    var isEnabled = true

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.isEnabled = isEnabled
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.isEnabled = isEnabled
    }

    final class DragView: NSView {
        var isEnabled = true

        override var mouseDownCanMoveWindow: Bool { isEnabled }

        override func hitTest(_ point: NSPoint) -> NSView? {
            isEnabled ? super.hitTest(point) : nil
        }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            window?.performDrag(with: event)
        }
    }
}
