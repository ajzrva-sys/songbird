import Foundation
import SwiftData

/// Persistent love/favorite state kept separate from track ratings.
/// Mirrors the `AlbumFavorite` pattern: a standalone model that records
/// whether a track is loved, independent of its numeric star rating.
@Model
public final class TrackFavorite {
    @Attribute(.unique) public var trackID: UUID
    public var dateAdded: Date

    public init(trackID: UUID, dateAdded: Date = Date()) {
        self.trackID = trackID
        self.dateAdded = dateAdded
    }
}
