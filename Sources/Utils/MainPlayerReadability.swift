import Foundation

/// Main-window content sizing; mini-player presets retain their stored geometry.
enum MainPlayerReadability {
    static let heightKey = "nowPlaying.mainFaceplateHeight"
    static let titleSize = 13.0
    static let subtitleSize = 11.0
    static let timeSize = 11.0
    static let seekHeight = 20.0
    static let minimumHeight = 72.0
    static let heightRange: ClosedRange<Double> = minimumHeight...112

    static func resolvedHeight(_ saved: Double) -> Double {
        max(minimumHeight, saved.isFinite ? saved : minimumHeight)
    }

    static func savedHeight(main: Double, legacy: Double) -> Double {
        main.isFinite && main > 0 ? main : legacy
    }
}
