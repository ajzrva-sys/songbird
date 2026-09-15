import AVFoundation
import Combine
import Foundation
import Testing
@testable import SongbirdLib

@MainActor
@Suite("Audio output routing")
struct AudioOutputControllerTests {
    @Test("AirPlay outputs sort first and retain Core Audio transport identity")
    func airPlayOutputsSortFirst() {
        let controller = AudioOutputController(provider: StubAudioOutputProvider(devices: [
            AudioOutputDevice(
                id: 3,
                name: "Studio Display",
                transport: .display,
                isSystemDefault: false
            ),
            AudioOutputDevice(
                id: 2,
                name: "Living Room",
                transport: .airPlay,
                isSystemDefault: false
            ),
            AudioOutputDevice(
                id: 1,
                name: "Mac Speakers",
                transport: .builtIn,
                isSystemDefault: true
            ),
        ]))

        #expect(controller.refreshDevices())
        #expect(controller.devices.map(\.name) == [
            "Living Room", "Mac Speakers", "Studio Display",
        ])
        #expect(controller.devices.first?.isAirPlay == true)
        #expect(controller.selectedRouteName == "System Output")
    }

    @Test("Refreshing an unchanged route list does not republish it")
    func unchangedRefreshDoesNotRepublishDevices() {
        let controller = AudioOutputController(provider: StubAudioOutputProvider(devices: [
            AudioOutputDevice(
                id: 1,
                name: "Mac Speakers",
                transport: .builtIn,
                isSystemDefault: true
            ),
        ]))
        var publications = 0
        let observation = controller.$devices
            .dropFirst()
            .sink { _ in publications += 1 }

        #expect(controller.refreshDevices())
        #expect(controller.refreshDevices())
        #expect(publications == 1)
        withExtendedLifetime(observation) {}
    }

    @Test("A successful selection is applied before it becomes current")
    func successfulSelectionCommitsAfterApply() {
        let controller = AudioOutputController(provider: StubAudioOutputProvider(devices: [
            AudioOutputDevice(
                id: 42,
                name: "Kitchen",
                transport: .airPlay,
                isSystemDefault: false
            ),
        ]))
        _ = controller.refreshDevices()
        var appliedIDs: [UInt32?] = []
        controller.installSelectionHandler { deviceID in
            #expect(controller.selectedDeviceID == nil)
            appliedIDs.append(deviceID)
        }

        controller.select(deviceID: 42)

        #expect(appliedIDs == [42])
        #expect(controller.selectedDeviceID == 42)
        #expect(controller.selectedRouteName == "Kitchen")
        #expect(controller.isAirPlaySelected)
        #expect(controller.errorMessage == nil)
    }

    @Test("A failed route change preserves the current output")
    func failedSelectionPreservesCurrentOutput() {
        let controller = AudioOutputController(provider: StubAudioOutputProvider(devices: [
            AudioOutputDevice(
                id: 7,
                name: "Office",
                transport: .airPlay,
                isSystemDefault: false
            ),
        ]))
        _ = controller.refreshDevices()
        controller.installSelectionHandler { _ in
            throw StubAudioOutputError.selectionFailed
        }

        controller.select(deviceID: 7)

        #expect(controller.selectedDeviceID == nil)
        #expect(controller.selectedRouteName == "System Output")
        #expect(controller.errorMessage?.contains("Could not change audio output") == true)
    }

    @Test("A disappeared route can fall back to System Output")
    func disappearedRouteFallsBackToSystemOutput() {
        let provider = MutableAudioOutputProvider(devices: [
            AudioOutputDevice(
                id: 11,
                name: "Bedroom",
                transport: .airPlay,
                isSystemDefault: false
            ),
        ])
        let controller = AudioOutputController(provider: provider)
        _ = controller.refreshDevices()
        controller.select(deviceID: 11)
        provider.devices = []

        #expect(controller.refreshDevices() == false)
        #expect(controller.selectedRouteName == "Unavailable Output")

        controller.useSystemOutputAfterRouteLoss()
        #expect(controller.selectedDeviceID == nil)
        #expect(controller.selectedRouteName == "System Output")
    }

    @Test("The native backend applies a selected route before publishing it")
    func nativeBackendAppliesSelectedRoute() throws {
        let controller = AudioOutputController(provider: StubAudioOutputProvider(devices: [
            AudioOutputDevice(
                id: 24,
                name: "Dining Room",
                transport: .airPlay,
                isSystemDefault: false
            ),
        ]))
        let applier = RecordingAudioOutputDeviceApplier()
        let backend = NativeAudioBackend(
            deviceCoordinator: StubAudioDeviceCoordinator(),
            audioOutput: controller,
            outputDeviceApplier: applier
        )
        defer { backend.shutdown() }
        _ = controller.refreshDevices()

        controller.select(deviceID: 24)

        #expect(applier.appliedDeviceIDs == [24])
        #expect(controller.selectedDeviceID == 24)
        #expect(controller.errorMessage == nil)
    }

    @Test("A native route failure rebuilds the prior System Output")
    func nativeBackendRollsBackFailedRoute() {
        let controller = AudioOutputController(provider: StubAudioOutputProvider(devices: [
            AudioOutputDevice(
                id: 99,
                name: "Unavailable Receiver",
                transport: .airPlay,
                isSystemDefault: false
            ),
        ]))
        let applier = RecordingAudioOutputDeviceApplier(failingDeviceID: 99)
        let backend = NativeAudioBackend(
            deviceCoordinator: StubAudioDeviceCoordinator(),
            audioOutput: controller,
            outputDeviceApplier: applier
        )
        defer { backend.shutdown() }
        _ = controller.refreshDevices()

        controller.select(deviceID: 99)

        #expect(applier.appliedDeviceIDs == [99, nil])
        #expect(controller.selectedDeviceID == nil)
        #expect(controller.errorMessage?.contains("Could not change audio output") == true)
    }
}

private struct StubAudioOutputProvider: AudioOutputDeviceProviding {
    let devices: [AudioOutputDevice]

    func outputDevices() throws -> [AudioOutputDevice] {
        devices
    }
}

private final class MutableAudioOutputProvider: AudioOutputDeviceProviding {
    var devices: [AudioOutputDevice]

    init(devices: [AudioOutputDevice]) {
        self.devices = devices
    }

    func outputDevices() throws -> [AudioOutputDevice] {
        devices
    }
}

private enum StubAudioOutputError: LocalizedError {
    case selectionFailed

    var errorDescription: String? { "Selection failed." }
}

@MainActor
private final class StubAudioDeviceCoordinator: AudioDeviceCoordinating {
    func observe(
        engine: AVAudioEngine,
        onEvent: @escaping @MainActor @Sendable (AudioDeviceEvent) -> Void
    ) {}

    func stopObserving() {}
}

@MainActor
private final class RecordingAudioOutputDeviceApplier: AudioOutputDeviceApplying {
    private let failingDeviceID: UInt32?
    private(set) var appliedDeviceIDs: [UInt32?] = []

    init(failingDeviceID: UInt32? = nil) {
        self.failingDeviceID = failingDeviceID
    }

    func apply(deviceID: UInt32?, to engine: AVAudioEngine) throws {
        appliedDeviceIDs.append(deviceID)
        if deviceID == failingDeviceID {
            throw StubAudioOutputError.selectionFailed
        }
    }
}
