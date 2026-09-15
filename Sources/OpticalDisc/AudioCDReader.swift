import AVFoundation
import Foundation
import OpticalDiscBridge

public protocol AudioCDSectorReading: Sendable {
    func readSectors(deviceID: String, firstSector: Int64, count: Int) throws -> Data
}

public struct SystemAudioCDSectorReader: AudioCDSectorReading {
    public init() {}

    public func readSectors(deviceID: String, firstSector: Int64, count: Int) throws -> Data {
        let capacity = count * Int(SB_CDDA_SECTOR_BYTES)
        var bytes = Data(count: capacity)
        var bytesRead: Int32 = 0
        let status = bytes.withUnsafeMutableBytes { rawBuffer in
            deviceID.withCString { name in
                SBOpticalDiscReadCDDASectors(
                    name,
                    firstSector,
                    Int32(count),
                    rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                    Int32(capacity),
                    &bytesRead
                )
            }
        }
        guard status == 0 else { throw AudioCDReaderError.deviceRead(status) }
        bytes.count = Int(bytesRead)
        return bytes
    }
}

public enum AudioCDReaderError: Error, LocalizedError, Equatable {
    case invalidTrackRange
    case deviceRead(Int32)
    case malformedSectorData
    case conversionFailed
    case closed

    public var errorDescription: String? {
        switch self {
        case .invalidTrackRange: "The CD track has an invalid sector range."
        case .deviceRead(let code): "The optical drive could not read the disc (error \(code))."
        case .malformedSectorData: "The drive returned malformed CD audio data."
        case .conversionFailed: "The CD audio could not be converted for playback."
        case .closed: "The CD audio reader is closed."
        }
    }
}

/// Buffered CDDA source. All drive I/O and conversion runs on a worker thread;
/// the render callback consumes only the lock-free ring buffer.
public final class AudioCDReader: @unchecked Sendable, RenderPCMSource {
    public let cdSource: AudioCDSource
    public let ringBuffer: RingBuffer
    public let sampleRate: Double
    public let duration: TimeInterval
    public let totalOutputFrames: Int64
    let minimumPlaybackFrames: Int

    private let sectorReader: any AudioCDSectorReading
    private let converter: AVAudioConverter
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let lifecycle = AtomicUInt32(PCMSourceState.idle.rawValue)
    private let decodeLatencyMetrics = AtomicLatencyMetrics()
    private let conversionLatencyMetrics = AtomicLatencyMetrics()
    private var decodeThread: Thread?
    private var nextSector: Int64
    private var pendingSamples: [Float] = []
    private var pendingFrameOffset = 0
    private var publishedError: String?

    var source: AudioSource { .audioCD(cdSource) }
    public var state: PCMSourceState {
        PCMSourceState(rawValue: lifecycle.loadAcquire()) ?? .failed
    }
    public var decodeError: String? { state == .failed ? publishedError : nil }
    var decodeLatency: AudioLatencyStatistics { decodeLatencyMetrics.snapshot() }
    var conversionLatency: AudioLatencyStatistics { conversionLatencyMetrics.snapshot() }

    public init(
        source: AudioCDSource,
        sampleRate: Double,
        bufferSeconds: Double = 16,
        sectorReader: any AudioCDSectorReading = SystemAudioCDSectorReader()
    ) throws {
        guard source.startSector >= 0, source.endSector > source.startSector else {
            throw AudioCDReaderError.invalidTrackRange
        }
        guard let input = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 2,
            interleaved: false
        ), let output = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ), let converter = AVAudioConverter(from: input, to: output) else {
            throw AudioCDReaderError.conversionFailed
        }
        self.cdSource = source
        self.sampleRate = sampleRate
        self.duration = source.duration
        self.totalOutputFrames = Int64((source.duration * sampleRate).rounded())
        self.minimumPlaybackFrames = Int(sampleRate * 4)
        self.ringBuffer = RingBuffer(channels: 2, seconds: bufferSeconds, sampleRate: sampleRate)
        self.sectorReader = sectorReader
        self.inputFormat = input
        self.outputFormat = output
        self.converter = converter
        self.nextSector = source.startSector
    }

    deinit { stop() }

    public func prime(minimumFrames: Int = 8_192) throws {
        while ringBuffer.availableFrames < minimumFrames && state != .eof {
            try decodeOnce()
        }
    }

    public func start() {
        guard state == .idle else { return }
        lifecycle.storeRelease(PCMSourceState.decoding.rawValue)
        let thread = Thread { [weak self] in self?.decodeLoop() }
        thread.name = "Songbird CDDA reader"
        thread.qualityOfService = .userInitiated
        decodeThread = thread
        thread.start()
    }

    public func stop() {
        lifecycle.storeRelease(PCMSourceState.cancelled.rawValue)
        decodeThread?.cancel()
        // A raw-drive ioctl cannot be interrupted reliably. The worker's
        // closure retains this reader until that call returns, so cancellation
        // can safely be nonblocking and must never stall the main actor.
        decodeThread = nil
    }

    public func seek(to seconds: TimeInterval) throws {
        guard decodeThread == nil else { throw AudioCDReaderError.closed }
        let clamped = min(max(seconds, 0), duration)
        nextSector = min(
            cdSource.endSector,
            cdSource.startSector + Int64((clamped * 75).rounded(.down))
        )
        converter.reset()
        pendingSamples.removeAll(keepingCapacity: true)
        pendingFrameOffset = 0
        publishedError = nil
        lifecycle.storeRelease(PCMSourceState.idle.rawValue)
    }

    private func decodeLoop() {
        while state == .decoding && !Thread.current.isCancelled {
            if ringBuffer.availableFrames > Int(sampleRate * 14) {
                Thread.sleep(forTimeInterval: 0.002)
                continue
            }
            do {
                try decodeOnce()
            } catch {
                publishedError = error.localizedDescription
                lifecycle.storeRelease(PCMSourceState.failed.rawValue)
            }
        }
    }

    private func decodeOnce() throws {
        if pendingFrameOffset * 2 >= pendingSamples.count, nextSector < cdSource.endSector {
            try refillPendingSamples()
        }

        let outputCapacity: AVAudioFrameCount = 4_096
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            throw AudioCDReaderError.conversionFailed
        }
        let conversionStarted = DispatchTime.now().uptimeNanoseconds
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { requested, inputStatus in
            let available = self.pendingSamples.count / 2 - self.pendingFrameOffset
            guard available > 0 else {
                inputStatus.pointee = self.nextSector >= self.cdSource.endSector
                    ? .endOfStream
                    : .noDataNow
                return nil
            }
            let frameCount = min(Int(max(requested, 1)), available)
            guard let input = AVAudioPCMBuffer(
                pcmFormat: self.inputFormat,
                frameCapacity: AVAudioFrameCount(frameCount)
            ), let channels = input.floatChannelData else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            input.frameLength = AVAudioFrameCount(frameCount)
            for frame in 0..<frameCount {
                let sourceFrame = self.pendingFrameOffset + frame
                channels[0][frame] = self.pendingSamples[sourceFrame * 2]
                channels[1][frame] = self.pendingSamples[sourceFrame * 2 + 1]
            }
            self.pendingFrameOffset += frameCount
            inputStatus.pointee = .haveData
            return input
        }
        conversionLatencyMetrics.record(
            nanoseconds: DispatchTime.now().uptimeNanoseconds - conversionStarted
        )
        guard status != .error, conversionError == nil, let outputChannels = output.floatChannelData else {
            throw conversionError ?? AudioCDReaderError.conversionFailed
        }

        let outputFrames = Int(output.frameLength)
        if outputFrames > 0 {
            var stereo = [Float](repeating: 0, count: outputFrames * 2)
            for frame in 0..<outputFrames {
                stereo[frame * 2] = outputChannels[0][frame]
                stereo[frame * 2 + 1] = outputChannels[1][frame]
            }
            stereo.withUnsafeBufferPointer { pointer in
                var offset = 0
                while offset < outputFrames && runningOrPriming {
                    let written = ringBuffer.write(
                        pointer.baseAddress!.advanced(by: offset * 2),
                        frames: outputFrames - offset
                    )
                    if written == 0 {
                        Thread.sleep(forTimeInterval: 0.001)
                    } else {
                        offset += written
                    }
                }
            }
        }

        if status == .endOfStream
            || (outputFrames == 0
                && nextSector >= cdSource.endSector
                && pendingFrameOffset * 2 >= pendingSamples.count) {
            lifecycle.storeRelease(PCMSourceState.eof.rawValue)
        }
    }

    private func refillPendingSamples() throws {
        // Optical drives have comparatively high command and seek latency. Read
        // two seconds per request so the producer stays comfortably ahead of
        // real-time playback even when a USB drive briefly stalls.
        let sectorCount = Int(min(150, cdSource.endSector - nextSector))
        let readStarted = DispatchTime.now().uptimeNanoseconds
        let data = try readWithRetry(firstSector: nextSector, count: sectorCount)
        decodeLatencyMetrics.record(
            nanoseconds: DispatchTime.now().uptimeNanoseconds - readStarted
        )
        guard data.count == sectorCount * Int(SB_CDDA_SECTOR_BYTES), data.count.isMultiple(of: 4) else {
            throw AudioCDReaderError.malformedSectorData
        }
        nextSector += Int64(sectorCount)

        let inputFrames = data.count / 4
        pendingSamples = [Float](repeating: 0, count: inputFrames * 2)
        pendingFrameOffset = 0
        data.withUnsafeBytes { bytes in
            let samples = bytes.bindMemory(to: UInt8.self)
            for frame in 0..<inputFrames {
                let offset = frame * 4
                let left = Int16(bitPattern: UInt16(samples[offset]) | UInt16(samples[offset + 1]) << 8)
                let right = Int16(bitPattern: UInt16(samples[offset + 2]) | UInt16(samples[offset + 3]) << 8)
                pendingSamples[frame * 2] = Float(left) / 32_768
                pendingSamples[frame * 2 + 1] = Float(right) / 32_768
            }
        }
    }

    private func readWithRetry(firstSector: Int64, count: Int) throws -> Data {
        var lastError: Error = AudioCDReaderError.deviceRead(-1)
        for attempt in 0..<3 {
            if Thread.current.isCancelled { throw CancellationError() }
            do {
                return try sectorReader.readSectors(
                    deviceID: cdSource.deviceID,
                    firstSector: firstSector,
                    count: count
                )
            } catch {
                lastError = error
                if attempt < 2 { Thread.sleep(forTimeInterval: 0.01 * Double(attempt + 1)) }
            }
        }
        throw lastError
    }

    private var runningOrPriming: Bool {
        state == .decoding || decodeThread == nil
    }

    func resetDiagnostics() {
        decodeLatencyMetrics.reset()
        conversionLatencyMetrics.reset()
    }
}
