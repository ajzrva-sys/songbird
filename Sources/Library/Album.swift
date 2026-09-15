import Foundation
import SwiftData

@Model
public final class Album {
    public var id: UUID
    public var title: String
    public var artist: String
    public var year: Int
    public var artworkData: Data?
    public var dateAdded: Date

    public var tracks: [Track] = []

    public init(title: String, artist: String = "Unknown Artist", year: Int = 0) {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.year = year
        self.dateAdded = Date()
    }
}
