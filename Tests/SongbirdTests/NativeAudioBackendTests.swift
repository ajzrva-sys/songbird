import AVFoundation
import XCTest
@testable import SongbirdLib

final class NativeAudioBackendTests: XCTestCase {
    func testRingBufferPreservesRemainderAcrossPartialWrites() {
        let ring = RingBuffer(channels: 2, seconds: 1, sampleRate: 4)
        let input: [Float] = [
            1, 101, 2, 102, 3, 103, 4, 104, 5, 105, 6, 106,
        ]

        let firstWrite = input.withUnsafeBufferPointer {
            ring.write($0.baseAddress!, frames: 6)
        }
        XCTAssertEqual(firstWrite, 4)

        var firstRead = [Float](repeating: 0, count: 4)
        XCTAssertEqual(ring.read(into: &firstRead, maxFrames: 2), 2)
        XCTAssertEqual(firstRead, [1, 101, 2, 102])

        let secondWrite = input.withUnsafeBufferPointer {
            ring.write($0.baseAddress!.advanced(by: firstWrite * 2), frames: 6 - firstWrite)
        }
        XCTAssertEqual(secondWrite, 2)

        var remainder = [Float](repeating: 0, count: 8)
        XCTAssertEqual(ring.read(into: &remainder, maxFrames: 4), 4)
        XCTAssertEqual(remainder, [3, 103, 4, 104, 5, 105, 6, 106])
    }

    func testStereoFrameReadReturnsFalseOnUnderflow() {
        let ring = RingBuffer(channels: 2, seconds: 1, sampleRate: 2)
        var left: Float = 7
        var right: Float = 8
        XCTAssertFalse(ring.readStereoFrame(left: &left, right: &right))
        XCTAssertEqual(left, 7)
        XCTAssertEqual(right, 8)
    }

    func testEqualPowerCrossfadeEndpointsAndMidpoint() {
        let start = EqualPowerCrossfade.gains(progress: 0, length: 100)
        XCTAssertEqual(start.active, 1, accuracy: 0.000_001)
        XCTAssertEqual(start.incoming, 0, accuracy: 0.000_001)

        let middle = EqualPowerCrossfade.gains(progress: 50, length: 100)
        XCTAssertEqual(middle.active, Float(1 / sqrt(2)), accuracy: 0.000_001)
        XCTAssertEqual(middle.incoming, Float(1 / sqrt(2)), accuracy: 0.000_001)
        XCTAssertEqual(
            middle.active * middle.active + middle.incoming * middle.incoming,
            1,
            accuracy: 0.000_001
        )

        let end = EqualPowerCrossfade.gains(progress: 100, length: 100)
        XCTAssertEqual(end.active, 0, accuracy: 0.000_001)
        XCTAssertEqual(end.incoming, 1, accuracy: 0.000_001)
    }

    func testOfflineKernelGaplessBoundaryHasNoMissingOrDuplicatedFrames() throws {
        let first = try makeStereoFloatFixture(frames: [1, 2, 3, 4])
        let second = try makeStereoFloatFixture(frames: [5, 6, 7, 8])
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let harness = try KernelHarness(urls: [first, second], crossfadeFrames: 0)
        defer { harness.reclaim() }

        let rendered = harness.render(frameCount: 8)
        assertFloatArraysEqual(
            rendered.left,
            [1, 2, 3, 4, 5, 6, 7, 8],
            accuracy: 0.000_01
        )
        XCTAssertEqual(rendered.right, rendered.left)
        let diagnostics = harness.diagnostics
        XCTAssertEqual(diagnostics.renderCallbacks, 1)
        XCTAssertEqual(diagnostics.renderedFrames, 8)
        XCTAssertEqual(diagnostics.underflowFrames, 0)
        XCTAssertEqual(diagnostics.transitionState, .gaplessHandoff)
    }

    func testOfflineKernelClampsLongCrossfadeToHalfShorterTrack() throws {
        let first = try makeStereoFloatFixture(frames: Array(repeating: 1, count: 8))
        let second = try makeStereoFloatFixture(frames: Array(repeating: 2, count: 8))
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let harness = try KernelHarness(urls: [first, second], crossfadeFrames: 100)
        defer { harness.reclaim() }

        let rendered = harness.render(frameCount: 12)
        XCTAssertEqual(Array(rendered.left.prefix(4)), Array(repeating: 1, count: 4))
        for progress in 0..<4 {
            let gains = EqualPowerCrossfade.gains(progress: Int64(progress), length: 4)
            XCTAssertEqual(
                rendered.left[4 + progress],
                gains.active + 2 * gains.incoming,
                accuracy: 0.000_01
            )
        }
        assertFloatArraysEqual(
            Array(rendered.left.suffix(4)),
            Array(repeating: 2, count: 4),
            accuracy: 0.000_01
        )
    }

    func testOfflineKernelPublishesCrossfadeProgressAndCancellation() throws {
        let first = try makeStereoFloatFixture(frames: Array(repeating: 1, count: 8))
        let second = try makeStereoFloatFixture(frames: Array(repeating: 2, count: 8))
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let harness = try KernelHarness(urls: [first, second], crossfadeFrames: 4)
        defer { harness.reclaim() }

        _ = harness.render(frameCount: 6)
        XCTAssertEqual(harness.diagnostics.transitionState, .crossfading)
        XCTAssertEqual(harness.diagnostics.transitionProgressFrames, 2)
        XCTAssertEqual(harness.diagnostics.transitionLengthFrames, 4)
        harness.stopAndProcess()
        XCTAssertEqual(harness.diagnostics.cancelledDecodedFrames, 8)
        XCTAssertEqual(harness.diagnostics.transitionState, .stopped)
        XCTAssertEqual(harness.diagnostics.currentBufferFrames, 0)
        XCTAssertEqual(harness.diagnostics.incomingBufferFrames, 0)

        harness.resetDiagnostics()
        XCTAssertEqual(harness.diagnostics.renderedFrames, 0)
        XCTAssertEqual(harness.diagnostics.cancelledDecodedFrames, 0)
    }

    func testNativeDecoderResamplesMonoWAVToStereo() throws {
        let url = try makeMonoFixture(fileExtension: "wav", formatID: kAudioFormatLinearPCM)
        defer { try? FileManager.default.removeItem(at: url) }
        try assertNativeDecode(url: url)
    }

    func testNativeDecoderSupportsFLAC() throws {
        let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: ffmpeg.path))
        let wav = try makeMonoFixture(fileExtension: "wav", formatID: kAudioFormatLinearPCM)
        let flac = wav.deletingPathExtension().appendingPathExtension("flac")
        defer {
            try? FileManager.default.removeItem(at: wav)
            try? FileManager.default.removeItem(at: flac)
        }
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-v", "error", "-y", "-i", wav.path, flac.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        try assertNativeDecode(url: flac)
    }

    func testCommittedFormatMatrixDecodesAndSeeks() throws {
        let names = [
            "tone-44100-mono-16.wav",
            "tone-48000-stereo-24.aiff",
            "tone-96000-stereo-24.flac",
            "tone-192000-mono-16.wav",
            "tone-48000-stereo-24-alac.m4a",
            "priming-44k-mono.mp3",
            "priming-48k-mono.m4a",
        ]
        for name in names {
            let session = try NativeDecoderSession(url: fixtureURL(name), sampleRate: 48_000)
            defer { session.stop() }
            try session.prime(minimumFrames: 512)
            XCTAssertGreaterThan(session.ringBuffer.availableFrames, 0, name)
        }

        let seekable = try NativeDecoderSession(
            url: fixtureURL("metadata-artwork-seek.flac"),
            sampleRate: 48_000
        )
        defer { seekable.stop() }
        try seekable.seek(to: 0.049)
        try seekable.prime(minimumFrames: 1_000)
        let available = seekable.ringBuffer.availableFrames
        var samples = [Float](repeating: 0, count: available * 2)
        XCTAssertGreaterThan(
            seekable.ringBuffer.read(into: &samples, maxFrames: available),
            0
        )
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.5)
    }

    func testCommittedCorruptFixturesAreRejected() {
        for name in ["corrupt-header.flac", "corrupt-truncated.wav"] {
            XCTAssertThrowsError(try {
                let session = try NativeDecoderSession(
                    url: fixtureURL(name),
                    sampleRate: 48_000
                )
                defer { session.stop() }
                try session.prime(minimumFrames: 128)
                if session.ringBuffer.availableFrames == 0 {
                    throw NativeAudioError.openFailed(name)
                }
            }(), name)
        }
    }

    func testFLACMetadataAndArtworkSurviveImport() async {
        let metadata = await MetadataReader.read(from: fixtureURL("metadata-artwork-seek.flac"))
        XCTAssertEqual(metadata?.title, "Synthetic Seek Markers")
        XCTAssertEqual(metadata?.artist, "Songbird Tests")
        XCTAssertEqual(metadata?.album, "Compatibility Suite")
        XCTAssertEqual(metadata?.trackNumber, 1)
        XCTAssertNotNil(metadata?.artworkData)
    }

    private func assertNativeDecode(url: URL) throws {
        let session = try NativeDecoderSession(url: url, sampleRate: 48_000)
        defer { session.stop() }
        try session.prime(minimumFrames: 100_000)

        XCTAssertTrue(session.reachedEOF)
        XCTAssertEqual(session.ringBuffer.availableFrames, 4_800, accuracy: 2)
        var decoded = [Float](repeating: 0, count: session.ringBuffer.availableFrames * 2)
        let frames = session.ringBuffer.read(into: &decoded, maxFrames: decoded.count / 2)
        XCTAssertGreaterThan(frames, 4_790)
        for frame in 0..<frames {
            XCTAssertEqual(decoded[frame * 2], decoded[frame * 2 + 1], accuracy: 0.000_001)
        }
        XCTAssertGreaterThan(decoded.map(abs).max() ?? 0, 0.25)
        XCTAssertGreaterThan(session.decodeLatency.sampleCount, 0)
        XCTAssertGreaterThan(session.conversionLatency.sampleCount, 0)
        XCTAssertGreaterThanOrEqual(
            session.decodeLatency.maximumMilliseconds,
            session.decodeLatency.averageMilliseconds
        )
    }

    private func makeMonoFixture(fileExtension: String, formatID: AudioFormatID) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        let settings: [String: Any] = [
            AVFormatIDKey: formatID,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 24,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410)!
        buffer.frameLength = 4_410
        let channel = buffer.floatChannelData![0]
        for frame in 0..<Int(buffer.frameLength) {
            channel[frame] = sin(Float(frame) * 2 * .pi * 440 / 44_100) * 0.5
        }
        try file.write(from: buffer)
        return url
    }

    private func makeStereoFloatFixture(frames: [Float]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frames.count)
        )!
        buffer.frameLength = AVAudioFrameCount(frames.count)
        for channel in 0..<2 {
            frames.withUnsafeBufferPointer {
                buffer.floatChannelData![channel].update(from: $0.baseAddress!, count: frames.count)
            }
        }
        try file.write(from: buffer)
        return url
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated")
            .appendingPathComponent(name)
    }
}

private final class KernelHarness {
    private let kernel = RenderKernel()
    private var streamPointers: [UInt] = []

    init(urls: [URL], crossfadeFrames: UInt64) throws {
        var streams: [(UInt, RenderStream)] = []
        for url in urls {
            let session = try NativeDecoderSession(url: url, sampleRate: 48_000)
            try session.prime(minimumFrames: 1_000)
            let stream = RenderStream(session: session)
            let pointer = UInt(bitPattern: Unmanaged.passRetained(stream).toOpaque())
            streams.append((pointer, stream))
            streamPointers.append(pointer)
        }
        XCTAssertTrue(kernel.enqueue(RenderSnapshot(
            command: .replaceActive,
            streamPointer: streams[0].0
        )))
        if streams.count > 1 {
            XCTAssertTrue(kernel.enqueue(RenderSnapshot(
                command: .setPending,
                streamPointer: streams[1].0,
                crossfadeFrames: crossfadeFrames
            )))
        }
    }

    func render(frameCount: Int) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                kernel.render(
                    left: leftBuffer.baseAddress!,
                    right: rightBuffer.baseAddress!,
                    frameCount: frameCount
                )
            }
        }
        return (left, right)
    }

    var diagnostics: AudioDiagnosticsSnapshot {
        kernel.diagnosticsSnapshot()
    }

    func stopAndProcess() {
        _ = kernel.enqueue(RenderSnapshot(command: .stop))
        kernel.processCommandsWhileStopped()
    }

    func resetDiagnostics() {
        kernel.resetDiagnostics()
    }

    func reclaim() {
        _ = kernel.enqueue(RenderSnapshot(command: .stop))
        kernel.processCommandsWhileStopped()
        while let message = kernel.popEvent(), let event = RenderEvent(rawValue: message.type) {
            guard let raw = UnsafeRawPointer(bitPattern: message.pointer) else { continue }
            switch event {
            case .commandConsumed:
                Unmanaged<RenderSnapshot>.fromOpaque(raw).release()
            case .streamRetired:
                let stream = Unmanaged<RenderStream>.fromOpaque(raw).takeRetainedValue()
                stream.session.stop()
                streamPointers.removeAll { $0 == message.pointer }
            default:
                break
            }
        }
        for pointer in streamPointers {
            guard let raw = UnsafeRawPointer(bitPattern: pointer) else { continue }
            Unmanaged<RenderStream>.fromOpaque(raw).takeRetainedValue().session.stop()
        }
        streamPointers.removeAll()
    }
}

private extension XCTestCase {
    func assertFloatArraysEqual(
        _ expression1: [Float],
        _ expression2: [Float],
        accuracy: Float,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(expression1.count, expression2.count, file: file, line: line)
        for (left, right) in zip(expression1, expression2) {
            XCTAssertEqual(left, right, accuracy: accuracy, file: file, line: line)
        }
    }
}
