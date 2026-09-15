import SwiftUI

struct AudioOutputPicker: View {
    @EnvironmentObject private var audioOutput: AudioOutputController

    var color: Color = .secondary
    var isEnabled = true

    var body: some View {
        Menu {
            routeButton(
                name: "System Output",
                systemImage: "speaker.wave.2",
                deviceID: nil,
                selected: audioOutput.selectedDeviceID == nil
            )

            if !audioOutput.devices.isEmpty {
                Divider()
                ForEach(audioOutput.devices) { device in
                    routeButton(
                        name: device.isSystemDefault
                            ? "\(device.name) — System Default"
                            : device.name,
                        systemImage: iconName(for: device),
                        deviceID: device.id,
                        selected: audioOutput.selectedDeviceID == device.id
                    )
                }
            }
        } label: {
            Image(systemName: audioOutput.isAirPlaySelected ? "airplayaudio" : "hifispeaker")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(audioOutput.isAirPlaySelected ? Color.accentColor : color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Audio Output: \(audioOutput.selectedRouteName)")
        .disabled(!isEnabled)
        .onAppear {
            audioOutput.refreshDevices()
        }
        .simultaneousGesture(TapGesture().onEnded {
            audioOutput.refreshDevices()
        })
        .alert(
            "Couldn't Change Audio Output",
            isPresented: Binding(
                get: { audioOutput.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { audioOutput.clearError() }
                }
            )
        ) {
            Button("OK") { audioOutput.clearError() }
        } message: {
            Text(audioOutput.errorMessage ?? "The selected output is unavailable.")
        }
    }

    private func routeButton(
        name: String,
        systemImage: String,
        deviceID: UInt32?,
        selected: Bool
    ) -> some View {
        Button {
            audioOutput.select(deviceID: deviceID)
        } label: {
            Label {
                Text(name)
            } icon: {
                Image(systemName: selected ? "checkmark" : systemImage)
            }
        }
    }

    private func iconName(for device: AudioOutputDevice) -> String {
        switch device.transport {
        case .airPlay:
            return "airplayaudio"
        case .bluetooth:
            return "wave.3.right"
        case .builtIn:
            return "laptopcomputer"
        case .display:
            return "display"
        case .wired:
            return "hifispeaker"
        case .virtual, .other:
            return "speaker.wave.2"
        }
    }
}
