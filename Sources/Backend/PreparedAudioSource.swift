import Foundation

protocol PreparedAudioSource: Sendable {
    var source: AudioSource { get }
}

/// Opening/priming may suspend; accepting the result and committing queue state
/// remain synchronous on the control actor.
@MainActor
protocol SourcePreparingPlayerBackend: PlayerBackend {
    func prepareSource(_ source: AudioSource, startAt: TimeInterval) async throws -> any PreparedAudioSource
    func playPrepared(_ source: any PreparedAudioSource, durationHint: TimeInterval) throws
    func seekPrepared(_ source: any PreparedAudioSource) throws
    func hasPreparedNext(_ source: AudioSource) -> Bool
    func setNextPrepared(_ source: any PreparedAudioSource, crossfadeDuration: TimeInterval) throws
}

/// Sole owner until the control actor consumes the stream. An abandoned result
/// is cleaned up away from the main actor; it has never reached the renderer.
final class NativePreparedSource: @unchecked Sendable, PreparedAudioSource {
    let source: AudioSource
    let sampleRate: Double
    let startAt: TimeInterval
    private var stream: RenderStream?

    init(source: AudioSource, sampleRate: Double, startAt: TimeInterval, stream: RenderStream) {
        self.source = source
        self.sampleRate = sampleRate
        self.startAt = startAt
        self.stream = stream
    }

    @MainActor
    func consume() throws -> RenderStream {
        guard let stream else { throw CancellationError() }
        self.stream = nil
        return stream
    }

    deinit {
        if let stream { NativeStreamCleanup.retire(stream) }
    }
}

enum NativeStreamCleanup {
    static func retire(_ stream: RenderStream) {
        DispatchQueue.global(qos: .utility).async { stream.session.stop() }
    }
}

enum NativeStreamPreparation {
    typealias Factory = @Sendable (AudioSource, Double, TimeInterval) throws -> RenderStream

    @MainActor
    static func prepare(
        _ source: AudioSource, sampleRate: Double, startAt: TimeInterval,
        factory: @escaping Factory = { source, rate, position in
            try makeStream(source, sampleRate: rate, startAt: position)
        }
    ) async throws -> NativePreparedSource {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let stream = try factory(source, sampleRate, startAt)
            let prepared = NativePreparedSource(
                source: source, sampleRate: sampleRate, startAt: startAt, stream: stream
            )
            try Task.checkCancellation()
            return prepared
        }
        return try await withTaskCancellationHandler {
            let prepared = try await worker.value
            try Task.checkCancellation()
            return prepared
        } onCancel: {
            worker.cancel()
        }
    }

    static func makeStream(_ source: AudioSource, sampleRate: Double, startAt: TimeInterval) throws -> RenderStream {
        let session: any RenderPCMSource
        switch source {
        case .file(let url):
            session = try NativeDecoderSession(url: url, sampleRate: sampleRate)
        case .audioCD(let cdSource):
            session = try AudioCDReader(source: cdSource, sampleRate: sampleRate)
        }
        if startAt > 0 { try session.seek(to: startAt) }
        if session.minimumPlaybackFrames == 0 {
            try session.prime(minimumFrames: 8_192)
        }
        return RenderStream(session: session)
    }
}
