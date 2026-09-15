import Foundation

actor ControlledThumbnailLoader {
    private var pending: [CheckedContinuation<Data, Never>] = []
    private(set) var count = 0
    private(set) var cancelledCount = 0
    func load() async -> Data {
        count += 1
        let data = await withCheckedContinuation { pending.append($0) }
        if Task.isCancelled { cancelledCount += 1 }
        return data
    }
    func complete(_ data: Data) {
        let continuations = pending
        pending.removeAll()
        for continuation in continuations { continuation.resume(returning: data) }
    }
}
