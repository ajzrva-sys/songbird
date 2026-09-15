import Foundation

enum AlbumGridSettings {
    static let artworkSizeKey = "albumGrid.artworkSize"
    static let gridSpacingKey = "albumGrid.gridSpacing"

    static let defaultArtworkSize: Double = 160
    static let artworkSizeRange: ClosedRange<Double> = 120...240
    static let artworkSizeStep: Double = 20
    static let defaultGridSpacing: Double = 16
    static let gridSpacingRange: ClosedRange<Double> = 8...48
    static let gridSpacingStep: Double = 4

    static func normalizedArtworkSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultArtworkSize }

        let clamped = min(max(value, artworkSizeRange.lowerBound), artworkSizeRange.upperBound)
        let steps = ((clamped - artworkSizeRange.lowerBound) / artworkSizeStep).rounded()
        return artworkSizeRange.lowerBound + (steps * artworkSizeStep)
    }

    static func normalizedGridSpacing(_ value: Double) -> Double {
        guard value.isFinite else { return defaultGridSpacing }

        let clamped = min(max(value, gridSpacingRange.lowerBound), gridSpacingRange.upperBound)
        let steps = ((clamped - gridSpacingRange.lowerBound) / gridSpacingStep).rounded()
        return gridSpacingRange.lowerBound + (steps * gridSpacingStep)
    }
}

enum AlbumGridExampleSelection {
    static let count = 2

    static func choose<ID: Hashable>(from ids: [ID]) -> [ID] {
        var generator = SystemRandomNumberGenerator()
        return choose(from: ids, using: &generator)
    }

    static func choose<ID: Hashable, Generator: RandomNumberGenerator>(
        from ids: [ID],
        using generator: inout Generator
    ) -> [ID] {
        var seen: Set<ID> = []
        let uniqueIDs = ids.filter { seen.insert($0).inserted }
        return Array(uniqueIDs.shuffled(using: &generator).prefix(count))
    }
}
