import AppKit
import SongbirdDockIconSupport

@objc(SongbirdDockTilePlugin)
@MainActor
public final class SongbirdDockTilePlugin: NSObject, @MainActor NSDockTilePlugIn {
    private var dockTile: NSDockTile?
    private var notificationObserver: NSObjectProtocol?

    public override init() {
        super.init()
    }

    isolated deinit {
        removeNotificationObserver()
    }

    public func setDockTile(_ dockTile: NSDockTile?) {
        self.dockTile = dockTile
        removeNotificationObserver()

        guard dockTile != nil,
              let appIdentity = containingAppIdentity()
        else { return }

        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: SongbirdDockIconArtwork.changeNotificationName(
                bundleIdentifier: appIdentity.bundleIdentifier
            ),
            object: appIdentity.bundleIdentifier,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateDockTile(using: appIdentity)
            }
        }
        updateDockTile(using: appIdentity)
    }

    private func updateDockTile(using appIdentity: AppIdentity) {
        guard let dockTile,
              let defaults = UserDefaults(suiteName: appIdentity.bundleIdentifier)
        else { return }

        let storedName = defaults.string(
            forKey: SongbirdDockIconArtwork.activeResourceStorageKey
        )
        guard let resourceName = SongbirdDockIconArtwork.validatedResourceName(storedName) else {
            dockTile.contentView = nil
            dockTile.display()
            return
        }
        guard let url = appIdentity.bundle.url(
            forResource: resourceName,
            withExtension: "png"
        ), let sourceImage = NSImage(contentsOf: url) else { return }

        let imageView = NSImageView(
            frame: NSRect(origin: .zero, size: dockTile.size)
        )
        imageView.image = SongbirdDockIconArtwork.dockReadyImage(
            from: sourceImage,
            resourceName: resourceName
        )
        imageView.imageScaling = .scaleAxesIndependently
        dockTile.contentView = imageView
        dockTile.display()
    }

    private func containingAppIdentity() -> AppIdentity? {
        let pluginBundle = Bundle(for: SongbirdDockTilePlugin.self)
        let appURL = pluginBundle.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard appURL.pathExtension == "app",
              let appBundle = Bundle(url: appURL),
              let bundleIdentifier = appBundle.bundleIdentifier
        else { return nil }
        return AppIdentity(bundle: appBundle, bundleIdentifier: bundleIdentifier)
    }

    private func removeNotificationObserver() {
        guard let notificationObserver else { return }
        DistributedNotificationCenter.default().removeObserver(notificationObserver)
        self.notificationObserver = nil
    }

    private struct AppIdentity {
        let bundle: Bundle
        let bundleIdentifier: String
    }
}
