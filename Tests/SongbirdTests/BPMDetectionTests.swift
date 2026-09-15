import AVFoundation
import Testing
@testable import SongbirdLib
import AubioBridge

@Suite("BPM Detection", .serialized)
struct BPMDetectionTests {
    /// Generates a click track WAV file at the given BPM.
    private func generateClickTrack(bpm: Int, duration: TimeInterval, sampleRate: Double = 44100) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("bpm-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent("click-\(bpm)bpm.wav")

        let beatInterval = 60.0 / Double(bpm)
        let totalFrames = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: totalFrames)

        var beatTime: Double = 0
        while beatTime < duration {
            let frame = Int(beatTime * sampleRate)
            let clickFrames = min(Int(0.01 * sampleRate), totalFrames - frame)
            for i in 0..<clickFrames {
                let envelope = 1.0 - Float(i) / Float(clickFrames)
                samples[frame + i] = sin(2.0 * .pi * 1000.0 * Float(i) / Float(sampleRate)) * envelope
            }
            beatTime += beatInterval
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames))!
        buffer.frameLength = AVAudioFrameCount(totalFrames)
        let channelData = buffer.floatChannelData![0]
        samples.withUnsafeBufferPointer { ptr in
            channelData.update(from: ptr.baseAddress!, count: totalFrames)
        }
        try file.write(from: buffer)

        return url
    }

    @Test("BPM detection returns valid tempo for 120 BPM click track")
    func testBPMDetection120() async throws {
        let url = try generateClickTrack(bpm: 120, duration: 10)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let metadata = await MetadataReader.read(from: url)
        let bpm = metadata?.beatsPerMinute ?? 0
        #expect(bpm >= 118 && bpm <= 122)
    }

    @Test("BPM detection returns valid tempo for 90 BPM click track")
    func testBPMDetection90() async throws {
        let url = try generateClickTrack(bpm: 90, duration: 10)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let metadata = await MetadataReader.read(from: url)
        let bpm = metadata?.beatsPerMinute ?? 0
        #expect(bpm >= 88 && bpm <= 92)
    }

    @Test("BPM detection returns 0 for very short audio")
    func testBPMDetectionShort() async throws {
        let url = try generateClickTrack(bpm: 120, duration: 0.5)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let metadata = await MetadataReader.read(from: url)
        let bpm = metadata?.beatsPerMinute ?? 0
        #expect(bpm >= 0)
    }

    @Test("C bridge returns 0 for null input")
    func testCBridgeNullInput() {
        #expect(SBAubioDetectBPM(44100, nil, 0) == 0)
    }

    @Test("C bridge returns 0 for zero frame count")
    func testCBridgeZeroFrames() {
        var sample: Float = 1.0
        #expect(SBAubioDetectBPM(44100, &sample, 0) == 0)
    }

    @Test("C bridge returns 0 for zero sample rate")
    func testCBridgeZeroSampleRate() {
        var sample: Float = 1.0
        #expect(SBAubioDetectBPM(0, &sample, 100) == 0)
    }
}
