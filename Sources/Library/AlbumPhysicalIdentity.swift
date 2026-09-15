import Foundation

/// A filesystem-backed identity for one physical album edition.
///
/// Album artist tags are intentionally excluded for named albums. Compilation
/// tracks often omit Album Artist and would otherwise create one Album per
/// performer. The containing folder keeps separate editions distinct.
public struct AlbumPhysicalIdentity: Hashable, Sendable {
    public let normalizedTitle: String
    public let standardizedFolderPath: String
    public let folderName: String
    public let fallbackArtist: String?

    public init(title: String, path: String, performer: String = "") {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaningfulTitle = Self.isMeaningfulAlbumTitle(trimmedTitle)
        // Library paths are standardized when imported. Keep identity
        // derivation lexical: URL(fileURLWithPath:) may call lstat to infer a
        // directory, which turns an O(n) catalog pass into thousands of slow
        // network-volume round trips.
        let folderPath = (path as NSString).deletingLastPathComponent

        normalizedTitle = meaningfulTitle
            ? Self.normalized(trimmedTitle)
            : Self.normalized("Unknown Album")
        standardizedFolderPath = folderPath
        folderName = (folderPath as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        fallbackArtist = meaningfulTitle ? nil : Self.normalizedArtist(performer)
    }

    public var stableKey: String {
        [normalizedTitle, standardizedFolderPath, fallbackArtist ?? ""]
            .joined(separator: "\u{1f}")
    }

    public static func isMeaningfulAlbumTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && normalized(trimmed) != normalized("Unknown Album")
    }

    public static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func normalizedArtist(_ artist: String) -> String? {
        let value = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, normalized(value) != normalized("Unknown Artist") else {
            return nil
        }
        return normalized(value)
    }
}
