import Foundation

enum PrimaryTransportAction: Equatable {
    case togglePlayPause
    case playTracks([UUID])
}

enum PrimaryTransportActionResolver {
    static func resolve(
        queueHasCurrentTrack: Bool,
        queueHasUpcomingTracks: Bool,
        visibleAlbumTrackIDs: [UUID]?,
        selectedTrackID: UUID?
    ) -> PrimaryTransportAction {
        if queueHasCurrentTrack || queueHasUpcomingTracks {
            return .togglePlayPause
        }
        if let visibleAlbumTrackIDs, visibleAlbumTrackIDs.isEmpty == false {
            return .playTracks(visibleAlbumTrackIDs)
        }
        if let selectedTrackID {
            return .playTracks([selectedTrackID])
        }
        return .togglePlayPause
    }
}
