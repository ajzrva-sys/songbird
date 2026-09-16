import CoreGraphics

public enum PlayerWindowMetrics {
    public static let mainMinimumWidth: CGFloat = 760
    public static let mainMinimumHeight: CGFloat = 520
    public static let libraryColumnMinimumWidth: CGFloat = 560
    public static let compactPlayerThreshold = 820.0
    public static let sidebarMinimumWidth: CGFloat = 180
    public static let sidebarMaximumWidth: CGFloat = 420
    public static let sidebarDefaultWidth: CGFloat = 260
    public static let nowPlayingPaneMinimumWidth: CGFloat = 200
    public static let nowPlayingPaneMaximumWidth: CGFloat = 360
    public static let nowPlayingPaneDefaultWidth: CGFloat = 260
}

public enum PlayerWindowLayoutPolicy {
    public struct PaneWidths: Equatable {
        public let sidebar: CGFloat
        public let rightPane: CGFloat
    }

    public static func minimumWidth(sidebarShown: Bool, rightPaneShown: Bool) -> CGFloat {
        switch (sidebarShown, rightPaneShown) {
        case (true, true): 956
        case (false, true): 768
        case (true, false), (false, false): 760
        }
    }

    public static func clampedSidebarWidth(_ width: CGFloat, availableWidth: CGFloat) -> CGFloat {
        min(
            max(width, PlayerWindowMetrics.sidebarMinimumWidth),
            min(
                PlayerWindowMetrics.sidebarMaximumWidth,
                max(PlayerWindowMetrics.sidebarMinimumWidth,
                    availableWidth - PlayerWindowMetrics.libraryColumnMinimumWidth - 8)
            )
        )
    }

    public static func clampedRightPaneWidth(_ width: CGFloat, availableWidth: CGFloat) -> CGFloat {
        min(
            max(width, PlayerWindowMetrics.nowPlayingPaneMinimumWidth),
            min(
                PlayerWindowMetrics.nowPlayingPaneMaximumWidth,
                max(PlayerWindowMetrics.nowPlayingPaneMinimumWidth,
                    availableWidth - PlayerWindowMetrics.libraryColumnMinimumWidth - 8)
            )
        )
    }

    public static func paneWidths(
        totalWidth: CGFloat,
        sidebarShown: Bool,
        rightPaneShown: Bool,
        desiredSidebar: CGFloat,
        desiredRightPane: CGFloat
    ) -> PaneWidths {
        let dividerTotal: CGFloat = (sidebarShown ? 8 : 0) + (rightPaneShown ? 8 : 0)
        var budget = max(0, totalWidth - PlayerWindowMetrics.libraryColumnMinimumWidth - dividerTotal)
        var sidebar: CGFloat = 0
        var right: CGFloat = 0
        if sidebarShown {
            sidebar = min(PlayerWindowMetrics.sidebarMinimumWidth, budget)
            budget -= sidebar
        }
        if rightPaneShown {
            right = min(PlayerWindowMetrics.nowPlayingPaneMinimumWidth, budget)
            budget -= right
        }
        if sidebarShown, budget > 0 {
            let addition = min(
                max(0, min(desiredSidebar, PlayerWindowMetrics.sidebarMaximumWidth) - sidebar),
                budget
            )
            sidebar += addition
            budget -= addition
        }
        if rightPaneShown, budget > 0 {
            right += min(
                max(0, min(desiredRightPane, PlayerWindowMetrics.nowPlayingPaneMaximumWidth) - right),
                budget
            )
        }
        return PaneWidths(sidebar: sidebar, rightPane: right)
    }

    public static func sidebarArtworkSide(sidebarWidth: CGFloat, windowHeight: CGFloat) -> CGFloat? {
        // Leave a separate, padded footer below at least 300 points of navigation.
        let remaining = windowHeight - 52 - 300 - 25
        let side = min(sidebarWidth - 24, 160, remaining)
        return side >= 120 ? side : nil
    }
}
