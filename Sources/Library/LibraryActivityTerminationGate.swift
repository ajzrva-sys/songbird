import Foundation

/// Holds AppKit termination only while history can be flushed within a small
/// budget. Independent tasks avoid waiting for an unresponsive I/O task to join.
@MainActor
public final class LibraryActivityTerminationGate {
    public private(set) var isFinished = false
    private var isWaiting = false
    private var flushTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    public init() {}

    @discardableResult
    public func begin(
        timeout: Duration = .seconds(2),
        prepare: () -> Void,
        flush: @escaping @MainActor () async -> Void,
        reply: @escaping @MainActor () -> Void
    ) -> Bool {
        guard !isWaiting, !isFinished else { return false }
        isWaiting = true
        prepare()
        flushTask = Task { @MainActor [weak self] in
            await flush()
            self?.finish(reply: reply)
        }
        timeoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.finish(reply: reply)
        }
        return true
    }

    private func finish(reply: () -> Void) {
        guard isWaiting, !isFinished else { return }
        isFinished = true
        isWaiting = false
        flushTask?.cancel()
        timeoutTask?.cancel()
        flushTask = nil
        timeoutTask = nil
        reply()
    }
}
