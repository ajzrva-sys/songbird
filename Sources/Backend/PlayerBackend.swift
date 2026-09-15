import Foundation

/// The source handed to the native renderer. Audio-CD tracks are deliberately
/// distinct from library files even when macOS exposes them as readable AIFF
/// proxies, so playback policy can remain source-aware.
public enum AudioSource: Sendable, Equatable {
    case file(URL)
    case audioCD(AudioCDSource)

    public var fileURL: URL? {
        switch self {
        case .file(let url): return url
        case .audioCD: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .file(let url): url.lastPathComponent
        case .audioCD(let source): "Audio CD track \(source.trackNumber)"
        }
    }
}

/// A decoder-side source that supplies PCM away from the real-time render
/// callback. NativeDecoderSession is the file implementation; optical sources
/// use the same buffered contract.
public protocol PCMSourceReader: AnyObject {
    var duration: TimeInterval { get }
    func prime(minimumFrames: Int) throws
    func start()
    func stop()
    func seek(to seconds: TimeInterval) throws
}

protocol RenderPCMSource: PCMSourceReader {
    var source: AudioSource { get }
    var ringBuffer: RingBuffer { get }
    var totalOutputFrames: Int64 { get }
    var minimumPlaybackFrames: Int { get }
    var state: PCMSourceState { get }
    var decodeError: String? { get }
    var decodeLatency: AudioLatencyStatistics { get }
    var conversionLatency: AudioLatencyStatistics { get }
    func resetDiagnostics()
}

public enum PCMSourceState: UInt32, Sendable {
    case idle, decoding, eof, failed, cancelled
}

/// Abstract interface between queue coordination and native audio playback.
@MainActor
public protocol PlayerBackend: AnyObject {
    // MARK: - Lifecycle

    func prepare() throws
    func shutdown()

    // MARK: - Transport

    func play(_ source: AudioSource, durationHint: TimeInterval) throws
    func pause()
    func resume()
    func stop()
    func stopImmediately()
    func seek(to time: TimeInterval)

    // MARK: - Gapless / crossfade preload

    /// Preload the next track. A zero duration performs a sample-continuous
    /// handoff; a positive duration overlaps both streams with equal-power gain.
    func setNextSource(_ source: AudioSource?, crossfadeDuration: TimeInterval)

    // MARK: - State

    var position: TimeInterval { get }
    var duration: TimeInterval { get }
    var isPlaying: Bool { get }
    var isPaused: Bool { get }
    var volume: Double { get set }
    var audioOutput: AudioOutputController? { get }

    // MARK: - Callbacks

    var onTrackBegan: ((AudioSource?) -> Void)? { get set }
    var onTrackFinished: (() -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
}

public extension PlayerBackend {
    var audioOutput: AudioOutputController? { nil }

    func stopImmediately() {
        stop()
    }

    func play(_ url: URL, durationHint: TimeInterval) throws {
        try play(.file(url), durationHint: durationHint)
    }

    func setNextURL(_ url: URL?, crossfadeDuration: TimeInterval) {
        setNextSource(url.map(AudioSource.file), crossfadeDuration: crossfadeDuration)
    }
}
