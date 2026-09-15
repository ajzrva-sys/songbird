import AppKit
import Foundation

/// Reuses decoded album images across table rows, the service pane, and other
/// transient view refreshes. The cache is UI-owned and therefore main-actor
/// isolated along with AppKit image creation.
@MainActor
enum ArtworkImageCache {
    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    static func image(for track: Track) -> NSImage? {
        guard let artworkData = track.resolvedArtworkData else { return nil }
        let artworkOwnerID = track.albumRelation?.id ?? track.id
        let key = "\(artworkOwnerID.uuidString)-\(artworkData.count)" as NSString
        if let cached = images.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(data: artworkData) else { return nil }
        images.setObject(image, forKey: key, cost: artworkData.count)
        return image
    }
}
