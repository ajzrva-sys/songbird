import Foundation
import SwiftData

@Model
public final class Artist {
    public var id: UUID
    public var name: String
    public var dateAdded: Date

    public var tracks: [Track] = []

    public init(name: String) {
        self.id = UUID()
        self.name = name
        self.dateAdded = Date()
    }
}
