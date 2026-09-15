import Combine
import Foundation

@MainActor
final class AudioDiagnosticsPoller: ObservableObject {
    @Published private(set) var snapshot = AudioDiagnosticsSnapshot.zero
    private var timer: Timer?
    private(set) var pollCount: UInt64 = 0
    var isPolling: Bool { timer != nil }

    func start(
        interval: TimeInterval = 0.25,
        provider: @escaping @MainActor @Sendable () -> AudioDiagnosticsSnapshot
    ) {
        stop()
        poll(provider)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll(provider)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll(_ provider: @MainActor @Sendable () -> AudioDiagnosticsSnapshot) {
        snapshot = provider()
        pollCount += 1
    }

    isolated deinit {
        timer?.invalidate()
    }
}
