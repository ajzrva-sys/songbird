import Foundation
import SwiftData

/// Persistent favorite state kept separate from album metadata and track ratings.
@Model
public final class AlbumFavorite {
    @Attribute(.unique) public var albumID: UUID
    public var dateAdded: Date

    public init(albumID: UUID, dateAdded: Date = Date()) {
        self.albumID = albumID
        self.dateAdded = dateAdded
    }
}
