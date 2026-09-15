import Foundation

public struct PlaylistDestinationRequest: Identifiable, Equatable {
    public let id = UUID()
    public let trackIDs: [UUID]
    public let bringMainPlayerForward: Bool

    public init(trackIDs: [UUID], bringMainPlayerForward: Bool) {
        self.trackIDs = trackIDs
        self.bringMainPlayerForward = bringMainPlayerForward
    }
}

/// A short-lived request that turns the sidebar's playlist section into a
/// destination picker. Keeping the payload here lets creation and selection
/// share the same ordered track IDs without coupling the sidebar to albums.
public struct SidebarPlaylistTargetRequest: Identifiable, Equatable {
    public let id = UUID()
    public let sourceID: String
    public let sourceName: String
    public let trackIDs: [UUID]

    public init(sourceID: String, sourceName: String, trackIDs: [UUID]) {
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.trackIDs = trackIDs
    }
}
