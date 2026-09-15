import Foundation

final class RenderStream: @unchecked Sendable {
    let session: any RenderPCMSource
    init(session: any RenderPCMSource) { self.session = session }
}

enum RenderCommand: UInt32 {
    case replaceActive = 1
    case setPending
    case clearPending
    case stop
}

enum RenderEvent: UInt32 {
    case commandConsumed = 1
    case streamBegan
    case streamRetired
    case playbackFinished
    case decoderFailed
    case underflow
}

/// Immutable control-thread command transferred to the renderer as a retained pointer.
final class RenderSnapshot: @unchecked Sendable {
    let command: RenderCommand
    let streamPointer: UInt
    let crossfadeFrames: UInt64
    let startFrame: UInt64

    init(
        command: RenderCommand,
        streamPointer: UInt = 0,
        crossfadeFrames: UInt64 = 0,
        startFrame: UInt64 = 0
    ) {
        self.command = command
        self.streamPointer = streamPointer
        self.crossfadeFrames = crossfadeFrames
        self.startFrame = startFrame
    }
}

/// Pure PCM renderer shared by AVAudioSourceNode and deterministic offline tests.
final class RenderKernel: @unchecked Sendable {
    private struct Cursor {
        var activeFrames: UInt64 = 0
        var incomingFrames: UInt64 = 0
        var crossfadeProgress: UInt64 = 0
        var activeCrossfadeFrames: UInt64 = 0
    }

    private let commands = AtomicMessageQueue(capacity: 256)
    private let events = AtomicMessageQueue(capacity: 8_192)
    private let volume = AtomicFloat(1)
    private let publishedPosition = AtomicUInt64()
    private let underflows = AtomicUInt64()
    private let lastUnderflowFrame = AtomicUInt64(UInt64.max)
    private let renderCallbacks = AtomicUInt64()
    private let renderedFrames = AtomicUInt64()
    private let cancelledDecodedFrames = AtomicUInt64()
    private let overflowRejectedFrames = AtomicUInt64()
    private let lateTransitionFrames = AtomicUInt64()
    private let currentBufferFrames = AtomicUInt64()
    private let incomingBufferFrames = AtomicUInt64()
    private let pendingBufferFrames = AtomicUInt64()
    private let publishedTransitionState = AtomicUInt32(AudioTransitionState.stopped.rawValue)
    private let transitionProgress = AtomicUInt64()
    private let transitionLength = AtomicUInt64()

    // Render-thread-owned raw retained handles.
    private var activePointer: UInt = 0
    private var incomingPointer: UInt = 0
    private var pendingPointer: UInt = 0
    private var configuredCrossfadeFrames: UInt64 = 0
    private var cursor = Cursor()
    private var finishSent = false
    private var failureSent = false
    private var underflowReported = false
    private var currentOutputFrame: UInt64 = 0
    private var handoffOccurredInBlock = false

    var positionFrames: UInt64 { publishedPosition.loadAcquire() }
    var underflowCount: UInt64 { underflows.loadAcquire() }
    var currentVolume: Float { volume.loadRelaxed() }

    func setVolume(_ value: Float) {
        volume.storeRelaxed(min(max(value, 0), 1))
    }

    func enqueue(_ snapshot: RenderSnapshot) -> Bool {
        let pointer = UInt(bitPattern: Unmanaged.passRetained(snapshot).toOpaque())
        if commands.push(AtomicMessage(type: snapshot.command.rawValue, pointer: pointer, value: 0)) {
            return true
        }
        Unmanaged<RenderSnapshot>.fromOpaque(UnsafeRawPointer(bitPattern: pointer)!)
            .release()
        return false
    }

    func popEvent() -> AtomicMessage? { events.pop() }

    /// May only be called after the audio engine has stopped. It lets the
    /// control thread reclaim render-owned pointers without restarting audio.
    func processCommandsWhileStopped() {
        applyCommands()
        publishRenderDiagnostics()
    }

    func render(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        applyCommands()
        let gain = volume.loadRelaxed()
        let outputBase = renderedFrames.loadRelaxed()
        handoffOccurredInBlock = false
        for frame in 0..<frameCount {
            currentOutputFrame = outputBase + UInt64(frame)
            var l: Float = 0
            var r: Float = 0
            produceFrame(left: &l, right: &r)
            left[frame] = l * gain
            right[frame] = r * gain
        }
        publishedPosition.storeRelease(
            incomingPointer != 0 ? cursor.incomingFrames : cursor.activeFrames
        )
        renderCallbacks.fetchAddRelaxed(1)
        renderedFrames.fetchAddRelaxed(UInt64(frameCount))
        publishRenderDiagnostics()
    }

    private func applyCommands() {
        while let message = commands.pop(),
              let raw = UnsafeRawPointer(bitPattern: message.pointer) {
            let snapshot = Unmanaged<RenderSnapshot>.fromOpaque(raw).takeUnretainedValue()
            switch snapshot.command {
            case .replaceActive:
                retireAllStreams(cancelled: true)
                activePointer = snapshot.streamPointer
                cursor = Cursor(activeFrames: snapshot.startFrame)
                configuredCrossfadeFrames = snapshot.crossfadeFrames
                finishSent = false
                failureSent = false
                underflowReported = false
                emit(.streamBegan, pointer: activePointer)
            case .setPending:
                retire(&pendingPointer, cancelled: true)
                pendingPointer = snapshot.streamPointer
                configuredCrossfadeFrames = snapshot.crossfadeFrames
            case .clearPending:
                retire(&pendingPointer, cancelled: true)
                configuredCrossfadeFrames = 0
            case .stop:
                retireAllStreams(cancelled: true)
                cursor = Cursor()
                finishSent = false
                failureSent = false
                underflowReported = false
            }
            emit(.commandConsumed, pointer: message.pointer)
        }
    }

    @inline(__always)
    private func stream(_ pointer: UInt) -> RenderStream {
        Unmanaged<RenderStream>.fromOpaque(UnsafeRawPointer(bitPattern: pointer)!)
            .takeUnretainedValue()
    }

    @inline(__always)
    private func produceFrame(left: inout Float, right: inout Float) {
        guard activePointer != 0 else { return }
        let active = stream(activePointer)
        if active.session.ringBuffer.totalSamplesRead == 0,
           active.session.ringBuffer.availableFrames < active.session.minimumPlaybackFrames,
           active.session.state != .eof,
           active.session.state != .failed {
            return
        }
        if pendingPointer != 0, stream(pendingPointer).session.state == .failed {
            reportFailure(pendingPointer)
            return
        }
        if incomingPointer != 0, stream(incomingPointer).session.state == .failed {
            reportFailure(incomingPointer)
            return
        }

        if incomingPointer == 0, pendingPointer != 0, configuredCrossfadeFrames > 0 {
            let pending = stream(pendingPointer)
            let effective = min(
                configuredCrossfadeFrames,
                UInt64(max(0, active.session.totalOutputFrames)) / 2,
                UInt64(max(0, pending.session.totalOutputFrames)) / 2
            )
            let remaining = UInt64(max(0, active.session.totalOutputFrames - Int64(cursor.activeFrames)))
            let ready = pending.session.ringBuffer.availableFrames >= Int(effective)
                || pending.session.state == .eof
            if effective > 0, remaining <= effective, ready {
                incomingPointer = pendingPointer
                pendingPointer = 0
                cursor.incomingFrames = 0
                cursor.crossfadeProgress = 0
                cursor.activeCrossfadeFrames = effective
                emit(.streamBegan, pointer: incomingPointer)
            }
        }

        if incomingPointer != 0 {
            let incoming = stream(incomingPointer)
            var al: Float = 0, ar: Float = 0
            var il: Float = 0, ir: Float = 0
            let readActive = active.session.ringBuffer.readStereoFrame(left: &al, right: &ar)
            let readIncoming = incoming.session.ringBuffer.readStereoFrame(left: &il, right: &ir)
            if readActive {
                cursor.activeFrames += 1
            }
            if readIncoming {
                cursor.incomingFrames += 1
            }
            if readActive && readIncoming {
                underflowReported = false
            }
            if !readActive || !readIncoming {
                incrementUnderflow()
                let missing = UInt64((readActive ? 0 : 1) + (readIncoming ? 0 : 1))
                lateTransitionFrames.fetchAddRelaxed(missing)
            }
            let length = max(1, cursor.activeCrossfadeFrames)
            let gains = EqualPowerCrossfade.gains(
                progress: Int64(cursor.crossfadeProgress),
                length: Int64(length)
            )
            left = al * gains.active + il * gains.incoming
            right = ar * gains.active + ir * gains.incoming
            cursor.crossfadeProgress += 1
            if cursor.crossfadeProgress >= length {
                retire(&activePointer, cancelled: false)
                activePointer = incomingPointer
                incomingPointer = 0
                cursor.activeFrames = cursor.incomingFrames
                cursor.incomingFrames = 0
                cursor.crossfadeProgress = 0
                cursor.activeCrossfadeFrames = 0
            }
            return
        }

        if active.session.ringBuffer.readStereoFrame(left: &left, right: &right) {
            cursor.activeFrames += 1
            underflowReported = false
            return
        }

        switch active.session.state {
        case .failed:
            reportFailure(activePointer)
        case .eof:
            if pendingPointer != 0,
               stream(pendingPointer).session.ringBuffer.availableFrames > 0
                || stream(pendingPointer).session.state == .eof {
                retire(&activePointer, cancelled: false)
                activePointer = pendingPointer
                pendingPointer = 0
                cursor.activeFrames = 0
                handoffOccurredInBlock = true
                emit(.streamBegan, pointer: activePointer)
                let next = stream(activePointer)
                if next.session.ringBuffer.readStereoFrame(left: &left, right: &right) {
                    cursor.activeFrames = 1
                    underflowReported = false
                }
            } else if pendingPointer == 0, !finishSent {
                retire(&activePointer, cancelled: false)
                finishSent = true
                emit(.playbackFinished)
            } else {
                incrementUnderflow()
            }
        default:
            incrementUnderflow()
        }
    }

    private func retireAllStreams(cancelled: Bool) {
        retire(&activePointer, cancelled: cancelled)
        retire(&incomingPointer, cancelled: cancelled)
        retire(&pendingPointer, cancelled: cancelled)
    }

    private func retire(_ pointer: inout UInt, cancelled: Bool) {
        guard pointer != 0 else { return }
        if cancelled {
            cancelledDecodedFrames.fetchAddRelaxed(
                UInt64(stream(pointer).session.ringBuffer.availableFrames)
            )
        }
        emit(.streamRetired, pointer: pointer)
        pointer = 0
    }

    private func emit(_ event: RenderEvent, pointer: UInt = 0, value: UInt64 = 0) {
        _ = events.push(AtomicMessage(type: event.rawValue, pointer: pointer, value: value))
    }

    private func incrementUnderflow() {
        let next = underflows.fetchAddRelaxed(1) + 1
        lastUnderflowFrame.storeRelaxed(currentOutputFrame)
        if !underflowReported {
            underflowReported = true
            emit(.underflow, value: next)
        }
    }

    private func reportFailure(_ pointer: UInt) {
        if !failureSent {
            failureSent = true
            emit(.decoderFailed, pointer: pointer)
        }
    }

    private func publishRenderDiagnostics() {
        currentBufferFrames.storeRelease(bufferFrames(activePointer))
        incomingBufferFrames.storeRelease(bufferFrames(incomingPointer))
        pendingBufferFrames.storeRelease(bufferFrames(pendingPointer))
        transitionProgress.storeRelease(cursor.crossfadeProgress)
        transitionLength.storeRelease(
            incomingPointer != 0 ? cursor.activeCrossfadeFrames : configuredCrossfadeFrames
        )

        let state: AudioTransitionState
        if handoffOccurredInBlock {
            state = .gaplessHandoff
        } else if incomingPointer != 0 {
            state = .crossfading
        } else if pendingPointer != 0 {
            state = configuredCrossfadeFrames > 0 ? .pendingCrossfade : .pendingGapless
        } else {
            state = activePointer == 0 ? .stopped : .playing
        }
        publishedTransitionState.storeRelease(state.rawValue)
    }

    @inline(__always)
    private func bufferFrames(_ pointer: UInt) -> UInt64 {
        pointer == 0 ? 0 : UInt64(stream(pointer).session.ringBuffer.availableFrames)
    }

    func diagnosticsSnapshot() -> AudioDiagnosticsSnapshot {
        let last = lastUnderflowFrame.loadAcquire()
        return AudioDiagnosticsSnapshot(
            currentBufferFrames: currentBufferFrames.loadAcquire(),
            incomingBufferFrames: incomingBufferFrames.loadAcquire(),
            pendingBufferFrames: pendingBufferFrames.loadAcquire(),
            underflowFrames: underflows.loadAcquire(),
            lastUnderflowOutputFrame: last == UInt64.max ? nil : last,
            renderCallbacks: renderCallbacks.loadAcquire(),
            renderedFrames: renderedFrames.loadAcquire(),
            cancelledDecodedFrames: cancelledDecodedFrames.loadAcquire(),
            overflowRejectedFrames: overflowRejectedFrames.loadAcquire(),
            lateTransitionFrames: lateTransitionFrames.loadAcquire(),
            deviceSampleRate: 0,
            transitionState: AudioTransitionState(
                rawValue: publishedTransitionState.loadAcquire()
            ) ?? .stopped,
            transitionProgressFrames: transitionProgress.loadAcquire(),
            transitionLengthFrames: transitionLength.loadAcquire(),
            decodeLatency: .zero,
            conversionLatency: .zero
        )
    }

    func resetDiagnostics() {
        underflows.storeRelease(0)
        lastUnderflowFrame.storeRelease(UInt64.max)
        renderCallbacks.storeRelease(0)
        renderedFrames.storeRelease(0)
        cancelledDecodedFrames.storeRelease(0)
        overflowRejectedFrames.storeRelease(0)
        lateTransitionFrames.storeRelease(0)
    }
}
