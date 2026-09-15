import Foundation
import Testing
@testable import SongbirdLib

private actor DropImportResolutionGate {
    private let started: AsyncStream<Void>.Continuation
    private var waiter: CheckedContinuation<DropImportResolution, Never>?

    init(started: AsyncStream<Void>.Continuation) {
        self.started = started
    }

    func wait() async -> DropImportResolution {
        await withCheckedContinuation { continuation in
            waiter = continuation
            started.yield()
        }
    }

    func release(_ batch: DropImportResolution) {
        waiter?.resume(returning: batch)
        waiter = nil
    }
}

struct DropImportLifecycleTests {
    @Test("Cancelled drop resolution cannot publish or import after resuming")
    @MainActor
    func cancelledResolutionHasNoSideEffects() async {
        let started = AsyncStream<Void>.makeStream()
        var startedIterator = started.stream.makeAsyncIterator()
        let gate = DropImportResolutionGate(started: started.continuation)
        var skippedNotices: [Int] = []
        var importedBatches: [[URL]] = []
        let task = Task { @MainActor in
            await DropImportOperation.run(
                resolve: { await gate.wait() },
                showSkippedNotice: { skippedNotices.append($0) },
                importURLs: { importedBatches.append($0) }
            )
        }

        _ = await startedIterator.next()
        task.cancel()
        await gate.release(DropImportResolution(
            urls: [URL(fileURLWithPath: "/Cancelled/Track.flac")],
            unsupportedCount: 1
        ))
        await task.value
        started.continuation.finish()

        #expect(skippedNotices.isEmpty)
        #expect(importedBatches.isEmpty)
    }

    @Test("Active drop resolution publishes and imports exactly once")
    @MainActor
    func activeResolutionPublishesAndImports() async {
        let urls = [
            URL(fileURLWithPath: "/Active/First.flac"),
            URL(fileURLWithPath: "/Active/Second.flac"),
        ]
        var skippedNotices: [Int] = []
        var importedBatches: [[URL]] = []

        await DropImportOperation.run(
            resolve: { DropImportResolution(urls: urls, unsupportedCount: 2) },
            showSkippedNotice: { skippedNotices.append($0) },
            importURLs: { importedBatches.append($0) }
        )

        #expect(skippedNotices == [2])
        #expect(importedBatches == [urls])
    }
}
