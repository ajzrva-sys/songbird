import SwiftUI

/// Centralized metrics for the service pane (sidebar) so density changes
/// are testable and reversible in one place.
public struct ServicePaneMetrics: Equatable {
    /// Horizontal content inset from the sidebar edge.
    public let horizontalInset: CGFloat
    /// Leading inset for section labels (e.g., "PLAYLISTS").
    public let sectionLabelLeadingInset: CGFloat
    /// Vertical spacing between sidebar sections.
    public let sectionSpacing: CGFloat
    /// Vertical padding per navigation row.
    public let rowVerticalPadding: CGFloat
    /// Width reserved for the icon column.
    public let iconColumnWidth: CGFloat
    /// Corner radius for the selection highlight.
    public let selectionCornerRadius: CGFloat
    /// Horizontal padding inside navigation rows.
    public let rowHorizontalPadding: CGFloat

    /// Standard metrics matching the current default.
    public static let standard = ServicePaneMetrics(
        horizontalInset: 8,
        sectionLabelLeadingInset: 24,
        sectionSpacing: 8,
        rowVerticalPadding: 6,
        iconColumnWidth: 16,
        selectionCornerRadius: 6,
        rowHorizontalPadding: 8
    )

    public static let storageKey = "servicePane.metrics"

    public static func resolved(from raw: String?) -> ServicePaneMetrics {
        .standard
    }
}
