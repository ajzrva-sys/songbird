import SwiftUI

/// AppKit click-count recognition for collection items that select on the
/// first click and activate on a double-click, matching native Mac lists.
struct MacClickActivationView: NSViewRepresentable {
    let singleClick: @MainActor (NSEvent.ModifierFlags) -> Void
    let doubleClick: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(singleClick: singleClick, doubleClick: doubleClick)
    }

    func makeNSView(context: Context) -> NSView {
        ClickView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.singleClick = singleClick
        context.coordinator.doubleClick = doubleClick
        (nsView as? ClickView)?.coordinator = context.coordinator
    }

    private final class ClickView: NSView {
        weak var coordinator: Coordinator?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func mouseDown(with event: NSEvent) {
            coordinator?.handleClick(
                count: event.clickCount,
                modifiers: event.modifierFlags
            )
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var singleClick: @MainActor (NSEvent.ModifierFlags) -> Void
        var doubleClick: @MainActor () -> Void

        init(
            singleClick: @escaping @MainActor (NSEvent.ModifierFlags) -> Void,
            doubleClick: @escaping @MainActor () -> Void
        ) {
            self.singleClick = singleClick
            self.doubleClick = doubleClick
        }

        func handleClick(count: Int, modifiers: NSEvent.ModifierFlags) {
            if count == 2 {
                doubleClick()
                return
            }
            if count == 1 {
                singleClick(modifiers)
            }
        }
    }
}
