import Foundation

/// Fixed-size single-producer, single-consumer stereo Float32 ring buffer.
public final class RingBuffer: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<Float>
    private let capacity: Int
    private let channels: Int

    private let writeIndex = AtomicUInt64()
    private let readIndex = AtomicUInt64()

    public init(channels: Int, seconds: Double, sampleRate: Double = 44100) {
        self.channels = channels
        self.capacity = Int(seconds * sampleRate) * channels
        self.storage = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    // MARK: - Capacity queries

    public var totalSamplesRead: UInt64 { readIndex.loadAcquire() }

    public var availableSamples: Int {
        let write = writeIndex.loadAcquire()
        let read = readIndex.loadAcquire()
        return write >= read ? Int(write - read) : 0
    }

    public var availableFrames: Int { availableSamples / channels }

    private var availableWrite: Int {
        capacity - availableSamples
    }

    // MARK: - Write (producer)

    @discardableResult
    public func write(_ samples: UnsafePointer<Float>, frames: Int) -> Int {
        let toWrite = min(frames * channels, availableWrite)
        guard toWrite > 0 else { return 0 }

        let write = writeIndex.loadRelaxed()
        let start = Int(write % UInt64(capacity))
        let first = min(toWrite, capacity - start)

        storage.advanced(by: start).update(from: samples, count: first)

        if first < toWrite {
            storage.update(from: samples.advanced(by: first), count: toWrite - first)
        }

        writeIndex.storeRelease(write + UInt64(toWrite))

        return toWrite / channels
    }

    // MARK: - Read (consumer)

    public func read(into destination: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        let toRead = min(maxFrames * channels, availableSamples)
        guard toRead > 0 else { return 0 }

        let read = readIndex.loadRelaxed()
        let start = Int(read % UInt64(capacity))
        let first = min(toRead, capacity - start)

        destination.update(from: storage.advanced(by: start), count: first)

        if first < toRead {
            destination.advanced(by: first)
                .update(from: storage, count: toRead - first)
        }

        readIndex.storeRelease(read + UInt64(toRead))

        return toRead / channels
    }

    /// Render-thread fast path. Returns false without modifying outputs on underflow.
    @inline(__always)
    public func readStereoFrame(left: inout Float, right: inout Float) -> Bool {
        guard channels == 2, availableSamples >= 2 else { return false }
        let read = readIndex.loadRelaxed()
        let start = Int(read % UInt64(capacity))
        left = storage[start]
        right = storage[(start + 1) % capacity]
        readIndex.storeRelease(read + 2)
        return true
    }
}
