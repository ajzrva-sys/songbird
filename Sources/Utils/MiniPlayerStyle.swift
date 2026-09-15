import Foundation

/// Visual style for the floating Mini Player window.
public enum MiniPlayerStyle: String, CaseIterable, Identifiable, Sendable {
    case modern
    case classic
    /// A single-row, space-efficient player inspired by Songbird's original chrome.
    case strip
    /// Behind-window vibrancy, like Apple Music’s floating mini player.
    case glass

    public static let storageKey = "miniPlayer.style"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .modern: return "Modern"
        case .classic: return "Classic"
        case .strip: return "Strip"
        case .glass: return "Glass"
        }
    }

    public var usesTransparentWindow: Bool {
        self == .glass
    }
}
