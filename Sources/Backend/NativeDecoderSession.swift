import AVFoundation
import FLACBridge
import Foundation
import os

private struct DecoderReadFailure: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

private struct DecoderConversionInputState: Sendable {
    var readFailure: DecoderReadFailure?
    var sourceReadNanoseconds: UInt64 = 0
}

/// Decodes one local file into stereo Float32 PCM at the engine sample rate.
public final class NativeDecoderSession: @unchecked Sendable, RenderPCMSource {
    public let url: URL
    public let ringBuffer: RingBuffer
    public let sampleRate: Double
    private var sourceSampleRate: Double = 0
    private var decoderFormat: AVAudioFormat!
    private var outputFormat: AVAudioFormat!
    private var converter: AVAudioConverter!
    public let duration: TimeInterval
    public let totalOutputFrames: Int64
    let minimumPlaybackFrames = 0

    private var file: AVAudioFile?
    private var flac: OpaquePointer?
    private var decodeThread: Thread?
    private let lifecycle = AtomicUInt32(PCMSourceState.idle.rawValue)
    private let decodeLatencyMetrics = AtomicLatencyMetrics()
    private let conversionLatencyMetrics = AtomicLatencyMetrics()
    private var publishedError: String?

    public var state: PCMSourceState {
        PCMSourceState(rawValue: lifecycle.loadAcquire()) ?? .failed
    }
    public var reachedEOF: Bool { state == .eof }
    public var decodeError: String? {
        state == .failed ? publishedError : nil
    }
    var decodeLatency: AudioLatencyStatistics { decodeLatencyMetrics.snapshot() }
    var conversionLatency: AudioLatencyStatistics { conversionLatencyMetrics.snapshot() }
    var source: AudioSource { .file(url) }

    public init(url: URL, sampleRate: Double, bufferSeconds: Double = 16) throws {
        self.url = url
        self.sampleRate = sampleRate
        self.ringBuffer = RingBuffer(channels: 2, seconds: bufferSeconds, sampleRate: sampleRate)

        do {
            let sourceFormat: AVAudioFormat
            let sourceRate: Double
            let sourceFrames: Int64
            if url.pathExtension.lowercased() == "flac" {
                guard let handle = url.withUnsafeFileSystemRepresentation({
                    $0.flatMap(SBFLACOpen)
                }) else {
                    throw NativeAudioError.openFailed(url.lastPathComponent)
                }
                flac = handle
                sourceRate = Double(SBFLACSampleRate(handle))
                sourceFrames = Int64(SBFLACTotalFrames(handle))
                guard let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: sourceRate,
                    channels: 2,
                    interleaved: false
                ) else {
                    throw NativeAudioError.unsupportedFormat(url.lastPathComponent)
                }
                sourceFormat = format
            } else {
                let opened = try AVAudioFile(
                    forReading: url,
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                )
                file = opened
                sourceFormat = opened.processingFormat
                sourceRate = opened.fileFormat.sampleRate
                sourceFrames = opened.length
            }
            self.sourceSampleRate = sourceRate
            guard sourceFormat.channelCount == 1 || sourceFormat.channelCount == 2 else {
                throw NativeAudioError.unsupportedFormat(
                    "\(url.lastPathComponent) has \(sourceFormat.channelCount) channels"
                )
            }
            self.duration = sourceRate > 0 ? Double(sourceFrames) / sourceRate : 0
            self.totalOutputFrames = Int64((duration * sampleRate).rounded())

            guard let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 2,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
                throw NativeAudioError.unsupportedFormat(url.lastPathComponent)
            }
            self.decoderFormat = sourceFormat
            self.outputFormat = outputFormat
            self.converter = converter
        } catch {
            self.file = nil
            if let flac {
                SBFLACClose(flac)
                self.flac = nil
            }
            throw error
        }
    }

    deinit { stop() }

    public func prime(minimumFrames: Int = 8_192) throws {
        while ringBuffer.availableFrames < minimumFrames && !reachedEOF {
            try decodeOnce()
        }
    }

    public func start() {
        guard state == .idle else { return }
        lifecycle.storeRelease(PCMSourceState.decoding.rawValue)
        let thread = Thread { [weak self] in self?.decodeLoop() }
        thread.name = "Songbird native decoder"
        thread.qualityOfService = .userInitiated
        decodeThread = thread
        thread.start()
    }

    public func stop() {
        lifecycle.storeRelease(PCMSourceState.cancelled.rawValue)
        decodeThread?.cancel()
        if let thread = decodeThread, thread !== Thread.current {
            let deadline = Date().addingTimeInterval(1)
            while thread.isExecuting && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
        decodeThread = nil
        file = nil
        if let flac {
            SBFLACClose(flac)
            self.flac = nil
        }
    }

    public func seek(to seconds: TimeInterval) throws {
        let target = Int64(max(0, seconds) * sourceSampleRate)
        if let flac {
            guard SBFLACSeek(flac, UInt64(target)) != 0 else {
                throw NativeAudioError.operationFailed("seek FLAC", -1)
            }
        } else if let file {
            file.framePosition = target
        } else {
            throw NativeAudioError.closed
        }
        converter.reset()
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
        guard (file != nil || flac != nil), let decoderFormat else {
            throw NativeAudioError.closed
        }
        let requestedFrames = 4_096
        let outputCapacity = AVAudioFrameCount(requestedFrames)
        guard let output = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else {
            throw NativeAudioError.operationFailed("allocate conversion buffer", -1)
        }

        let inputState = OSAllocatedUnfairLock(initialState: DecoderConversionInputState())
        var conversionError: NSError?
        let conversionStarted = DispatchTime.now().uptimeNanoseconds
        let status = converter.convert(to: output, error: &conversionError) { requested, inputStatus in
            let framesToRead = min(max(requested, 1), AVAudioFrameCount(4_096))
            guard let input = AVAudioPCMBuffer(
                pcmFormat: decoderFormat,
                frameCapacity: framesToRead
            ) else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            do {
                let readStarted = DispatchTime.now().uptimeNanoseconds
                try self.readInput(into: input, maximumFrames: framesToRead)
                let elapsed = DispatchTime.now().uptimeNanoseconds - readStarted
                inputState.withLock { state in
                    state.sourceReadNanoseconds += elapsed
                }
            } catch {
                inputState.withLock { state in
                    if state.readFailure == nil {
                        state.readFailure = DecoderReadFailure(
                            message: error.localizedDescription
                        )
                    }
                }
                inputStatus.pointee = .endOfStream
                return nil
            }
            if input.frameLength == 0 {
                self.lifecycle.storeRelease(PCMSourceState.eof.rawValue)
                inputStatus.pointee = .endOfStream
                return nil
            }
            inputStatus.pointee = .haveData
            return input
        }
        let conversionElapsed = DispatchTime.now().uptimeNanoseconds - conversionStarted
        let (readFailure, sourceReadNanoseconds) = inputState.withLock { state in
            (state.readFailure, state.sourceReadNanoseconds)
        }
        decodeLatencyMetrics.record(nanoseconds: sourceReadNanoseconds)
        conversionLatencyMetrics.record(
            nanoseconds: conversionElapsed > sourceReadNanoseconds
                ? conversionElapsed - sourceReadNanoseconds
                : 0
        )
        if let readFailure { throw readFailure }
        if status == .error && output.frameLength == 0 {
            throw conversionError ?? NativeAudioError.operationFailed("convert PCM", -1)
        }

        let outputFrames = Int(output.frameLength)
        if outputFrames == 0, state == .eof { return }
        guard outputFrames > 0, let channels = output.floatChannelData else { return }
        var stereoSamples = [Float](repeating: 0, count: outputFrames * 2)
        for frame in 0..<outputFrames {
            stereoSamples[frame * 2] = channels[0][frame]
            stereoSamples[frame * 2 + 1] = channels[1][frame]
        }
        stereoSamples.withUnsafeBufferPointer { pointer in
            var offset = 0
            let frameCount = outputFrames
            while offset < frameCount && runningOrPriming {
                let written = ringBuffer.write(
                    pointer.baseAddress!.advanced(by: offset * 2),
                    frames: frameCount - offset
                )
                if written == 0 {
                    Thread.sleep(forTimeInterval: 0.001)
                } else {
                    offset += written
                }
            }
        }
    }

    private func readInput(
        into buffer: AVAudioPCMBuffer,
        maximumFrames: AVAudioFrameCount
    ) throws {
        if let flac {
            var interleaved = [Float](repeating: 0, count: Int(maximumFrames) * 2)
            let frames = interleaved.withUnsafeMutableBufferPointer {
                SBFLACReadStereoFloat(flac, $0.baseAddress, Int(maximumFrames))
            }
            buffer.frameLength = AVAudioFrameCount(frames)
            if frames == 0 {
                if SBFLACAtEnd(flac) != 0 {
                    lifecycle.storeRelease(PCMSourceState.eof.rawValue)
                }
                return
            }
            guard let channels = buffer.floatChannelData else {
                throw NativeAudioError.operationFailed("read FLAC PCM", -1)
            }
            for frame in 0..<frames {
                channels[0][frame] = interleaved[frame * 2]
                channels[1][frame] = interleaved[frame * 2 + 1]
            }
            return
        }
        guard let file else { throw NativeAudioError.closed }
        if file.framePosition >= file.length {
            lifecycle.storeRelease(PCMSourceState.eof.rawValue)
            buffer.frameLength = 0
            return
        }
        try file.read(into: buffer, frameCount: maximumFrames)
    }

    private var runningOrPriming: Bool {
        state == .decoding || decodeThread == nil
    }

    func resetDiagnostics() {
        decodeLatencyMetrics.reset()
        conversionLatencyMetrics.reset()
    }
}

public enum NativeAudioError: LocalizedError {
    case openFailed(String)
    case operationFailed(String, OSStatus)
    case unsupportedFormat(String)
    case closed

    public var errorDescription: String? {
        switch self {
        case .openFailed(let name): return "Could not open \(name)."
        case .operationFailed(let operation, let status):
            return "\(operation) failed (AudioToolbox error \(status))."
        case .unsupportedFormat(let name): return "Unsupported audio format: \(name)"
        case .closed: return "The audio decoder is closed."
        }
    }
}
