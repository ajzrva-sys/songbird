import AVFoundation
import AppKit
import Foundation

enum AudioDeviceEvent {
    case configurationChanged
    case willSleep
    case didWake
}

@MainActor
protocol AudioDeviceCoordinating: AnyObject {
    func observe(
        engine: AVAudioEngine,
        onEvent: @escaping @MainActor @Sendable (AudioDeviceEvent) -> Void
    )
    func stopObserving()
}

@MainActor
final class SystemAudioDeviceCoordinator: AudioDeviceCoordinating {
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    func observe(
        engine: AVAudioEngine,
        onEvent: @escaping @MainActor @Sendable (AudioDeviceEvent) -> Void
    ) {
        stopObserving()
        let configuration = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                onEvent(.configurationChanged)
            }
        }
        observers.append((.default, configuration))
        let workspace = NSWorkspace.shared.notificationCenter
        let sleep = workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                onEvent(.willSleep)
            }
        }
        let wake = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                onEvent(.didWake)
            }
        }
        observers.append((workspace, sleep))
        observers.append((workspace, wake))
    }

    func stopObserving() {
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    isolated deinit {
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
    }
}
