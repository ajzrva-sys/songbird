import Foundation
import SwiftUI

public enum ServicePaneSection: String, CaseIterable, Identifiable {
    case library = "Library"
    case playlists = "Playlists"
    case queue = "Queue"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .library: return "music.note.list"
        case .playlists: return "list.bullet"
        case .queue: return "text.alignleft"
        }
    }
}

public enum ServicePaneDestination: Hashable {
    case allTracks
    case artists
    case albums
    case genres
    case recentlyAdded
    case topPlayed
    case healthDashboard
    case ghostTracks
    case unavailableTracks
    case duplicateTracks
    case missingGenre
    case missingArtwork
    case unknownArtist
    case unknownAlbum
    case missingTrackNumber
    case inconsistentArtists
    case inconsistentAlbums
    case emptyTitles
    case missingYear
    case lowBitrate
    case inconsistentGenres
    case filledComments
    case inconsistentAlbumArtists
    case queue
    case playlist(UUID)
    case audioCD(DiscIdentifier)
}
