import Foundation

/// UserDefaults keys for library metadata preferences.
public enum LibrarySettings {
    public static let writeTagsToFilesKey = "library.writeTagsToFiles"

    public static var writeTagsToFiles: Bool {
        get { UserDefaults.standard.bool(forKey: writeTagsToFilesKey) }
        set { UserDefaults.standard.set(newValue, forKey: writeTagsToFilesKey) }
    }
}
