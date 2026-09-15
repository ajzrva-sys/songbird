import SwiftUI

/// Confines the 10 Hz playback clock invalidation to the seek/time subtree.
struct PlaybackClockReader<Content: View>: View {
    @EnvironmentObject private var clock: PlaybackClock
    private let content: (TimeInterval, TimeInterval) -> Content

    init(@ViewBuilder content: @escaping (TimeInterval, TimeInterval) -> Content) {
        self.content = content
    }

    var body: some View {
        content(clock.position, clock.duration)
    }
}

/// Confines volume changes to the volume control subtree.
struct PlaybackVolumeReader<Content: View>: View {
    @EnvironmentObject private var volumeState: PlaybackVolumeState
    private let content: (Double) -> Content

    init(@ViewBuilder content: @escaping (Double) -> Content) {
        self.content = content
    }

    var body: some View {
        content(volumeState.volume)
    }
}

/// Keeps queue-mode and queue-mutation invalidations inside the small controls subtree.
struct PlaybackQueueReader<Content: View>: View {
    @ObservedObject var queue: PlaybackQueue
    private let content: (PlaybackQueue) -> Content

    init(queue: PlaybackQueue, @ViewBuilder content: @escaping (PlaybackQueue) -> Content) {
        self.queue = queue
        self.content = content
    }

    var body: some View {
        content(queue)
    }
}
