import AppKit
import SongbirdDockIconSupport

@MainActor
public enum SongbirdDockIconManager {
    private static var imageCache: [SongbirdDockIconChoice: NSImage] = [:]

    public static func apply(for theme: SongbirdThemeID) {
        guard let choice = SongbirdDockIconPreference.choice(for: theme) else {
            NSApp.applicationIconImage = nil
            SongbirdDockIconPreference.clearActiveChoice()
            notifyDockPlugin()
            return
        }
        guard let image = image(for: choice) else { return }
        SongbirdDockIconPreference.setActiveChoice(choice)
        NSApp.applicationIconImage = image
        notifyDockPlugin()
    }

    public static func image(for choice: SongbirdDockIconChoice) -> NSImage? {
        if let cachedImage = imageCache[choice] {
            return cachedImage
        }
        guard let url = resourceURL(for: choice), let sourceImage = NSImage(contentsOf: url) else {
            return nil
        }
        let image = SongbirdDockIconArtwork.dockReadyImage(
            from: sourceImage,
            resourceName: choice.resourceName
        )
        imageCache[choice] = image
        return image
    }

    private static func notifyDockPlugin() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        DistributedNotificationCenter.default().postNotificationName(
            SongbirdDockIconArtwork.changeNotificationName(
                bundleIdentifier: bundleIdentifier
            ),
            object: bundleIdentifier,
            userInfo: nil,
            options: [.deliverImmediately]
        )
    }

    private static func resourceURL(for choice: SongbirdDockIconChoice) -> URL? {
        if let packagedURL = Bundle.main.url(
            forResource: choice.resourceName,
            withExtension: "png"
        ) {
            return packagedURL
        }
        return Bundle.module.url(
            forResource: choice.resourceName,
            withExtension: "png",
            subdirectory: "Resources"
        ) ?? Bundle.module.url(
            forResource: choice.resourceName,
            withExtension: "png"
        )
    }
}
