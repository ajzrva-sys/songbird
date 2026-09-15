import SwiftUI

/// Deterministic player-layout presets.
public enum NowPlayingLayoutPreset: String, CaseIterable, Identifiable {
    case classic
    case balanced
    case compact

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .balanced: return "Balanced"
        case .compact: return "Compact"
        }
    }

    public struct Configuration: Equatable {
        public let faceplateWidth: Double
        public let faceplateHeight: Double
        public let leadingGap: Double
        public let trailingGap: Double
        public let barPadding: Double
        public let buttonSpacing: Double
        public let controlsSpacing: Double
    }

    public var configuration: Configuration {
        switch self {
        case .classic:
            return Configuration(
                faceplateWidth: 360, faceplateHeight: 44,
                leadingGap: 8, trailingGap: 4,
                barPadding: 10, buttonSpacing: 2, controlsSpacing: 8
            )
        case .balanced:
            return Configuration(
                faceplateWidth: 420, faceplateHeight: 48,
                leadingGap: 12, trailingGap: 6,
                barPadding: 12, buttonSpacing: 3, controlsSpacing: 10
            )
        case .compact:
            return Configuration(
                faceplateWidth: 300, faceplateHeight: 40,
                leadingGap: 6, trailingGap: 3,
                barPadding: 8, buttonSpacing: 1, controlsSpacing: 6
            )
        }
    }

    /// Resolve which preset matches the given values, or nil if custom.
    public static func match(
        faceplateWidth: Double,
        faceplateHeight: Double,
        leadingGap: Double,
        trailingGap: Double,
        barPadding: Double,
        buttonSpacing: Double,
        controlsSpacing: Double
    ) -> NowPlayingLayoutPreset? {
        let target = Configuration(
            faceplateWidth: faceplateWidth, faceplateHeight: faceplateHeight,
            leadingGap: leadingGap, trailingGap: trailingGap,
            barPadding: barPadding, buttonSpacing: buttonSpacing,
            controlsSpacing: controlsSpacing
        )
        for preset in NowPlayingLayoutPreset.allCases {
            if preset.configuration == target { return preset }
        }
        return nil
    }
}

/// Persisted layout knobs for the now-playing chrome (Layout Studio).
enum NowPlayingLayoutSettings {
    static let faceplateWidthKey = "nowPlaying.faceplateWidth"
    static let faceplateHeightKey = "nowPlaying.faceplateHeight"
    static let leadingGapKey = "nowPlaying.leadingGap"
    static let trailingGapKey = "nowPlaying.trailingGap"
    // Read once when migrating the old combined gap controls.
    static let sectionSpacingKey = "nowPlaying.sectionSpacing"
    static let sideSpacerKey = "nowPlaying.sideSpacer"
    static let gapMigrationKey = "nowPlaying.independentGapsMigrated"
    static let barPaddingKey = "nowPlaying.barPadding"
    static let buttonSpacingKey = "nowPlaying.buttonSpacing"
    static let controlsSpacingKey = "nowPlaying.controlsSpacing"

    static let defaultFaceplateWidth: Double = 420
    static let defaultFaceplateHeight: Double = 48
    static let defaultLeadingGap: Double = 12
    static let defaultTrailingGap: Double = 6
    static let defaultBarPadding: Double = 12
    static let defaultButtonSpacing: Double = 3
    static let defaultControlsSpacing: Double = 10

    static let faceplateWidthRange: ClosedRange<Double> = 280...560
    static let faceplateHeightRange: ClosedRange<Double> = 36...72
    static let gapRange: ClosedRange<Double> = 0...64
    static let barPaddingRange: ClosedRange<Double> = 4...28
    static let buttonSpacingRange: ClosedRange<Double> = 0...20
    static let controlsSpacingRange: ClosedRange<Double> = 2...32

    static let widthStep: Double = 1
    static let heightStep: Double = 1
    static let spacingStep: Double = 1
    static let buttonSpacingStep: Double = 1
    static let controlsSpacingStep: Double = 1

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    static func reset(
        faceplateWidth: inout Double,
        faceplateHeight: inout Double,
        leadingGap: inout Double,
        trailingGap: inout Double,
        barPadding: inout Double,
        buttonSpacing: inout Double,
        controlsSpacing: inout Double
    ) {
        faceplateWidth = defaultFaceplateWidth
        faceplateHeight = defaultFaceplateHeight
        leadingGap = defaultLeadingGap
        trailingGap = defaultTrailingGap
        barPadding = defaultBarPadding
        buttonSpacing = defaultButtonSpacing
        controlsSpacing = defaultControlsSpacing
    }
}

enum LayoutStudioZone: String, CaseIterable, Identifiable {
    case faceplate
    case leadingGap
    case trailingGap
    case buttonSpacing
    case controlsSpacing
    case barPadding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .faceplate: return "Now Playing Box"
        case .leadingGap: return "Controls Gap"
        case .trailingGap: return "Trailing Gap"
        case .buttonSpacing: return "Play Button Spacing"
        case .controlsSpacing: return "Controls Group Spacing"
        case .barPadding: return "Bar Padding"
        }
    }

    var detail: String {
        switch self {
        case .faceplate: return "Width and height of the LCD / faceplate."
        case .leadingGap: return "Space between the controls and the now-playing box."
        case .trailingGap: return "Space between the now-playing box and the outer padding."
        case .buttonSpacing: return "Gap between previous, play, and next."
        case .controlsSpacing: return "Gap between transport, volume, and shuffle/repeat."
        case .barPadding: return "Outer padding around the chrome."
        }
    }
}
