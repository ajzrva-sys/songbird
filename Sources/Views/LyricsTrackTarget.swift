import Foundation

struct LyricsTrackTarget: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let artist: String
    let path: String

    @MainActor
    init(track: Track) {
        id = track.id
        title = track.title
        artist = track.artist
        path = track.path
    }
}
