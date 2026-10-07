import Foundation
import Testing
@testable import SongbirdLib

@Suite("Activity termination", .serialized)
struct LibraryActivityTerminationTests {
    @MainActor
    @Test("A completed flush prepares playback and replies once across repeated quit requests")
    func successfulFlush() async {
        let gate = LibraryActivityTerminationGate()
        var prepares = 0
        var flushes = 0
        var replies = 0
        await withCheckedContinuation { continuation in
            #expect(gate.begin(timeout: .seconds(1), prepare: { prepares += 1 }, flush: {
                flushes += 1
            }, reply: {
                replies += 1
                continuation.resume()
            }))
            #expect(!gate.begin(prepare: { prepares += 1 }, flush: { flushes += 1 }, reply: { replies += 1 }))
        }
        #expect(gate.isFinished)
        #expect(prepares == 1 && flushes == 1 && replies == 1)
        #expect(!gate.begin(prepare: { prepares += 1 }, flush: {}, reply: { replies += 1 }))
        #expect(prepares == 1 && replies == 1)
    }

    @MainActor
    @Test("An unresponsive flush cannot block quit and a late completion cannot reply twice")
    func boundedFlush() async {
        let gate = LibraryActivityTerminationGate()
        var prepares = 0
        var replies = 0
        var releaseFlush: CheckedContinuation<Void, Never>?
        await withCheckedContinuation { continuation in
            #expect(gate.begin(timeout: .milliseconds(30), prepare: { prepares += 1 }, flush: {
                await withCheckedContinuation { releaseFlush = $0 }
            }, reply: {
                replies += 1
                continuation.resume()
            }))
        }
        #expect(gate.isFinished)
        #expect(prepares == 1 && replies == 1)
        releaseFlush?.resume()
        await Task.yield()
        #expect(replies == 1)
    }
}
