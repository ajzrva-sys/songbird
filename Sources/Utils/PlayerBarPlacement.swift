import Foundation

/// Where the full player chrome (transport + faceplate) sits in the main content column.
public enum PlayerBarPlacement: String, CaseIterable, Identifiable, Sendable {
    case top
    case bottom

    public static let storageKey = "playerBar.placement"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }
}
