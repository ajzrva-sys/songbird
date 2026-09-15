import AudioToolbox
import Combine
import CoreAudio
import Foundation

public enum AudioOutputTransport: String, Sendable {
    case airPlay
    case bluetooth
    case builtIn
    case display
    case wired
    case virtual
    case other
}

public struct AudioOutputDevice: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public let name: String
    public let transport: AudioOutputTransport
    public let isSystemDefault: Bool

    public init(
        id: UInt32,
        name: String,
        transport: AudioOutputTransport,
        isSystemDefault: Bool
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.isSystemDefault = isSystemDefault
    }

    public var isAirPlay: Bool { transport == .airPlay }
}

protocol AudioOutputDeviceProviding {
    func outputDevices() throws -> [AudioOutputDevice]
}

@MainActor
public final class AudioOutputController: ObservableObject {
    @Published public private(set) var devices: [AudioOutputDevice] = []
    @Published public private(set) var selectedDeviceID: UInt32?
    @Published public private(set) var errorMessage: String?

    private let provider: any AudioOutputDeviceProviding
    private var selectionHandler: ((UInt32?) throws -> Void)?

    public init() {
        provider = SystemAudioOutputDeviceProvider()
    }

    init(provider: any AudioOutputDeviceProviding) {
        self.provider = provider
    }

    public var selectedDevice: AudioOutputDevice? {
        guard let selectedDeviceID else { return nil }
        return devices.first { $0.id == selectedDeviceID }
    }

    public var selectedRouteName: String {
        if let selectedDevice { return selectedDevice.name }
        if selectedDeviceID != nil { return "Unavailable Output" }
        return "System Output"
    }

    public var isAirPlaySelected: Bool {
        selectedDevice?.isAirPlay == true
    }

    @discardableResult
    public func refreshDevices() -> Bool {
        do {
            let refreshedDevices = try provider.outputDevices().sorted(by: Self.deviceSort)
            // AudioOutputPicker refreshes when it appears and when its menu is
            // opened. Publishing an identical value from those callbacks can
            // make SwiftUI recreate the menu and invoke onAppear again,
            // producing an AttributeGraph update cycle that starves unrelated
            // player controls. Only publish an actual Core Audio route change.
            if devices != refreshedDevices {
                devices = refreshedDevices
            }
            return selectedDeviceID == nil || devices.contains { $0.id == selectedDeviceID }
        } catch {
            let message = "Could not list audio outputs: \(error.localizedDescription)"
            if errorMessage != message {
                errorMessage = message
            }
            // A transient enumeration failure is not proof that an active route vanished.
            return true
        }
    }

    public func select(deviceID: UInt32?) {
        guard deviceID != selectedDeviceID else { return }
        if let deviceID, devices.contains(where: { $0.id == deviceID }) == false {
            errorMessage = "That audio output is no longer available."
            return
        }
        do {
            try selectionHandler?(deviceID)
            selectedDeviceID = deviceID
            errorMessage = nil
        } catch {
            errorMessage = "Could not change audio output: \(error.localizedDescription)"
        }
    }

    public func clearError() {
        errorMessage = nil
    }

    func installSelectionHandler(_ handler: @escaping (UInt32?) throws -> Void) {
        selectionHandler = handler
    }

    func useSystemOutputAfterRouteLoss() {
        selectedDeviceID = nil
    }

    private static func deviceSort(_ lhs: AudioOutputDevice, _ rhs: AudioOutputDevice) -> Bool {
        if lhs.isAirPlay != rhs.isAirPlay { return lhs.isAirPlay }
        if lhs.isSystemDefault != rhs.isSystemDefault { return lhs.isSystemDefault }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

private struct SystemAudioOutputDeviceProvider: AudioOutputDeviceProviding {
    func outputDevices() throws -> [AudioOutputDevice] {
        let defaultDeviceID = try uint32Property(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice
        )
        let deviceIDs = try allDeviceIDs()
        return deviceIDs.compactMap { deviceID in
            try? outputDevice(deviceID, defaultDeviceID: defaultDeviceID)
        }
    }

    private func outputDevice(
        _ deviceID: AudioDeviceID,
        defaultDeviceID: AudioDeviceID
    ) throws -> AudioOutputDevice? {
        guard try hasOutputChannels(deviceID), try isAlive(deviceID) else { return nil }
        let name = try stringProperty(
            objectID: deviceID,
            selector: kAudioObjectPropertyName
        )
        let transportValue = try uint32Property(
            objectID: deviceID,
            selector: kAudioDevicePropertyTransportType
        )
        return AudioOutputDevice(
            id: deviceID,
            name: name as String,
            transport: Self.transport(for: transportValue),
            isSystemDefault: deviceID == defaultDeviceID
        )
    }

    private func allDeviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &byteCount
        ), operation: "read audio-device list size")
        guard byteCount > 0 else { return [] }
        var deviceIDs = [AudioDeviceID](
            repeating: kAudioObjectUnknown,
            count: Int(byteCount) / MemoryLayout<AudioDeviceID>.stride
        )
        let status = deviceIDs.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return kAudio_ParamError }
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &byteCount,
                baseAddress
            )
        }
        try check(status, operation: "read audio-device list")
        return deviceIDs
    }

    private func hasOutputChannels(_ deviceID: AudioDeviceID) throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &byteCount
        ), operation: "read output-channel list size")
        guard byteCount > 0 else { return false }
        var storage = [UInt8](repeating: 0, count: Int(byteCount))
        let status = storage.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return kAudio_ParamError }
            return AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &byteCount,
                baseAddress
            )
        }
        try check(status, operation: "read output-channel list")
        return storage.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return false }
            let buffers = UnsafeMutableAudioBufferListPointer(
                baseAddress.assumingMemoryBound(to: AudioBufferList.self)
            )
            return buffers.contains { $0.mNumberChannels > 0 }
        }
    }

    private func isAlive(_ deviceID: AudioDeviceID) throws -> Bool {
        let value = try uint32Property(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceIsAlive
        )
        return value != 0
    }

    private func uint32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var byteCount = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &byteCount,
            &value
        )
        try check(status, operation: "read audio-device property")
        return value
    }

    private func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> CFString {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var byteCount = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &byteCount,
            &value
        )
        try check(status, operation: "read audio-device name")
        guard let value else {
            throw AudioOutputRoutingError.status("read audio-device name", kAudio_ParamError)
        }
        return value.takeRetainedValue()
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw AudioOutputRoutingError.status(operation, status)
        }
    }

    private static func transport(for value: UInt32) -> AudioOutputTransport {
        switch value {
        case kAudioDeviceTransportTypeAirPlay:
            return .airPlay
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return .display
        case kAudioDeviceTransportTypeUSB,
             kAudioDeviceTransportTypeFireWire,
             kAudioDeviceTransportTypePCI,
             kAudioDeviceTransportTypeThunderbolt:
            return .wired
        case kAudioDeviceTransportTypeAggregate,
             kAudioDeviceTransportTypeAutoAggregate,
             kAudioDeviceTransportTypeVirtual:
            return .virtual
        default:
            return .other
        }
    }
}

enum AudioOutputRoutingError: LocalizedError {
    case missingOutputUnit
    case status(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingOutputUnit:
            return "The audio engine did not expose an output unit."
        case .status(let operation, let status):
            return "Could not \(operation) (Core Audio \(status))."
        }
    }
}
