import Foundation

@MainActor
final class ViewTaskSlot {
    struct Lease: Equatable {
        fileprivate let generation: Int
    }

    private var task: Task<Void, Never>?
    private var generation = 0
    private var acceptsNewTasks = true

    var isRunning: Bool { task != nil }

    func lease() -> Lease? {
        acceptsNewTasks ? Lease(generation: generation) : nil
    }

    func activate() {
        guard acceptsNewTasks == false else { return }
        generation &+= 1
        acceptsNewTasks = true
    }

    @discardableResult
    func start(
        lease: Lease? = nil,
        _ operation: @escaping @MainActor () async -> Void
    ) -> Bool {
        guard acceptsNewTasks else { return false }
        if let lease, lease.generation != generation { return false }
        cancel()
        let activeGeneration = generation
        task = Task { @MainActor [weak self] in
            await operation()
            guard let self, generation == activeGeneration else { return }
            task = nil
        }
        return true
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
    }

    func invalidate() {
        acceptsNewTasks = false
        cancel()
    }

    isolated deinit {
        task?.cancel()
    }
}
