import Foundation
import XCTest
@testable import SongbirdLib

final class AudioAtomicTests: XCTestCase {
    func testAtomicScalarPublication() {
        let integer = AtomicUInt64()
        let boolean = AtomicBool()
        let pointer = AtomicPointer()
        let float = AtomicFloat()

        integer.storeRelease(UInt64.max - 7)
        boolean.storeRelease(true)
        pointer.storeRelease(0x1234)
        float.storeRelaxed(0.625)

        XCTAssertEqual(integer.loadAcquire(), UInt64.max - 7)
        XCTAssertTrue(boolean.loadAcquire())
        XCTAssertEqual(pointer.loadAcquire(), 0x1234)
        XCTAssertEqual(float.loadRelaxed(), 0.625)
    }

    func testAtomicAddMaxAndDoublePublication() {
        let integer = AtomicUInt64(10)
        XCTAssertEqual(integer.fetchAddRelaxed(7), 10)
        XCTAssertEqual(integer.loadAcquire(), 17)
        integer.maxRelaxed(12)
        XCTAssertEqual(integer.loadAcquire(), 17)
        integer.maxRelaxed(42)
        XCTAssertEqual(integer.loadAcquire(), 42)

        let double = AtomicDouble()
        double.storeRelease(192_000.25)
        XCTAssertEqual(double.loadAcquire(), 192_000.25)
    }

    func testLatencyMetricsAggregateAndReset() {
        let metrics = AtomicLatencyMetrics()
        metrics.record(nanoseconds: 1_000_000)
        metrics.record(nanoseconds: 3_000_000)
        let snapshot = metrics.snapshot()
        XCTAssertEqual(snapshot.latestMilliseconds, 3)
        XCTAssertEqual(snapshot.averageMilliseconds, 2)
        XCTAssertEqual(snapshot.maximumMilliseconds, 3)
        XCTAssertEqual(snapshot.ewmaMilliseconds, 1.25)
        XCTAssertEqual(snapshot.sampleCount, 2)

        metrics.reset()
        XCTAssertEqual(metrics.snapshot(), .zero)
    }

    func testSPSCQueueIsBoundedAndOrdered() {
        let queue = AtomicMessageQueue(capacity: 4)
        for value in 0..<4 {
            XCTAssertTrue(queue.push(AtomicMessage(
                type: 1,
                pointer: UInt(value),
                value: UInt64(value)
            )))
        }
        XCTAssertFalse(queue.push(AtomicMessage(type: 1, pointer: 99, value: 99)))
        for value in 0..<4 {
            XCTAssertEqual(
                queue.pop(),
                AtomicMessage(type: 1, pointer: UInt(value), value: UInt64(value))
            )
        }
        XCTAssertNil(queue.pop())
    }

    func testSPSCQueueConcurrentProducerConsumer() {
        let queue = AtomicMessageQueue(capacity: 257)
        let count = 100_000
        let finished = expectation(description: "producer and consumer")
        finished.expectedFulfillmentCount = 2
        let failure = AtomicBool()

        DispatchQueue.global(qos: .userInitiated).async {
            for value in 0..<count {
                let message = AtomicMessage(type: 3, pointer: UInt(value), value: UInt64(value))
                while !queue.push(message) { Thread.sleep(forTimeInterval: 0) }
            }
            finished.fulfill()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            for expected in 0..<count {
                var message: AtomicMessage?
                while message == nil {
                    message = queue.pop()
                    if message == nil { Thread.sleep(forTimeInterval: 0) }
                }
                if message?.value != UInt64(expected) {
                    failure.storeRelease(true)
                }
            }
            finished.fulfill()
        }

        wait(for: [finished], timeout: 10)
        XCTAssertFalse(failure.loadAcquire())
        XCTAssertEqual(queue.count, 0)
    }

    func testRingBufferConcurrentProducerConsumerAcrossManyWraps() {
        let ring = RingBuffer(channels: 2, seconds: 0.001, sampleRate: 48_000)
        let frameCount = 250_000
        let finished = expectation(description: "ring producer and consumer")
        finished.expectedFulfillmentCount = 2
        let failure = AtomicBool()

        DispatchQueue.global(qos: .userInitiated).async {
            var frame = 0
            while frame < frameCount {
                let value = Float(frame % 1_009)
                let samples = [value, -value]
                let written = samples.withUnsafeBufferPointer {
                    ring.write($0.baseAddress!, frames: 1)
                }
                if written == 1 {
                    frame += 1
                } else {
                    Thread.sleep(forTimeInterval: 0)
                }
            }
            finished.fulfill()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var frame = 0
            var samples = [Float](repeating: 0, count: 2)
            while frame < frameCount {
                if ring.read(into: &samples, maxFrames: 1) == 1 {
                    let expected = Float(frame % 1_009)
                    if samples[0] != expected || samples[1] != -expected {
                        failure.storeRelease(true)
                    }
                    frame += 1
                } else {
                    Thread.sleep(forTimeInterval: 0)
                }
            }
            finished.fulfill()
        }

        wait(for: [finished], timeout: 20)
        XCTAssertFalse(failure.loadAcquire())
        XCTAssertEqual(ring.totalSamplesRead, UInt64(frameCount * 2))
    }

    func testSaturatedKernelCommandQueueReclaimsEverySnapshotOnce() {
        let kernel = RenderKernel()
        var weakSnapshots: [WeakSnapshot] = []
        for _ in 0..<256 {
            let snapshot = RenderSnapshot(command: .stop)
            weakSnapshots.append(WeakSnapshot(snapshot))
            XCTAssertTrue(kernel.enqueue(snapshot))
        }
        XCTAssertFalse(kernel.enqueue(RenderSnapshot(command: .stop)))

        kernel.processCommandsWhileStopped()
        var acknowledgements = 0
        while let message = kernel.popEvent() {
            guard RenderEvent(rawValue: message.type) == .commandConsumed,
                  let raw = UnsafeRawPointer(bitPattern: message.pointer) else { continue }
            Unmanaged<RenderSnapshot>.fromOpaque(raw).release()
            acknowledgements += 1
        }
        XCTAssertEqual(acknowledgements, 256)
        XCTAssertTrue(weakSnapshots.allSatisfy { $0.value == nil })
    }
}

private final class WeakSnapshot {
    weak var value: RenderSnapshot?
    init(_ value: RenderSnapshot) { self.value = value }
}
