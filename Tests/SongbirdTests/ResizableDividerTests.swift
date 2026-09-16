import AppKit
import SwiftUI
import XCTest
@testable import SongbirdLib

final class ResizableDividerTests: XCTestCase {
    @MainActor
    func testFixedPaneWidthsRenderWithoutAnAdjustableRange() {
        for minimum in [180.0, 200.0] {
            render(minimum: minimum, maximum: minimum)
        }
    }

    @MainActor
    func testAvailableWidthSmallerThanKeyboardStepRenders() {
        for remaining in [0.5, 1.0, 5.0, 9.99, 10.0, 12.0] {
            render(minimum: 180, maximum: 180 + remaining)
        }
    }

    @MainActor
    func testRestoringSidebarCanConstrainBothDividersWithoutChangingPreferredWidths() {
        _ = NSApplication.shared
        var preferredWidth = 260.0
        let binding = Binding(get: { preferredWidth }, set: { preferredWidth = $0 })
        let host = NSHostingView(rootView: ResizableDivider(
            width: binding, minimum: 180, maximum: 420, direction: .expandsRight
        ))
        host.frame = NSRect(x: 0, y: 0, width: 8, height: 400)
        for maximum in [420.0, 185.0, 180.0, 192.0, 420.0] {
            host.rootView = ResizableDivider(
                width: binding, minimum: 180, maximum: maximum, direction: .expandsRight
            )
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(host.fittingSize.height.isFinite)
            XCTAssertEqual(preferredWidth, 260, "Layout must not overwrite the saved preference")
        }
    }

    @MainActor
    private func render(minimum: Double, maximum: Double) {
        _ = NSApplication.shared
        let divider = ResizableDivider(
            width: .constant(260), minimum: minimum, maximum: maximum, direction: .expandsLeft
        )
        // Evaluate the production body too: the reported trap occurs while the
        // native Slider is constructed, before pointer or keyboard interaction.
        _ = divider.body
        let host = NSHostingView(rootView: divider)
        host.frame = NSRect(x: 0, y: 0, width: 8, height: 400)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(host.fittingSize.height.isFinite)
    }
}
