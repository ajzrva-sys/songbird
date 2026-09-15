import Foundation

public enum AudioTransitionState: UInt32, Sendable {
    case stopped
    case playing
    case pendingGapless
    case pendingCrossfade
    case gaplessHandoff
    case crossfading
}

public struct AudioLatencyStatistics: Sendable, Equatable {
    public var latestMilliseconds: Double
    public var averageMilliseconds: Double
    public var maximumMilliseconds: Double
    public var ewmaMilliseconds: Double
    public var sampleCount: UInt64

    public static let zero = AudioLatencyStatistics(
        latestMilliseconds: 0,
        averageMilliseconds: 0,
        maximumMilliseconds: 0,
        ewmaMilliseconds: 0,
        sampleCount: 0
    )
}

public struct AudioDiagnosticsSnapshot: Sendable, Equatable {
    public var currentBufferFrames: UInt64
    public var incomingBufferFrames: UInt64
    public var pendingBufferFrames: UInt64
    public var underflowFrames: UInt64
    public var lastUnderflowOutputFrame: UInt64?
    public var renderCallbacks: UInt64
    public var renderedFrames: UInt64
    public var cancelledDecodedFrames: UInt64
    public var overflowRejectedFrames: UInt64
    public var lateTransitionFrames: UInt64
    public var deviceSampleRate: Double
    public var transitionState: AudioTransitionState
    public var transitionProgressFrames: UInt64
    public var transitionLengthFrames: UInt64
    public var decodeLatency: AudioLatencyStatistics
    public var conversionLatency: AudioLatencyStatistics

    public var discardedFrames: UInt64 {
        cancelledDecodedFrames + overflowRejectedFrames + lateTransitionFrames
    }

    public static let zero = AudioDiagnosticsSnapshot(
        currentBufferFrames: 0,
        incomingBufferFrames: 0,
        pendingBufferFrames: 0,
        underflowFrames: 0,
        lastUnderflowOutputFrame: nil,
        renderCallbacks: 0,
        renderedFrames: 0,
        cancelledDecodedFrames: 0,
        overflowRejectedFrames: 0,
        lateTransitionFrames: 0,
        deviceSampleRate: 0,
        transitionState: .stopped,
        transitionProgressFrames: 0,
        transitionLengthFrames: 0,
        decodeLatency: .zero,
        conversionLatency: .zero
    )
}

@MainActor
public protocol AudioDiagnosticsProviding: AnyObject {
    func audioDiagnosticsSnapshot() -> AudioDiagnosticsSnapshot
    func resetAudioDiagnostics()
}

final class AtomicLatencyMetrics: @unchecked Sendable {
    private let latestNanoseconds = AtomicUInt64()
    private let totalNanoseconds = AtomicUInt64()
    private let maximumNanoseconds = AtomicUInt64()
    private let ewmaNanoseconds = AtomicUInt64()
    private let samples = AtomicUInt64()

    func record(nanoseconds: UInt64) {
        latestNanoseconds.storeRelaxed(nanoseconds)
        totalNanoseconds.fetchAddRelaxed(nanoseconds)
        maximumNanoseconds.maxRelaxed(nanoseconds)
        let previous = ewmaNanoseconds.loadRelaxed()
        let next = previous == 0
            ? nanoseconds
            : (previous * 7 + nanoseconds) / 8
        ewmaNanoseconds.storeRelaxed(next)
        samples.fetchAddRelaxed(1)
    }

    func snapshot() -> AudioLatencyStatistics {
        let count = samples.loadAcquire()
        let total = totalNanoseconds.loadAcquire()
        let milliseconds = 1_000_000.0
        return AudioLatencyStatistics(
            latestMilliseconds: Double(latestNanoseconds.loadAcquire()) / milliseconds,
            averageMilliseconds: count > 0
                ? Double(total) / Double(count) / milliseconds
                : 0,
            maximumMilliseconds: Double(maximumNanoseconds.loadAcquire()) / milliseconds,
            ewmaMilliseconds: Double(ewmaNanoseconds.loadAcquire()) / milliseconds,
            sampleCount: count
        )
    }

    func reset() {
        latestNanoseconds.storeRelease(0)
        totalNanoseconds.storeRelease(0)
        maximumNanoseconds.storeRelease(0)
        ewmaNanoseconds.storeRelease(0)
        samples.storeRelease(0)
    }
}

struct LatencyAccumulator {
    private(set) var totalMilliseconds: Double = 0
    private(set) var sampleCount: UInt64 = 0
    private(set) var maximumMilliseconds: Double = 0
    private(set) var latestMilliseconds: Double = 0
    private(set) var ewmaMilliseconds: Double = 0

    mutating func add(_ statistics: AudioLatencyStatistics) {
        guard statistics.sampleCount > 0 else { return }
        totalMilliseconds += statistics.averageMilliseconds * Double(statistics.sampleCount)
        sampleCount += statistics.sampleCount
        maximumMilliseconds = max(maximumMilliseconds, statistics.maximumMilliseconds)
        latestMilliseconds = statistics.latestMilliseconds
        ewmaMilliseconds = statistics.ewmaMilliseconds
    }

    var snapshot: AudioLatencyStatistics {
        AudioLatencyStatistics(
            latestMilliseconds: latestMilliseconds,
            averageMilliseconds: sampleCount > 0
                ? totalMilliseconds / Double(sampleCount)
                : 0,
            maximumMilliseconds: maximumMilliseconds,
            ewmaMilliseconds: ewmaMilliseconds,
            sampleCount: sampleCount
        )
    }

    mutating func reset() {
        self = LatencyAccumulator()
    }
}
