import Foundation

/// Testable interaction rules shared by Songbird's native-backed player sliders.
public enum PlayerSliderBehavior {
    public static let seekIncrement: TimeInterval = 5
    public static let volumeIncrement = 0.05
    public static let compactPlayerThreshold = PlayerWindowMetrics.compactPlayerThreshold

    public static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    public static func seekStep(duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0.01 }
        return min(1, seekIncrement / duration)
    }

    public static func adjusted(
        _ value: Double,
        direction: FloatingPointSign,
        step: Double
    ) -> Double {
        clamp(value + (direction == .plus ? step : -step))
    }

    public static func usesCompactPlayer(width: Double, isEditingLayout: Bool) -> Bool {
        width < compactPlayerThreshold && isEditingLayout == false
    }
}
