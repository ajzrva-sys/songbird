import CoreGraphics
import Foundation

/// Image bytes can change without changing an album's persistent identity.
/// A nil set means that save evidence could not identify the affected albums.
struct ArtworkInvalidation: Sendable {
    static let notificationName = Notification.Name("Songbird.albumArtworkInvalidated")
    let albumIDs: Set<UUID>?

    init(albumIDs: Set<UUID>?) {
        self.albumIDs = albumIDs
    }

    init?(notification: Notification) {
        guard notification.name == Self.notificationName,
              let event = notification.userInfo?["invalidation"] as? Self else { return nil }
        self = event
    }

    func affects(_ reference: ArtworkReference?) -> Bool {
        guard case .album(let id, _) = reference else { return false }
        return albumIDs?.contains(id) ?? true
    }

    @MainActor
    func post() {
        NotificationCenter.default.post(
            name: Self.notificationName, object: nil, userInfo: ["invalidation": self]
        )
    }
}

/// View-local state keeps an album event from reloading unrelated visible cells.
/// Generations also reject old results before SwiftUI cancels the previous task.
struct ArtworkThumbnailLoadState {
    private(set) var generation: UInt64 = 0
    private(set) var image: CGImage?

    mutating func invalidate(_ event: ArtworkInvalidation, reference: ArtworkReference?) {
        guard event.affects(reference) else { return }
        generation &+= 1
        image = nil
    }

    mutating func publish(_ image: CGImage?, generation: UInt64) {
        guard generation == self.generation else { return }
        self.image = image
    }

    mutating func expire(reference: ArtworkReference?, at now: DiscogsFetchStamp?) {
        guard let reference, !reference.isAvailable(at: now) else { return }
        generation &+= 1
        image = nil
    }
}
