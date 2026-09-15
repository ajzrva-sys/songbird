import Foundation

public enum GenreMetadata {
    public static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isMissing(_ value: String) -> Bool {
        normalized(value).isEmpty
    }
}
