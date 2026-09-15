import Foundation

/// Value-only qualification state. The engine feeds it monotonic uptime while audio is playing;
/// media position is deliberately irrelevant so seeking cannot qualify a play.
struct PlayQualificationTracker: Equatable {
    private(set) var trackID: UUID?
    private(set) var accumulatedPlayback: TimeInterval = 0
    private(set) var hasQualified = false
    private var lastPlayingUptime: TimeInterval?
    private var threshold: TimeInterval = 30

    mutating func begin(
        trackID: UUID,
        duration: TimeInterval,
        uptime: TimeInterval
    ) {
        self.trackID = trackID
        accumulatedPlayback = 0
        hasQualified = false
        threshold = Self.threshold(for: duration)
        lastPlayingUptime = uptime
    }

    mutating func pause(uptime: TimeInterval) {
        _ = advance(uptime: uptime)
        lastPlayingUptime = nil
    }

    mutating func resume(uptime: TimeInterval) {
        guard trackID != nil, !hasQualified else { return }
        lastPlayingUptime = uptime
    }

    mutating func reset() {
        self = Self()
    }

    /// Returns true exactly once for a playback attempt.
    mutating func advance(uptime: TimeInterval) -> Bool {
        guard !hasQualified, let previous = lastPlayingUptime else { return false }
        accumulatedPlayback += max(0, uptime - previous)
        lastPlayingUptime = uptime
        guard accumulatedPlayback >= threshold else { return false }
        hasQualified = true
        lastPlayingUptime = nil
        return true
    }

    static func threshold(for duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite, duration > 0 else { return 30 }
        return duration < 60 ? duration / 2 : 30
    }
}
