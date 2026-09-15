import Foundation
import Combine

public enum PlaybackStatus: Equatable {
    case stopped
    case playing
    case paused
    case loading
}

/// Low-frequency playback state for views that need play/pause semantics but
/// must not redraw for the engine's ten-times-per-second position clock.
@MainActor
public final class PlaybackActivity: ObservableObject {
    @Published public fileprivate(set) var status: PlaybackStatus = .stopped

    public init() {}

    func update(_ status: PlaybackStatus) {
        guard self.status != status else { return }
        self.status = status
    }
}

/// High-frequency time state observed only by seek/time leaf views.
@MainActor
public final class PlaybackClock: ObservableObject {
    @Published public private(set) var position: TimeInterval = 0
    @Published public private(set) var duration: TimeInterval = 0

    public init() {}

    func update(position: TimeInterval? = nil, duration: TimeInterval? = nil) {
        if let position, self.position != position {
            self.position = position
        }
        if let duration, self.duration != duration {
            self.duration = duration
        }
    }
}

/// Volume-only presentation state for controls that should not observe playback ticks.
@MainActor
public final class PlaybackVolumeState: ObservableObject {
    @Published public private(set) var volume: Double = 1

    public init() {}

    func update(_ volume: Double) {
        guard self.volume != volume else { return }
        self.volume = volume
    }
}

/// Low-frequency player presentation used by transport, artwork, and row highlighting.
@MainActor
public final class PlaybackPresentationState: ObservableObject {
    @Published public private(set) var status: PlaybackStatus = .stopped
    @Published public private(set) var currentTrack: Track?
    @Published public private(set) var currentTrackID: UUID?

    public init() {}

    func update(status: PlaybackStatus? = nil, currentTrack: Track? = nil, clearsTrack: Bool = false) {
        if let status, self.status != status {
            self.status = status
        }
        if clearsTrack {
            if self.currentTrack != nil || currentTrackID != nil {
                self.currentTrack = nil
                currentTrackID = nil
            }
        } else if let currentTrack, currentTrackID != currentTrack.id {
            self.currentTrack = currentTrack
            currentTrackID = currentTrack.id
        }
    }
}
