import AVFoundation
import AudioToolbox
import Foundation

enum EqualPowerCrossfade {
    @inline(__always)
    static func gains(progress: Int64, length: Int64) -> (active: Float, incoming: Float) {
        let phase = min(1, Double(progress) / Double(max(1, length)))
        return (Float(cos(phase * .pi / 2)), Float(sin(phase * .pi / 2)))
    }
}

@MainActor
public final class NativeAudioBackend:
    SourcePreparingPlayerBackend,
    AudioDiagnosticsProviding,
    @unchecked Sendable
{
    private let kernel = RenderKernel()
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var eventTimer: Timer?
    private let deviceCoordinator: AudioDeviceCoordinating
    private let outputDeviceApplier: any AudioOutputDeviceApplying
    public let audioOutput: AudioOutputController?
    private var requestedOutputDeviceID: UInt32?
    private var streams: [UInt: RenderStream] = [:]
    private var activePointer: UInt = 0
    private var pendingPointer: UInt = 0
    private var sampleRate: Double = 48_000
    private let publishedSampleRate = AtomicDouble(48_000)
    private var retiredDecodeLatency = LatencyAccumulator()
    private var retiredConversionLatency = LatencyAccumulator()
    private var currentSource: AudioSource?
    private var currentDurationHint: TimeInterval = 0
    private var _isRunning = false
    private var _isPaused = false
    private var requestedVolume: Double = 1
    private var fadeTask: Task<Void, Never>?
    private let transportFadeDuration: TimeInterval = 0.22
    private var sleepRecovery: (source: AudioSource, position: TimeInterval, wasPaused: Bool)?

    public var onTrackBegan: ((AudioSource?) -> Void)?
    public var onTrackFinished: (() -> Void)?
    public var onError: ((String) -> Void)?

    public init() {
        deviceCoordinator = SystemAudioDeviceCoordinator()
        outputDeviceApplier = SystemAudioOutputDeviceApplier()
        let audioOutput = AudioOutputController()
        self.audioOutput = audioOutput
        bindAudioOutputSelection(audioOutput)
    }

    init(deviceCoordinator: AudioDeviceCoordinating) {
        self.deviceCoordinator = deviceCoordinator
        outputDeviceApplier = SystemAudioOutputDeviceApplier()
        let audioOutput = AudioOutputController()
        self.audioOutput = audioOutput
        bindAudioOutputSelection(audioOutput)
    }

    init(
        deviceCoordinator: AudioDeviceCoordinating,
        audioOutput: AudioOutputController
    ) {
        self.deviceCoordinator = deviceCoordinator
        outputDeviceApplier = SystemAudioOutputDeviceApplier()
        self.audioOutput = audioOutput
        bindAudioOutputSelection(audioOutput)
    }

    init(
        deviceCoordinator: AudioDeviceCoordinating,
        audioOutput: AudioOutputController,
        outputDeviceApplier: any AudioOutputDeviceApplying
    ) {
        self.deviceCoordinator = deviceCoordinator
        self.outputDeviceApplier = outputDeviceApplier
        self.audioOutput = audioOutput
        bindAudioOutputSelection(audioOutput)
    }

    isolated deinit {
        fadeTask?.cancel()
        eventTimer?.invalidate()
    }

    public func prepare() throws {
        guard engine == nil else { return }
        try configureEngine()
        eventTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.drainRenderEvents() }
        }
        observeDeviceChanges()
    }

    public func shutdown() {
        fadeTask?.cancel()
        fadeTask = nil
        stopImmediately()
        eventTimer?.invalidate()
        eventTimer = nil
        deviceCoordinator.stopObserving()
        engine = nil
        sourceNode = nil
    }

    public func play(_ source: AudioSource, durationHint: TimeInterval) throws {
        try validateSource(source)
        if engine == nil { try prepare() }
        let stream = try NativeStreamPreparation.makeStream(source, sampleRate: sampleRate, startAt: 0)
        try playPrepared(NativePreparedSource(
            source: source, sampleRate: sampleRate, startAt: 0, stream: stream
        ), durationHint: durationHint)
    }

    func prepareSource(_ source: AudioSource, startAt: TimeInterval) async throws -> any PreparedAudioSource {
        try validateSource(source)
        if engine == nil { try prepare() }
        return try await NativeStreamPreparation.prepare(source, sampleRate: sampleRate, startAt: startAt)
    }

    func playPrepared(_ source: any PreparedAudioSource, durationHint: TimeInterval) throws {
        try replacePrepared(source, wasPaused: false)
        currentDurationHint = durationHint
    }

    func seekPrepared(_ source: any PreparedAudioSource) throws {
        guard source.source == currentSource else { throw CancellationError() }
        try replacePrepared(source, wasPaused: _isPaused)
    }

    private func checkedPreparation(_ source: any PreparedAudioSource) throws -> NativePreparedSource {
        guard engine != nil,
              let prepared = source as? NativePreparedSource,
              prepared.sampleRate == sampleRate else {
            throw NativeAudioError.operationFailed("accept source after audio output changed; try again", -1)
        }
        return prepared
    }

    private func replacePrepared(_ source: any PreparedAudioSource, wasPaused: Bool) throws {
        let prepared = try checkedPreparation(source)
        let stream = try prepared.consume()
        stream.session.start()
        let pointer = UInt(bitPattern: Unmanaged.passRetained(stream).toOpaque())
        cancelFade(restoringVolume: true)
        stopRendererAndReclaim()
        guard submit(RenderSnapshot(
            command: .replaceActive, streamPointer: pointer,
            startFrame: UInt64(max(0, prepared.startAt) * sampleRate)
        )) else {
            reclaimUnsubmitted(pointer)
            throw NativeAudioError.operationFailed("queue playback command", -1)
        }
        streams[pointer] = stream
        activePointer = pointer
        pendingPointer = 0
        currentSource = prepared.source
        do {
            if !wasPaused { try engine?.start() }
        } catch {
            stopImmediately()
            throw error
        }
        _isRunning = true
        _isPaused = wasPaused
    }

    private func validateSource(_ source: AudioSource) throws {
        if case .file(let url) = source,
           !Self.supportedExtensions.contains(url.pathExtension.lowercased()) {
            throw NativeAudioError.unsupportedFormat(url.lastPathComponent)
        }
    }

    public func pause() {
        guard let engine, _isRunning, !_isPaused else { return }
        _isPaused = true
        fadeTask?.cancel()
        let startVolume = Float(requestedVolume)
        fadeTask = Task { @MainActor [weak self, weak engine] in
            guard let self else { return }
            let completed = await self.rampVolume(
                from: startVolume,
                to: 0,
                duration: self.transportFadeDuration
            )
            guard completed else { return }
            engine?.pause()
            // Restore silently while paused so resume starts at the chosen volume.
            self.kernel.setVolume(Float(self.requestedVolume))
            self.fadeTask = nil
        }
    }

    public func resume() {
        guard let engine, _isPaused else { return }
        cancelFade(restoringVolume: false)
        do {
            let wasRunning = engine.isRunning
            let startVolume = wasRunning ? kernel.currentVolume : 0
            if !wasRunning {
                kernel.setVolume(0)
                try engine.start()
            }
            _isPaused = false
            let target = Float(requestedVolume)
            fadeTask = Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await self.rampVolume(
                    from: startVolume,
                    to: target,
                    duration: self.transportFadeDuration
                )
                self.fadeTask = nil
            }
        } catch {
            kernel.setVolume(Float(requestedVolume))
            onError?("Could not resume playback: \(error.localizedDescription)")
        }
    }

    public func stop() {
        guard _isRunning else {
            stopImmediately()
            return
        }
        fadeTask?.cancel()
        let startVolume = kernel.currentVolume
        fadeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let completed = await self.rampVolume(
                from: startVolume,
                to: 0,
                duration: self.transportFadeDuration
            )
            guard completed else { return }
            self.stopImmediately()
            self.kernel.setVolume(Float(self.requestedVolume))
            self.fadeTask = nil
        }
        _isRunning = false
        _isPaused = false
    }

    public func stopImmediately() {
        fadeTask?.cancel()
        stopRendererAndReclaim()
        currentSource = nil
        currentDurationHint = 0
        activePointer = 0
        pendingPointer = 0
        _isRunning = false
        _isPaused = false
    }

    public func seek(to time: TimeInterval) {
        guard let source = currentSource else { return }
        do {
            let stream = try NativeStreamPreparation.makeStream(source, sampleRate: sampleRate, startAt: time)
            try seekPrepared(NativePreparedSource(
                source: source, sampleRate: sampleRate, startAt: time, stream: stream
            ))
        } catch {
            onError?("Could not seek source: \(error.localizedDescription)")
        }
    }

    public func setNextSource(_ source: AudioSource?, crossfadeDuration: TimeInterval) {
        guard let source else {
            _ = submit(RenderSnapshot(command: .clearPending))
            pendingPointer = 0
            return
        }
        if streams[pendingPointer]?.session.source == source { return }
        do {
            let stream = try NativeStreamPreparation.makeStream(source, sampleRate: sampleRate, startAt: 0)
            try setNextPrepared(NativePreparedSource(
                source: source, sampleRate: sampleRate, startAt: 0, stream: stream
            ), crossfadeDuration: crossfadeDuration)
        } catch {
            setNextSource(nil, crossfadeDuration: 0)
            onError?("Could not preload source: \(error.localizedDescription)")
        }
    }

    func hasPreparedNext(_ source: AudioSource) -> Bool {
        streams[pendingPointer]?.session.source == source
    }

    func setNextPrepared(_ source: any PreparedAudioSource, crossfadeDuration: TimeInterval) throws {
        let prepared = try checkedPreparation(source)
        if streams[pendingPointer]?.session.source == prepared.source { return }
        let stream = try prepared.consume()
        stream.session.start()
        let pointer = UInt(bitPattern: Unmanaged.passRetained(stream).toOpaque())
        guard submit(RenderSnapshot(
            command: .setPending, streamPointer: pointer,
            crossfadeFrames: UInt64(max(0, crossfadeDuration) * sampleRate)
        )) else {
            reclaimUnsubmitted(pointer)
            throw NativeAudioError.operationFailed("queue preload command", -1)
        }
        streams[pointer] = stream
        pendingPointer = pointer
    }

    public var position: TimeInterval {
        sampleRate > 0 ? Double(kernel.positionFrames) / sampleRate : 0
    }

    public var duration: TimeInterval {
        streams[activePointer]?.session.duration ?? currentDurationHint
    }

    public var isPlaying: Bool { _isRunning && !_isPaused }
    public var isPaused: Bool { _isPaused }

    public var volume: Double {
        get { requestedVolume }
        set {
            requestedVolume = min(max(newValue, 0), 1)
            if fadeTask == nil {
                kernel.setVolume(Float(requestedVolume))
            }
        }
    }

    private func cancelFade(restoringVolume: Bool) {
        fadeTask?.cancel()
        fadeTask = nil
        if restoringVolume {
            kernel.setVolume(Float(requestedVolume))
        }
    }

    /// Smooth control-thread gain changes; the render callback only performs
    /// one atomic load per buffer and never sleeps or allocates.
    private func rampVolume(
        from start: Float,
        to end: Float,
        duration: TimeInterval
    ) async -> Bool {
        let steps = 22
        let nanoseconds = UInt64(duration * 1_000_000_000 / Double(steps))
        for step in 1...steps {
            guard !Task.isCancelled else { return false }
            let progress = Float(step) / Float(steps)
            // Raised-cosine easing avoids a sharp slope at either endpoint.
            let eased = (1 - cos(progress * .pi)) / 2
            kernel.setVolume(start + (end - start) * eased)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return false
            }
        }
        kernel.setVolume(end)
        return true
    }

    public func audioDiagnosticsSnapshot() -> AudioDiagnosticsSnapshot {
        var snapshot = kernel.diagnosticsSnapshot()
        snapshot.deviceSampleRate = publishedSampleRate.loadAcquire()

        var decode = retiredDecodeLatency
        var conversion = retiredConversionLatency
        for stream in streams.values {
            decode.add(stream.session.decodeLatency)
            conversion.add(stream.session.conversionLatency)
        }
        snapshot.decodeLatency = decode.snapshot
        snapshot.conversionLatency = conversion.snapshot
        return snapshot
    }

    public func resetAudioDiagnostics() {
        kernel.resetDiagnostics()
        retiredDecodeLatency.reset()
        retiredConversionLatency.reset()
        for stream in streams.values {
            stream.session.resetDiagnostics()
        }
    }

    private func configureEngine() throws {
        let engine = AVAudioEngine()
        try applyRequestedOutputDevice(to: engine)
        let hardwareFormat = engine.outputNode.inputFormat(forBus: 0)
        sampleRate = hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : 48_000
        publishedSampleRate.storeRelease(sampleRate)
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            throw NativeAudioError.operationFailed("create output format", -1)
        }

        let source = AVAudioSourceNode(format: sourceFormat) { [kernel] _, _, frameCount, buffers in
            let output = UnsafeMutableAudioBufferListPointer(buffers)
            guard output.count >= 2,
                  output[0].mNumberChannels == 1,
                  output[1].mNumberChannels == 1,
                  let left = output[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = output[1].mData?.assumingMemoryBound(to: Float.self) else {
                for buffer in output {
                    if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                }
                return noErr
            }
            kernel.render(left: left, right: right, frameCount: Int(frameCount))
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: sourceFormat)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        engine.mainMixerNode.outputVolume = 1
        self.engine = engine
        sourceNode = source
    }

    private func makeStream(
        source: AudioSource,
        startAt: TimeInterval = 0
    ) throws -> (UInt, RenderStream) {
        let stream = try NativeStreamPreparation.makeStream(source, sampleRate: sampleRate, startAt: startAt)
        stream.session.start()
        let pointer = UInt(bitPattern: Unmanaged.passRetained(stream).toOpaque())
        return (pointer, stream)
    }

    private func submit(_ snapshot: RenderSnapshot) -> Bool {
        if kernel.enqueue(snapshot) { return true }
        drainRenderEvents()
        return kernel.enqueue(snapshot)
    }

    private func stopRendererAndReclaim() {
        engine?.stop()
        enqueueStopAndReclaim()
    }

    private func enqueueStopAndReclaim() {
        if !submit(RenderSnapshot(command: .stop)) {
            onError?("The audio command queue could not accept a stop command.")
            return
        }
        kernel.processCommandsWhileStopped()
        drainRenderEvents()
    }

    private func reclaimUnsubmitted(_ pointer: UInt) {
        guard let raw = UnsafeRawPointer(bitPattern: pointer) else { return }
        let stream = Unmanaged<RenderStream>.fromOpaque(raw).takeRetainedValue()
        NativeStreamCleanup.retire(stream)
    }

    private func drainRenderEvents() {
        var failure: (AudioSource, String)?
        while let message = kernel.popEvent(), let event = RenderEvent(rawValue: message.type) {
            switch event {
            case .commandConsumed:
                if let raw = UnsafeRawPointer(bitPattern: message.pointer) {
                    Unmanaged<RenderSnapshot>.fromOpaque(raw).release()
                }
            case .streamBegan:
                guard let stream = streams[message.pointer] else { continue }
                activePointer = message.pointer
                if pendingPointer == message.pointer { pendingPointer = 0 }
                currentSource = stream.session.source
                onTrackBegan?(stream.session.source)
            case .streamRetired:
                retireStream(message.pointer)
            case .playbackFinished:
                _isRunning = false
                _isPaused = false
                onTrackFinished?()
            case .decoderFailed:
                if let stream = streams[message.pointer] {
                    failure = (
                        stream.session.source,
                        stream.session.decodeError ?? "The decoder stopped unexpectedly."
                    )
                }
            case .underflow:
                break
            }
        }
        if let failure {
            stop()
            onError?("Could not decode \(failure.0.displayName): \(failure.1)")
        }
    }

    private func retireStream(_ pointer: UInt) {
        guard let raw = UnsafeRawPointer(bitPattern: pointer) else { return }
        let retained = Unmanaged<RenderStream>.fromOpaque(raw).takeRetainedValue()
        retiredDecodeLatency.add(retained.session.decodeLatency)
        retiredConversionLatency.add(retained.session.conversionLatency)
        streams.removeValue(forKey: pointer)
        if activePointer == pointer { activePointer = 0 }
        if pendingPointer == pointer { pendingPointer = 0 }
        NativeStreamCleanup.retire(retained)
    }

    private func observeDeviceChanges() {
        guard let engine else { return }
        deviceCoordinator.observe(engine: engine) { [weak self] event in
            self?.handleDeviceEvent(event)
        }
    }

    private func handleDeviceEvent(_ event: AudioDeviceEvent) {
        switch event {
        case .willSleep:
            guard _isRunning, let source = currentSource else { return }
            sleepRecovery = (source, position, _isPaused)
            engine?.pause()
        case .didWake:
            guard let recovery = sleepRecovery else { return }
            sleepRecovery = nil
            rebuildEngine(
                source: recovery.source,
                resumeAt: recovery.position,
                wasPaused: recovery.wasPaused
            )
        case .configurationChanged:
            let selectedRouteStillExists = audioOutput?.refreshDevices() ?? true
            if selectedRouteStillExists == false {
                requestedOutputDeviceID = nil
                audioOutput?.useSystemOutputAfterRouteLoss()
                onError?("The selected audio output disconnected. Songbird returned to System Output.")
                if !_isRunning {
                    cancelFade(restoringVolume: true)
                    do {
                        try reconfigureEngine(source: nil, resumeAt: 0, wasPaused: false)
                    } catch {
                        engine = nil
                        sourceNode = nil
                        onError?("System Output could not be restored: \(error.localizedDescription)")
                    }
                    return
                }
            }
            guard sleepRecovery == nil, _isRunning, let source = currentSource else { return }
            rebuildEngine(source: source, resumeAt: position, wasPaused: _isPaused)
        }
    }

    private func rebuildEngine(source: AudioSource, resumeAt: TimeInterval, wasPaused: Bool) {
        do {
            try reconfigureEngine(source: source, resumeAt: resumeAt, wasPaused: wasPaused)
        } catch {
            stopImmediately()
            onError?("Audio device changed and playback could not resume: \(error.localizedDescription)")
        }
    }

    private func bindAudioOutputSelection(_ audioOutput: AudioOutputController) {
        audioOutput.installSelectionHandler { [weak self] deviceID in
            guard let self else { throw NativeAudioError.closed }
            try self.selectOutputDevice(deviceID)
        }
    }

    private func selectOutputDevice(_ deviceID: UInt32?) throws {
        let previousDeviceID = requestedOutputDeviceID
        cancelFade(restoringVolume: true)
        let source = _isRunning ? currentSource : nil
        let resumeAt = source == nil ? 0 : position
        let wasPaused = _isPaused
        requestedOutputDeviceID = deviceID
        do {
            try reconfigureEngine(source: source, resumeAt: resumeAt, wasPaused: wasPaused)
        } catch {
            requestedOutputDeviceID = previousDeviceID
            do {
                try reconfigureEngine(source: source, resumeAt: resumeAt, wasPaused: wasPaused)
            } catch {
                stopImmediately()
                onError?("Audio output recovery failed: \(error.localizedDescription)")
            }
            throw error
        }
    }

    private func applyRequestedOutputDevice(to engine: AVAudioEngine) throws {
        try outputDeviceApplier.apply(deviceID: requestedOutputDeviceID, to: engine)
    }

    private func reconfigureEngine(
        source: AudioSource?,
        resumeAt: TimeInterval,
        wasPaused: Bool
    ) throws {
        engine?.stop()
        enqueueStopAndReclaim()
        deviceCoordinator.stopObserving()
        engine = nil
        sourceNode = nil
        try configureEngine()
        observeDeviceChanges()

        guard let source else {
            currentSource = nil
            currentDurationHint = 0
            _isRunning = false
            _isPaused = false
            return
        }
        let (pointer, stream) = try makeStream(source: source, startAt: resumeAt)
        guard submit(RenderSnapshot(
            command: .replaceActive,
            streamPointer: pointer,
            startFrame: UInt64(max(0, resumeAt) * sampleRate)
        )) else {
            reclaimUnsubmitted(pointer)
            throw NativeAudioError.operationFailed("queue device recovery", -1)
        }
        streams[pointer] = stream
        activePointer = pointer
        currentSource = source
        if !wasPaused { try engine?.start() }
        _isRunning = true
        _isPaused = wasPaused
    }

    private static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aiff", "aif"
    ]
}

@MainActor
protocol AudioOutputDeviceApplying {
    func apply(deviceID: UInt32?, to engine: AVAudioEngine) throws
}

@MainActor
struct SystemAudioOutputDeviceApplier: AudioOutputDeviceApplying {
    func apply(deviceID: UInt32?, to engine: AVAudioEngine) throws {
        guard var deviceID else { return }
        guard let outputUnit = engine.outputNode.audioUnit else {
            throw AudioOutputRoutingError.missingOutputUnit
        }
        let status = AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioOutputRoutingError.status("select audio output", status)
        }
    }
}
