import Foundation

/// Controls the visual density and artwork visibility of the track table.
public enum TrackTablePresentation: String, CaseIterable, Sendable {
    /// Classic Songbird density: no per-row artwork, ~20pt rows.
    case classic
    /// Comfortable density: 24pt artwork gutter, current row insets.
    case comfortable

    public static let storageKey = "trackTable.presentation"

    /// Resolve a stored value, defaulting to Classic for invalid or missing values.
    public static func resolved(from raw: String?) -> TrackTablePresentation {
        raw.flatMap(TrackTablePresentation.init(rawValue:)) ?? .classic
    }

    /// Whether to show per-row artwork in the track table.
    public var showsArtwork: Bool {
        switch self {
        case .classic: return false
        case .comfortable: return true
        }
    }

    /// Width of the artwork gutter (0 for classic).
    public var artworkGutterWidth: CGFloat {
        switch self {
        case .classic: return 0
        case .comfortable: return 36
        }
    }

    /// Vertical padding per row.
    public var rowVerticalInset: CGFloat {
        switch self {
        case .classic: return 2
        case .comfortable: return 4
        }
    }

    /// Column header height.
    public var headerHeight: CGFloat {
        switch self {
        case .classic: return 20
        case .comfortable: return 22
        }
    }

    /// Column header font size.
    public var headerFontSize: CGFloat {
        switch self {
        case .classic: return 10
        case .comfortable: return 11
        }
    }

    /// Display name for the picker.
    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .comfortable: return "Comfortable"
        }
    }
}
