import AppKit
// ApplicationServices exposes its documented option-key constant through a
// legacy mutable C global. Keep compatibility handling scoped to this probe.
@preconcurrency import ApplicationServices
import Darwin
import Foundation

private let defaultBundleIdentifier = "com.songbird.player.usability"

private struct ProbeRequest: Codable {
    let id: String
    let serverEpoch: String
    let traceID: UInt64
    let command: String
    let arguments: [String]
}

private struct ProbeResponse: Codable {
    let id: String
    let serverEpoch: String
    let traceID: UInt64
    let ok: Bool
    let output: String
    let error: String?
    let startedAt: Date
    let finishedAt: Date
    let eventPostedAt: Date?
    let startedMonotonicNS: UInt64
    let eventPostedMonotonicNS: UInt64?
    let finishedMonotonicNS: UInt64
}

private struct ProbeServerState: Codable {
    enum Phase: String, Codable {
        case idle
        case busy
        case poisoned
    }

    let phase: Phase
    let serverEpoch: String
    let requestID: String?
    let updatedAt: Date
}

private struct AXFrame: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

private struct AXNode: Codable {
    let path: String
    let role: String?
    let subrole: String?
    let identifier: String?
    let title: String?
    let label: String?
    let value: String?
    let help: String?
    let enabled: Bool?
    let focused: Bool?
    let selected: Bool?
    let frame: AXFrame?
    let actions: [String]
    let children: [AXNode]
}

private struct AXAttributeDiagnostic: Codable {
    let attribute: String
    let errorCode: Int32
    let errorName: String
    let valueCount: Int?
    let value: String?
}

private struct CGWindowDiagnostic: Codable {
    let number: Int
    let name: String
    let layer: Int
    let alpha: Double
    let bounds: AXFrame?
}

private struct ObservationDiagnostic: Codable {
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
    let guiSessionPresent: Bool
    let onConsole: Bool?
    let loginComplete: Bool?
    let bundleIdentifier: String
    let matchingApplicationCount: Int
    let processID: Int32?
    let active: Bool?
    let expectedExecutablePath: String?
    let actualExecutablePath: String?
    let executableMatches: Bool?
    let cgWindows: [CGWindowDiagnostic]
    let messagingTimeoutErrorCode: Int32?
    let messagingTimeoutErrorName: String?
    let attributes: [AXAttributeDiagnostic]
}

private enum ProbeError: LocalizedError {
    case usage(String)
    case appNotRunning(String)
    case accessibilityPermission
    case elementNotFound(String)
    case ambiguousElement(String, Int)
    case actionUnavailable(String, String)
    case actionFailed(String)
    case invalidArgument(String)
    case screenshotFailed(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message), .actionFailed(let message), .invalidArgument(let message),
             .screenshotFailed(let message):
            return message
        case .appNotRunning(let bundleID):
            return "No running app has bundle identifier \(bundleID)."
        case .accessibilityPermission:
            return "Accessibility permission is not granted to SongbirdUIProbe. Run `permission --prompt`, then enable it in System Settings > Privacy & Security > Accessibility."
        case .elementNotFound(let selector):
            return "No accessibility element exactly matches \(selector)."
        case .ambiguousElement(let selector, let count):
            return "\(selector) matches \(count) accessibility elements. Use id=, title=, label=, role=, or append #N to disambiguate."
        case .actionUnavailable(let selector, let action):
            return "\(selector) does not expose \(action)."
        }
    }
}

@main
private enum SongbirdUIProbe {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let mode = arguments.first else { throw ProbeError.usage(usage) }
            switch mode {
            case "serve":
                try serve(arguments: Array(arguments.dropFirst()))
            case "client":
                try client(arguments: Array(arguments.dropFirst()))
            case "direct":
                try direct(arguments: Array(arguments.dropFirst()))
            case "launch-detached":
                try launchDetached(arguments: Array(arguments.dropFirst()))
            case "permission":
                let prompt = arguments.contains("--prompt")
                let trusted = AXIsProcessTrustedWithOptions([
                    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt,
                ] as CFDictionary)
                print(trusted ? "trusted" : "not-trusted")
                Foundation.exit(trusted ? EXIT_SUCCESS : EXIT_FAILURE)
            case "screen-permission":
                let trusted = arguments.contains("--prompt")
                    ? CGRequestScreenCaptureAccess()
                    : CGPreflightScreenCaptureAccess()
                print(trusted ? "trusted" : "not-trusted")
                Foundation.exit(trusted ? EXIT_SUCCESS : EXIT_FAILURE)
            case "help", "--help", "-h":
                print(usage)
            default:
                throw ProbeError.usage("Unknown mode: \(mode)\n\n\(usage)")
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static let usage = """
    SongbirdUIProbe — semantic macOS UI driver

      SongbirdUIProbe permission [--prompt]
      SongbirdUIProbe screen-permission [--prompt]
      SongbirdUIProbe serve --directory PATH [--bundle-id ID] [--test-root PATH] [--safe] [--detached]
      SongbirdUIProbe launch-detached --executable PATH --log PATH [ARGUMENTS...]
      SongbirdUIProbe client --directory PATH COMMAND [ARGUMENTS...]
      SongbirdUIProbe direct [--bundle-id ID] COMMAND [ARGUMENTS...]

    Commands: status, observation-diagnostic [EXPECTED_EXECUTABLE], wait-window [seconds],
          snapshot [depth], window-snapshot [depth], windows, activate, press SELECTOR,
          click SELECTOR [modifiers], double-click SELECTOR [modifiers],
          right-click SELECTOR [modifiers], action SELECTOR AXAction,
          click-point X Y [modifiers], double-click-point X Y [modifiers],
          right-click-point X Y [modifiers], drag-point X1 Y1 X2 Y2 [modifiers],
          scroll-point X Y DELTA_X DELTA_Y [modifiers],
          focus-window TITLE, set-window-frame TITLE X Y WIDTH HEIGHT,
          window-snapshot-title TITLE [depth], window-press TITLE SELECTOR,
          window-click TITLE SELECTOR [modifiers], window-set-value TITLE SELECTOR VALUE,
          measure-window-action TITLE OUTPUT_DIR ROI_X ROI_Y ROI_W ROI_H DURATION ACTION [ARGS...],
          set-value SELECTOR VALUE, key KEY [modifiers], wait SELECTOR [seconds],
          activate-menu-item TITLE [seconds], screenshot PATH,
          screenshot-window TITLE PATH
    """

    private static func option(
        _ name: String,
        in arguments: inout [String],
        default defaultValue: String? = nil
    ) throws -> String {
        guard let index = arguments.firstIndex(of: name) else {
            if let defaultValue { return defaultValue }
            throw ProbeError.usage("Missing \(name).")
        }
        guard arguments.indices.contains(index + 1) else {
            throw ProbeError.usage("Missing value after \(name).")
        }
        let value = arguments[index + 1]
        arguments.removeSubrange(index...(index + 1))
        return value
    }

    private static func serve(arguments: [String]) throws {
        var arguments = arguments
        let safeMode = arguments.contains("--safe")
        let detached = arguments.contains("--detached")
        arguments.removeAll { $0 == "--safe" || $0 == "--detached" }
        let directory = URL(fileURLWithPath: try option("--directory", in: &arguments))
        let testRoot = arguments.contains("--test-root")
            ? try option("--test-root", in: &arguments)
            : nil
        let bundleID = try option(
            "--bundle-id",
            in: &arguments,
            default: defaultBundleIdentifier
        )
        guard AXIsProcessTrusted() else { throw ProbeError.accessibilityPermission }
        if detached {
            try spawnDetachedServer(
                directory: directory,
                bundleID: bundleID,
                safeMode: safeMode,
                testRoot: testRoot
            )
            return
        }

        let requests = directory.appendingPathComponent("requests", isDirectory: true)
        let responses = directory.appendingPathComponent("responses", isDirectory: true)
        let serverEpoch = UUID().uuidString.lowercased()
        let quarantine = directory
            .appendingPathComponent("quarantine", isDirectory: true)
            .appendingPathComponent(serverEpoch, isDirectory: true)
        try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: responses, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
        try Data("\(ProcessInfo.processInfo.processIdentifier)\n".utf8).write(
            to: directory.appendingPathComponent("server.pid"),
            options: .atomic
        )
        let stateURL = directory.appendingPathComponent("server-state.json")
        try writeServerState(
            .init(
                phase: .idle,
                serverEpoch: serverEpoch,
                requestID: nil,
                updatedAt: Date()
            ),
            to: stateURL
        )
        print("SongbirdUIProbe serving \(bundleID) via \(directory.path)")
        fflush(stdout)

        while true {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: requests,
                includingPropertiesForKeys: nil
            ))?.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
            for file in files {
                autoreleasepool {
                    let startedAt = Date()
                    let startedMonotonicNS = DispatchTime.now().uptimeNanoseconds
                    let response: ProbeResponse
                    var eventPostedAt: Date?
                    var eventPostedMonotonicNS: UInt64?
                    var responseRequestID = file.deletingPathExtension().lastPathComponent
                    var responseTraceID: UInt64 = 0
                    do {
                        let request = try JSONDecoder().decode(
                            ProbeRequest.self,
                            from: Data(contentsOf: file)
                        )
                        responseRequestID = request.id
                        responseTraceID = request.traceID
                        guard request.serverEpoch == serverEpoch else {
                            throw ProbeError.actionFailed(
                                "Request belongs to stale broker epoch \(request.serverEpoch)."
                            )
                        }
                        try writeServerState(
                            .init(
                                phase: .busy,
                                serverEpoch: serverEpoch,
                                requestID: request.id,
                                updatedAt: Date()
                            ),
                            to: stateURL
                        )
                        let output = try execute(
                            command: request.command,
                            arguments: request.arguments,
                            bundleID: bundleID,
                            safeMode: safeMode,
                            allowedTestRoot: testRoot,
                            traceID: request.traceID,
                            eventPostedAt: &eventPostedAt,
                            eventPostedMonotonicNS: &eventPostedMonotonicNS
                        )
                        response = ProbeResponse(
                            id: request.id,
                            serverEpoch: serverEpoch,
                            traceID: request.traceID,
                            ok: true,
                            output: output,
                            error: nil,
                            startedAt: startedAt,
                            finishedAt: Date(),
                            eventPostedAt: eventPostedAt,
                            startedMonotonicNS: startedMonotonicNS,
                            eventPostedMonotonicNS: eventPostedMonotonicNS,
                            finishedMonotonicNS: DispatchTime.now().uptimeNanoseconds
                        )
                    } catch {
                        response = ProbeResponse(
                            id: responseRequestID,
                            serverEpoch: serverEpoch,
                            traceID: responseTraceID,
                            ok: false,
                            output: "",
                            error: error.localizedDescription,
                            startedAt: startedAt,
                            finishedAt: Date(),
                            eventPostedAt: eventPostedAt,
                            startedMonotonicNS: startedMonotonicNS,
                            eventPostedMonotonicNS: eventPostedMonotonicNS,
                            finishedMonotonicNS: DispatchTime.now().uptimeNanoseconds
                        )
                    }
                    do {
                        let currentState = try? readServerState(from: stateURL)
                        let wasPoisoned = currentState?.phase == .poisoned
                            && currentState?.requestID == response.id
                        let responseDirectory = wasPoisoned ? quarantine : responses
                        let responseURL = responseDirectory.appendingPathComponent(
                            response.id + ".json"
                        )
                        try JSONEncoder.usability.encode(response).write(
                            to: responseURL,
                            options: .atomic
                        )
                        try? FileManager.default.removeItem(at: file)
                        if wasPoisoned == false {
                            try writeServerState(
                                .init(
                                    phase: .idle,
                                    serverEpoch: serverEpoch,
                                    requestID: nil,
                                    updatedAt: Date()
                                ),
                                to: stateURL
                            )
                        }
                    } catch {
                        FileHandle.standardError.write(Data("server response error: \(error)\n".utf8))
                    }
                }
            }
            Thread.sleep(forTimeInterval: 0.04)
        }
    }

    private static func launchDetached(arguments: [String]) throws {
        var arguments = arguments
        let executable = try option("--executable", in: &arguments)
        let log = try option("--log", in: &arguments)
        let processID = try spawnDetached(
            executable: executable,
            arguments: [executable] + arguments,
            logPath: log
        )
        print(processID)
    }

    /// Starts a kept broker in a new process session so task runners that
    /// reap their child process group cannot terminate it on exit.
    private static func spawnDetachedServer(
        directory: URL,
        bundleID: String,
        safeMode: Bool,
        testRoot: String?
    ) throws {
        var spawnArguments = [
            CommandLine.arguments[0],
            "serve",
            "--directory",
            directory.path,
            "--bundle-id",
            bundleID,
        ]
        if safeMode {
            spawnArguments.append("--safe")
        }
        if let testRoot {
            spawnArguments += ["--test-root", testRoot]
        }

        _ = try spawnDetached(
            executable: spawnArguments[0],
            arguments: spawnArguments,
            logPath: nil
        )
    }

    @discardableResult
    private static func spawnDetached(
        executable: String,
        arguments: [String],
        logPath: String?
    ) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            throw ProbeError.actionFailed("Could not initialize detached process attributes.")
        }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID)) == 0 else {
            throw ProbeError.actionFailed("Could not create a new detached process session.")
        }

        var fileActions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            throw ProbeError.actionFailed("Could not initialize detached process file actions.")
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        guard posix_spawn_file_actions_addopen(
            &fileActions,
            STDIN_FILENO,
            "/dev/null",
            O_RDONLY,
            0
        ) == 0 else {
            throw ProbeError.actionFailed("Could not detach process input.")
        }

        if let logPath {
            let flags = O_WRONLY | O_CREAT | O_APPEND
            let permissions = mode_t(S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
            guard posix_spawn_file_actions_addopen(
                &fileActions,
                STDOUT_FILENO,
                logPath,
                flags,
                permissions
            ) == 0,
                posix_spawn_file_actions_addopen(
                    &fileActions,
                    STDERR_FILENO,
                    logPath,
                    flags,
                    permissions
                ) == 0
            else {
                throw ProbeError.actionFailed("Could not redirect detached process output.")
            }
        }

        let cArguments: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer {
            for argument in cArguments.dropLast() {
                free(argument)
            }
        }
        var mutableArguments = cArguments
        var processID: pid_t = 0
        let result = mutableArguments.withUnsafeMutableBufferPointer { buffer in
            posix_spawn(
                &processID,
                executable,
                &fileActions,
                &attributes,
                buffer.baseAddress,
                environ
            )
        }
        guard result == 0 else {
            throw ProbeError.actionFailed(
                "Could not spawn detached process: \(String(cString: strerror(result)))."
            )
        }
        return processID
    }

    private static func client(arguments: [String]) throws {
        var arguments = arguments
        let emitsJSON = arguments.contains("--json")
        arguments.removeAll { $0 == "--json" }
        let traceValue = try option(
            "--trace-id",
            in: &arguments,
            default: "0"
        )
        guard let traceID = UInt64(traceValue), traceID <= UInt64(Int64.max) else {
            throw ProbeError.invalidArgument("--trace-id must be a nonnegative 63-bit integer.")
        }
        let directory = URL(fileURLWithPath: try option("--directory", in: &arguments))
        guard let command = arguments.first else { throw ProbeError.usage(usage) }
        let stateURL = directory.appendingPathComponent("server-state.json")
        guard let state = try? readServerState(from: stateURL) else {
            throw ProbeError.actionFailed("The UI probe server has no readable state.")
        }
        guard state.phase == .idle else {
            let owner = state.requestID.map { " (request \($0))" } ?? ""
            throw ProbeError.actionFailed(
                "The UI probe session is \(state.phase.rawValue)\(owner). Restart it before another action."
            )
        }
        let request = ProbeRequest(
            id: UUID().uuidString.lowercased(),
            serverEpoch: state.serverEpoch,
            traceID: traceID,
            command: command,
            arguments: Array(arguments.dropFirst())
        )
        let requests = directory.appendingPathComponent("requests", isDirectory: true)
        let responses = directory.appendingPathComponent("responses", isDirectory: true)
        try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: responses, withIntermediateDirectories: true)
        let requestURL = requests.appendingPathComponent(request.id + ".json")
        try JSONEncoder.usability.encode(request).write(to: requestURL, options: .atomic)

        let responseURL = responses.appendingPathComponent(request.id + ".json")
        let commandTimeout: TimeInterval
        if request.command == "wait" {
            let requestedSeconds = Double(request.arguments.dropFirst().first ?? "5") ?? 5
            commandTimeout = max(0.1, min(requestedSeconds, 60)) + 5
        } else {
            commandTimeout = 30
        }
        let timeout = Date().addingTimeInterval(commandTimeout)
        while Date() < timeout {
            if let data = try? Data(contentsOf: responseURL),
               let response = try? JSONDecoder.usability.decode(ProbeResponse.self, from: data) {
                try? FileManager.default.removeItem(at: responseURL)
                let timing = String(
                    format: "%.1f",
                    Double(response.finishedMonotonicNS - response.startedMonotonicNS) / 1_000_000
                )
                let measurement: String
                if let eventPostedAt = response.eventPostedAt {
                    let lookup = response.eventPostedMonotonicNS.map {
                        Double($0 - response.startedMonotonicNS) / 1_000_000
                    } ?? eventPostedAt.timeIntervalSince(response.startedAt) * 1_000
                    let afterEvent = response.eventPostedMonotonicNS.map {
                        Double(response.finishedMonotonicNS - $0) / 1_000_000
                    } ?? response.finishedAt.timeIntervalSince(eventPostedAt) * 1_000
                    measurement = String(
                        format: " epoch=%@ request=%@ trace=%llu pre-event=%.1f ms event-to-probe-return=%.1f ms",
                        response.serverEpoch,
                        response.id,
                        response.traceID,
                        lookup,
                        afterEvent
                    )
                } else {
                    measurement = " epoch=\(response.serverEpoch) request=\(response.id) trace=\(response.traceID)"
                }
                if emitsJSON {
                    print(String(decoding: try JSONEncoder.usability.encode(response), as: UTF8.self))
                    if response.ok { return }
                    throw ProbeError.actionFailed(response.error ?? "Unknown UI probe error.")
                }
                if response.ok {
                    print(response.output)
                    FileHandle.standardError.write(
                        Data("[ui-probe total=\(timing) ms\(measurement)]\n".utf8)
                    )
                    return
                }
                throw ProbeError.actionFailed(response.error ?? "Unknown UI probe error.")
            }
            Thread.sleep(forTimeInterval: 0.04)
        }
        try? writeServerState(
            .init(
                phase: .poisoned,
                serverEpoch: request.serverEpoch,
                requestID: request.id,
                updatedAt: Date()
            ),
            to: stateURL
        )
        throw ProbeError.actionFailed("Timed out waiting for the UI probe server.")
    }

    private static func direct(arguments: [String]) throws {
        if ProcessInfo.processInfo.environment["SONGBIRD_USABILITY_PREPARED"] == "1" {
            throw ProbeError.actionFailed(
                "Direct probe access is disabled during a prepared usability run; use scripts/usability/ui."
            )
        }
        var arguments = arguments
        let bundleID = try option(
            "--bundle-id",
            in: &arguments,
            default: defaultBundleIdentifier
        )
        guard let command = arguments.first else { throw ProbeError.usage(usage) }
        var eventPostedAt: Date?
        var eventPostedMonotonicNS: UInt64?
        print(try execute(
            command: command,
            arguments: Array(arguments.dropFirst()),
            bundleID: bundleID,
            safeMode: false,
            allowedTestRoot: nil,
            traceID: 0,
            eventPostedAt: &eventPostedAt,
            eventPostedMonotonicNS: &eventPostedMonotonicNS
        ))
    }

    private static func execute(
        command: String,
        arguments: [String],
        bundleID: String,
        safeMode: Bool,
        allowedTestRoot: String?,
        traceID: UInt64,
        eventPostedAt: inout Date?,
        eventPostedMonotonicNS: inout UInt64?
    ) throws -> String {
        if safeMode {
            try enforceSafety(
                command: command,
                arguments: arguments,
                allowedTestRoot: allowedTestRoot
            )
        }
        if command == "status" {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            var status: [String: Any] = [
                "accessibility_trusted": AXIsProcessTrusted(),
                "bundle_identifier": bundleID,
                "running": apps.isEmpty == false,
            ]
            if let app = apps.first {
                let processID = app.processIdentifier
                status["pid"] = Int(processID)
                status["active"] = app.isActive
                let windowInfo = CGWindowListCopyWindowInfo(
                    [.optionOnScreenOnly, .excludeDesktopElements],
                    kCGNullWindowID
                ) as? [[String: Any]] ?? []
                let onScreenWindows = windowInfo.filter {
                    ($0[kCGWindowOwnerPID as String] as? Int32) == processID
                        && (($0[kCGWindowLayer as String] as? Int) ?? 1) == 0
                        && (($0[kCGWindowAlpha as String] as? Double) ?? 0) > 0
                }
                status["on_screen_window_count"] = onScreenWindows.count
                status["on_screen_windows"] = onScreenWindows.map {
                    [
                        "bounds": $0[kCGWindowBounds as String] ?? [:],
                        "name": $0[kCGWindowName as String] ?? "",
                        "number": $0[kCGWindowNumber as String] ?? 0,
                    ]
                }
            }
            return try jsonString(status)
        }
        if command == "observation-diagnostic" {
            return try jsonString(observationDiagnostic(
                bundleID: bundleID,
                expectedExecutablePath: arguments.first
            ))
        }
        guard AXIsProcessTrusted() else { throw ProbeError.accessibilityPermission }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            throw ProbeError.appNotRunning(bundleID)
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)

        if safeMode, hasSensitiveSystemWindow(root) {
            let selector = arguments.first?.lowercased() ?? ""
            let isCancel = ["cancel", "title=cancel", "label=cancel"].contains(selector)
            let isEscape = command == "key"
                && ["escape", "esc"].contains(arguments.first?.lowercased() ?? "")
            if ["windows", "window-snapshot", "screenshot", "screenshot-window"].contains(command)
                || (["press", "click", "double-click", "right-click", "action", "set-value"].contains(command)
                    && !isCancel)
                || ["window-press", "window-click", "window-set-value", "window-snapshot-title"]
                    .contains(command)
                || (command == "key" && !isEscape) {
                throw ProbeError.actionFailed(
                    "Blocked by safety policy: cancel the system file dialog without inspecting it."
                )
            }
        }

        switch command {
        case "wait-window":
            let seconds = Double(arguments.first ?? "30") ?? 30
            let deadline = Date().addingTimeInterval(max(0.1, min(seconds, 60)))
            repeat {
                if windowElements(root).isEmpty == false {
                    return "window ready"
                }
                Thread.sleep(forTimeInterval: 0.05)
            } while Date() < deadline
            throw ProbeError.actionFailed(
                "Songbird did not expose an AX window within \(String(format: "%.1f", seconds)) seconds."
            )
        case "snapshot":
            let depth = min(max(Int(arguments.first ?? "8") ?? 8, 1), 20)
            var remaining = 2_000
            let node = snapshot(root, path: "app", depth: depth, remaining: &remaining)
            return try jsonString(node)
        case "window-snapshot":
            let depth = min(max(Int(arguments.first ?? "10") ?? 10, 1), 20)
            let windows = windowElements(root)
            var remaining = 2_000
            return try jsonString(windows.enumerated().map {
                snapshot(
                    $1,
                    path: "window[\($0)]",
                    depth: depth,
                    remaining: &remaining
                )
            })
        case "window-snapshot-title":
            let title = try required(arguments, at: 0, command: command)
            let depth = min(max(Int(arguments.dropFirst().first ?? "10") ?? 10, 1), 20)
            let window = try exactWindow(title: title, in: root)
            var remaining = 2_000
            return try jsonString(snapshot(window, path: "window", depth: depth, remaining: &remaining))
        case "windows":
            let windows = windowElements(root)
            var remaining = 500
            return try jsonString(windows.enumerated().map {
                snapshot($1, path: "window[\($0)]", depth: 4, remaining: &remaining)
            })
        case "activate":
            app.activate(options: [.activateAllWindows])
            return "activated"
        case "focus-window":
            let title = try required(arguments, at: 0, command: command)
            let window = try exactWindow(title: title, in: root)
            let result = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            guard result == .success else {
                throw ProbeError.actionFailed("Could not focus window \(title): AX error \(result.rawValue).")
            }
            app.activate(options: [.activateAllWindows])
            return "focused window \(title)"
        case "set-window-frame":
            let title = try required(arguments, at: 0, command: command)
            let values = try pointValues(Array(arguments.dropFirst()), count: 4, command: command)
            guard values[2] >= 100, values[3] >= 100 else {
                throw ProbeError.actionFailed("Window width and height must be at least 100 points.")
            }
            let window = try exactWindow(title: title, in: root)
            var position = CGPoint(x: values[0], y: values[1])
            var size = CGSize(width: values[2], height: values[3])
            guard let positionValue = AXValueCreate(.cgPoint, &position),
                  let sizeValue = AXValueCreate(.cgSize, &size) else {
                throw ProbeError.actionFailed("Could not encode the requested window frame.")
            }
            let positionResult = AXUIElementSetAttributeValue(
                window, kAXPositionAttribute as CFString, positionValue
            )
            let sizeResult = AXUIElementSetAttributeValue(
                window, kAXSizeAttribute as CFString, sizeValue
            )
            guard positionResult == .success, sizeResult == .success else {
                throw ProbeError.actionFailed(
                    "Could not set window frame: AX errors \(positionResult.rawValue), \(sizeResult.rawValue)."
                )
            }
            return "set window frame \(title)"
        case "window-press":
            let title = try required(arguments, at: 0, command: command)
            let selector = try required(arguments, at: 1, command: command)
            let window = try exactWindow(title: title, in: root)
            let element = try find(selector, in: window)
            if safeMode {
                try enforceElementSafety(
                    element,
                    selector: selector,
                    allowedTestRoot: allowedTestRoot
                )
            }
            return try perform(kAXPressAction as String, on: element, selector: selector)
        case "window-set-value":
            let title = try required(arguments, at: 0, command: command)
            let selector = try required(arguments, at: 1, command: command)
            let value = try required(arguments, at: 2, command: command)
            let window = try exactWindow(title: title, in: root)
            let element = try find(selector, in: window)
            if safeMode {
                try enforceElementSafety(
                    element,
                    selector: selector,
                    allowedTestRoot: allowedTestRoot
                )
            }
            let result = AXUIElementSetAttributeValue(
                element,
                kAXValueAttribute as CFString,
                value as CFTypeRef
            )
            guard result == .success else {
                throw ProbeError.actionFailed(
                    "Could not set \(selector) in \(title): AX error \(result.rawValue)."
                )
            }
            return "value set in \(title)"
        case "window-click":
            let title = try required(arguments, at: 0, command: command)
            let selector = try required(arguments, at: 1, command: command)
            let window = try exactWindow(title: title, in: root)
            let element = try find(selector, in: window)
            if safeMode {
                try enforceElementSafety(
                    element,
                    selector: selector,
                    allowedTestRoot: allowedTestRoot
                )
            }
            guard let elementFrame = frame(element) else {
                throw ProbeError.actionFailed("\(selector) has no clickable frame.")
            }
            let point = CGPoint(
                x: elementFrame.x + elementFrame.width / 2,
                y: elementFrame.y + elementFrame.height / 2
            )
            eventPostedAt = Date()
            eventPostedMonotonicNS = DispatchTime.now().uptimeNanoseconds
            try postMouseClicks(
                at: point,
                flags: modifierFlags(arguments.count > 2 ? arguments[2] : nil),
                count: 1,
                traceID: traceID
            )
            return "clicked \(selector) in \(title)"
        case "measure-window-action":
            guard traceID > 0 else {
                throw ProbeError.invalidArgument(
                    "measure-window-action requires an explicit positive --trace-id."
                )
            }
            let title = try required(arguments, at: 0, command: command)
            let outputPath = try required(arguments, at: 1, command: command)
            let roiValues = try pointValues(
                Array(arguments.dropFirst(2)),
                count: 4,
                command: command
            )
            guard let duration = Double(try required(arguments, at: 6, command: command)),
                  duration.isFinite else {
                throw ProbeError.invalidArgument("measure-window-action duration is invalid.")
            }
            let measuredAction = try required(arguments, at: 7, command: command)
            let measuredArguments = Array(arguments.dropFirst(8))
            _ = try exactWindow(title: title, in: root)
            let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
                .standardizedFileURL
            if safeMode {
                try enforceMeasurementOutputSafety(
                    outputDirectory,
                    allowedTestRoot: allowedTestRoot
                )
            }
            let result = try WindowFrameMeasurement.measure(
                processID: app.processIdentifier,
                windowTitle: title,
                roi: CGRect(
                    x: roiValues[0],
                    y: roiValues[1],
                    width: roiValues[2],
                    height: roiValues[3]
                ),
                duration: duration,
                outputDirectory: outputDirectory
            ) {
                let postedNS = DispatchTime.now().uptimeNanoseconds
                eventPostedAt = Date()
                eventPostedMonotonicNS = postedNS
                switch measuredAction {
                case "click-point", "double-click-point", "right-click-point":
                    let values = try pointValues(
                        measuredArguments,
                        count: 2,
                        command: measuredAction
                    )
                    let point = CGPoint(x: values[0], y: values[1])
                    if safeMode { try enforcePointSafety(point, root: root) }
                    try postMouseClicks(
                        at: point,
                        flags: modifierFlags(
                            measuredArguments.count > 2 ? measuredArguments[2] : nil
                        ),
                        count: measuredAction == "double-click-point" ? 2 : 1,
                        button: measuredAction == "right-click-point" ? .right : .left,
                        traceID: traceID
                    )
                case "key":
                    let key = try required(measuredArguments, at: 0, command: measuredAction)
                    try postKey(
                        key,
                        flags: modifierFlags(measuredArguments.dropFirst().first),
                        traceID: traceID
                    )
                case "scroll-point":
                    let values = try pointValues(
                        measuredArguments,
                        count: 4,
                        command: measuredAction
                    )
                    let point = CGPoint(x: values[0], y: values[1])
                    if safeMode { try enforcePointSafety(point, root: root) }
                    try postScroll(
                        at: point,
                        deltaX: Int32(values[2]),
                        deltaY: Int32(values[3]),
                        flags: modifierFlags(
                            measuredArguments.count > 4 ? measuredArguments[4] : nil
                        ),
                        traceID: traceID
                    )
                default:
                    throw ProbeError.invalidArgument(
                        "Unsupported measured action: \(measuredAction)."
                    )
                }
                return postedNS
            }
            return try jsonString(result)
        case "press":
            let selector = try required(arguments, at: 0, command: command)
            let element = try find(selector, in: root)
            if safeMode { try enforceElementSafety(element, selector: selector, allowedTestRoot: allowedTestRoot) }
            return try perform(kAXPressAction as String, on: element, selector: selector)
        case "action":
            let selector = try required(arguments, at: 0, command: command)
            let action = try required(arguments, at: 1, command: command)
            let element = try find(selector, in: root)
            if safeMode { try enforceElementSafety(element, selector: selector, allowedTestRoot: allowedTestRoot) }
            return try perform(action, on: element, selector: selector)
        case "set-value":
            let selector = try required(arguments, at: 0, command: command)
            let value = try required(arguments, at: 1, command: command)
            let element = try find(selector, in: root)
            if safeMode { try enforceElementSafety(element, selector: selector, allowedTestRoot: allowedTestRoot) }
            let result = AXUIElementSetAttributeValue(
                element,
                kAXValueAttribute as CFString,
                value as CFTypeRef
            )
            guard result == .success else {
                throw ProbeError.actionFailed("Could not set \(selector): AX error \(result.rawValue).")
            }
            return "value set"
        case "click", "double-click", "right-click":
            let selector = try required(arguments, at: 0, command: command)
            let modifiers = modifierFlags(arguments.dropFirst().first)
            let element = try find(selector, in: root)
            if safeMode { try enforceElementSafety(element, selector: selector, allowedTestRoot: allowedTestRoot) }
            guard let frame = frame(element) else {
                throw ProbeError.actionFailed("\(selector) has no clickable frame.")
            }
            let point = CGPoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
            let clickCount = command == "double-click" ? 2 : 1
            let button: CGMouseButton = command == "right-click" ? .right : .left
            eventPostedAt = Date()
            eventPostedMonotonicNS = DispatchTime.now().uptimeNanoseconds
            try postMouseClicks(
                at: point,
                flags: modifiers,
                count: clickCount,
                button: button,
                traceID: traceID
            )
            if command == "right-click" { return "right-clicked \(selector)" }
            return clickCount == 2 ? "double-clicked \(selector)" : "clicked \(selector)"
        case "click-point", "double-click-point", "right-click-point":
            let values = try pointValues(arguments, count: 2, command: command)
            let point = CGPoint(x: values[0], y: values[1])
            if safeMode { try enforcePointSafety(point, root: root) }
            let modifiers = modifierFlags(arguments.count > 2 ? arguments[2] : nil)
            let clickCount = command == "double-click-point" ? 2 : 1
            let button: CGMouseButton = command == "right-click-point" ? .right : .left
            eventPostedAt = Date()
            eventPostedMonotonicNS = DispatchTime.now().uptimeNanoseconds
            try postMouseClicks(
                at: point,
                flags: modifiers,
                count: clickCount,
                button: button,
                traceID: traceID
            )
            return "\(command) at \(Int(point.x)),\(Int(point.y))"
        case "drag-point":
            let values = try pointValues(arguments, count: 4, command: command)
            let start = CGPoint(x: values[0], y: values[1])
            let end = CGPoint(x: values[2], y: values[3])
            if safeMode {
                try enforcePointSafety(start, root: root)
                try enforcePointSafety(end, root: root)
            }
            eventPostedAt = Date()
            eventPostedMonotonicNS = DispatchTime.now().uptimeNanoseconds
            try postDrag(
                from: start,
                to: end,
                flags: modifierFlags(arguments.count > 4 ? arguments[4] : nil),
                traceID: traceID
            )
            return "dragged from \(Int(start.x)),\(Int(start.y)) to \(Int(end.x)),\(Int(end.y))"
        case "scroll-point":
            let values = try pointValues(arguments, count: 4, command: command)
            let point = CGPoint(x: values[0], y: values[1])
            if safeMode { try enforcePointSafety(point, root: root) }
            eventPostedAt = Date()
            eventPostedMonotonicNS = DispatchTime.now().uptimeNanoseconds
            try postScroll(
                at: point,
                deltaX: Int32(values[2]),
                deltaY: Int32(values[3]),
                flags: modifierFlags(arguments.count > 4 ? arguments[4] : nil),
                traceID: traceID
            )
            return "scrolled at \(Int(point.x)),\(Int(point.y))"
        case "key":
            let key = try required(arguments, at: 0, command: command)
            if safeMode,
               ["return", "enter", "space"].contains(key.lowercased()),
               let focused = attribute(root, kAXFocusedUIElementAttribute as CFString) {
                try enforceElementSafety(
                    focused as! AXUIElement,
                    selector: "focused element",
                    allowedTestRoot: allowedTestRoot
                )
            }
            eventPostedAt = Date()
            eventPostedMonotonicNS = DispatchTime.now().uptimeNanoseconds
            try postKey(
                key,
                flags: modifierFlags(arguments.dropFirst().first),
                traceID: traceID
            )
            return "sent key \(key)"
        case "wait":
            let selector = try required(arguments, at: 0, command: command)
            let seconds = Double(arguments.dropFirst().first ?? "5") ?? 5
            let deadline = Date().addingTimeInterval(max(0.1, min(seconds, 60)))
            repeat {
                if (try? find(selector, in: root)) != nil { return "found \(selector)" }
                Thread.sleep(forTimeInterval: 0.05)
            } while Date() < deadline
            throw ProbeError.elementNotFound(selector)
        case "activate-menu-item":
            let title = try required(arguments, at: 0, command: command)
            let seconds = Double(arguments.dropFirst().first ?? "3") ?? 3
            let deadline = Date().addingTimeInterval(max(0.1, min(seconds, 10)))
            repeat {
                if let item = findMenuItem(title: title, in: root) {
                    if safeMode {
                        try enforceElementSafety(
                            item,
                            selector: title,
                            allowedTestRoot: allowedTestRoot
                        )
                    }
                    return try perform(kAXPressAction as String, on: item, selector: title)
                }
                Thread.sleep(forTimeInterval: 0.04)
            } while Date() < deadline
            throw ProbeError.elementNotFound("menu item title=\(title)")
        case "screenshot":
            let path = try required(arguments, at: 0, command: command)
            return try captureWindow(pid: app.processIdentifier, destination: path)
        case "screenshot-window":
            let title = try required(arguments, at: 0, command: command)
            let path = try required(arguments, at: 1, command: command)
            let window = try exactWindow(title: title, in: root)
            return try captureWindow(
                pid: app.processIdentifier,
                destination: path,
                title: title,
                expectedFrame: frame(window)
            )
        default:
            throw ProbeError.usage("Unknown probe command: \(command)")
        }
    }

    private static func enforceSafety(
        command: String,
        arguments: [String],
        allowedTestRoot: String?
    ) throws {
        if command == "snapshot" {
            throw ProbeError.actionFailed(
                "Blocked by safety policy: full-app snapshots can expose macOS Recent Items."
            )
        }

        if ["press", "click", "double-click", "right-click", "action", "set-value", "activate-menu-item"].contains(command),
           let selector = arguments.first,
           isApprovedDisposableFolderSelector(selector, allowedTestRoot: allowedTestRoot) == false,
           isSensitiveSelector(selector) {
            throw ProbeError.actionFailed(
                "Blocked by safety policy: \(selector) can leave the disposable profile or contact an external service."
            )
        }

        if ["window-press", "window-click", "window-set-value"].contains(command),
           arguments.indices.contains(1),
           isApprovedDisposableFolderSelector(
            arguments[1],
            allowedTestRoot: allowedTestRoot
           ) == false,
           isSensitiveSelector(arguments[1]) {
            throw ProbeError.actionFailed(
                "Blocked by safety policy: \(arguments[1]) can leave the disposable profile or contact an external service."
            )
        }

        if command == "key",
           arguments.first?.lowercased() == "o",
           arguments.dropFirst().first?.lowercased().contains("command") == true {
            throw ProbeError.actionFailed(
                "Blocked by safety policy: Command-O variants can open a filesystem picker."
            )
        }
    }

    private static func isSensitiveSelector(_ selector: String) -> Bool {
        let value = selector.lowercased()
        let fragments = [
            "scan folder", "scan other folder", "import files", "import library",
            "show in finder", "reveal in finder", "open file", "choose folder",
            "select folder", "log in", "sign in", "connect account", "authenticate",
            "authorize", "search album art", "search artwork", "find album art",
            "find missing artwork", "add artwork", "replace artwork", "add folder",
            "relocate folder", "export m3u", "test connection", "personal access token",
        ]
        return fragments.contains(where: value.contains) || value.hasPrefix("browse")
    }

    private static func enforceElementSafety(
        _ element: AXUIElement,
        selector: String,
        allowedTestRoot: String?
    ) throws {
        if isApprovedDisposableFolderSelector(selector, allowedTestRoot: allowedTestRoot) { return }
        let text = [
            string(element, kAXTitleAttribute),
            string(element, kAXDescriptionAttribute),
            string(element, kAXHelpAttribute),
            stringValue(element, kAXValueAttribute),
        ].compactMap { $0 }.joined(separator: " ")
        if isSensitiveSelector(text) {
            throw ProbeError.actionFailed(
                "Blocked by safety policy: \(selector) resolves to a protected external-data action."
            )
        }
    }

    private static func isApprovedDisposableFolderSelector(
        _ selector: String,
        allowedTestRoot: String?
    ) -> Bool {
        guard let allowedTestRoot,
              allowedTestRoot.hasPrefix("/"),
              allowedTestRoot.contains("/.build/usability/runs/"),
              allowedTestRoot.hasSuffix("/profile") else {
            return false
        }
        return [
            "id=usability.folder.addAndScan",
            "id=usability.folder.addWithoutScanning",
            "id=usability.folder.initialImport",
        ].contains(selector)
    }

    private static func hasSensitiveSystemWindow(_ root: AXUIElement) -> Bool {
        let blockedTitles = ["Open", "Save", "Choose", "Select Folder", "Choose Folder"]
        return windowElements(root).contains {
            guard let title = string($0, kAXTitleAttribute) else { return false }
            return blockedTitles.contains(title)
        }
    }

    private static func required(_ arguments: [String], at index: Int, command: String) throws -> String {
        guard arguments.indices.contains(index) else {
            throw ProbeError.usage("\(command) requires more arguments.")
        }
        return arguments[index]
    }

    private static func perform(
        _ action: String,
        on element: AXUIElement,
        selector: String
    ) throws -> String {
        var names: CFArray?
        AXUIElementCopyActionNames(element, &names)
        let actions = names as? [String] ?? []
        guard actions.contains(action) else { throw ProbeError.actionUnavailable(selector, action) }
        let result = AXUIElementPerformAction(element, action as CFString)
        guard result == .success else {
            throw ProbeError.actionFailed("\(action) failed for \(selector): AX error \(result.rawValue).")
        }
        return "performed \(action) on \(selector)"
    }

    private static func find(_ rawSelector: String, in root: AXUIElement) throws -> AXUIElement {
        let parts = rawSelector.split(separator: "#", maxSplits: 1).map(String.init)
        let selector = parts[0]
        let requestedOccurrence = parts.count == 2 ? Int(parts[1]) : nil
        let constraint: (String?, String)
        if let separator = selector.firstIndex(of: "=") {
            constraint = (
                String(selector[..<separator]).lowercased(),
                String(selector[selector.index(after: separator)...])
            )
        } else {
            constraint = (nil, selector)
        }
        var matchingElements: [AXUIElement] = []
        var remaining = 4_000
        _ = walk(root, depth: 20, remaining: &remaining) { element in
            if matches(element, field: constraint.0, expected: constraint.1) {
                matchingElements.append(element)
            }
            if let occurrence = requestedOccurrence {
                return matchingElements.count < occurrence
            }
            return matchingElements.count < 2
        }
        if matchingElements.isEmpty {
            for window in windowElements(root) {
                guard remaining > 0 else { break }
                _ = walk(window, depth: 20, remaining: &remaining) { element in
                    if matches(element, field: constraint.0, expected: constraint.1) {
                        matchingElements.append(element)
                    }
                    if let occurrence = requestedOccurrence {
                        return matchingElements.count < occurrence
                    }
                    return matchingElements.count < 2
                }
            }
        }
        if let occurrence = requestedOccurrence {
            guard occurrence > 0, matchingElements.indices.contains(occurrence - 1) else {
                throw ProbeError.elementNotFound(rawSelector)
            }
            return matchingElements[occurrence - 1]
        }
        guard let only = matchingElements.first else { throw ProbeError.elementNotFound(rawSelector) }
        guard matchingElements.count == 1 else {
            throw ProbeError.ambiguousElement(rawSelector, matchingElements.count)
        }
        return only
    }

    private static func findMenuItem(title: String, in root: AXUIElement) -> AXUIElement? {
        var remaining = 2_000
        var match: AXUIElement?
        _ = walk(root, depth: 12, remaining: &remaining) { element in
            guard string(element, kAXRoleAttribute) == (kAXMenuItemRole as String),
                  string(element, kAXTitleAttribute) == title else {
                return true
            }
            match = element
            return false
        }
        return match
    }

    private static func matches(_ element: AXUIElement, field: String?, expected: String) -> Bool {
        let expected = expected.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
        let candidates: [String?]
        switch field {
        case "id", "identifier": candidates = [string(element, kAXIdentifierAttribute)]
        case "title": candidates = [string(element, kAXTitleAttribute)]
        case "label": candidates = [
            string(element, kAXDescriptionAttribute),
            string(element, kAXTitleAttribute),
        ]
        case "role": candidates = [string(element, kAXRoleAttribute)]
        case "value": candidates = [stringValue(element, kAXValueAttribute)]
        case nil: candidates = [
            string(element, kAXIdentifierAttribute),
            string(element, kAXTitleAttribute),
            string(element, kAXDescriptionAttribute),
            stringValue(element, kAXValueAttribute),
        ]
        default: return false
        }
        return candidates.compactMap { $0?.localizedLowercase }.contains(expected)
    }

    private static func walk(
        _ element: AXUIElement,
        depth: Int,
        remaining: inout Int,
        visit: (AXUIElement) -> Bool
    ) -> Bool {
        guard depth >= 0, remaining > 0 else { return true }
        remaining -= 1
        guard visit(element) else { return false }
        for child in elements(element, attribute: kAXChildrenAttribute as CFString) {
            guard remaining > 0 else { break }
            guard walk(child, depth: depth - 1, remaining: &remaining, visit: visit) else {
                return false
            }
        }
        return true
    }

    private static func snapshot(
        _ element: AXUIElement,
        path: String,
        depth: Int,
        remaining: inout Int
    ) -> AXNode {
        remaining -= 1
        let children: [AXNode]
        if depth > 0, remaining > 0 {
            children = elements(element, attribute: kAXChildrenAttribute as CFString)
                .enumerated()
                .prefix(max(0, remaining))
                .map { snapshot(
                    $0.element,
                    path: path + ".children[\($0.offset)]",
                    depth: depth - 1,
                    remaining: &remaining
                ) }
        } else {
            children = []
        }
        var actionNames: CFArray?
        AXUIElementCopyActionNames(element, &actionNames)
        return AXNode(
            path: path,
            role: string(element, kAXRoleAttribute),
            subrole: string(element, kAXSubroleAttribute),
            identifier: string(element, kAXIdentifierAttribute),
            title: string(element, kAXTitleAttribute),
            label: string(element, kAXDescriptionAttribute),
            value: stringValue(element, kAXValueAttribute),
            help: string(element, kAXHelpAttribute),
            enabled: bool(element, kAXEnabledAttribute),
            focused: bool(element, kAXFocusedAttribute),
            selected: bool(element, kAXSelectedAttribute),
            frame: frame(element),
            actions: actionNames as? [String] ?? [],
            children: children
        )
    }

    private static func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    private static func observationDiagnostic(
        bundleID: String,
        expectedExecutablePath: String?
    ) -> ObservationDiagnostic {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let app = apps.first
        let processID = app?.processIdentifier
        let actualExecutablePath = app?.executableURL?.standardizedFileURL.path
        let normalizedExpected = expectedExecutablePath.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }
        let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        let cgWindows: [CGWindowDiagnostic]
        if let processID {
            cgWindows = windowInfo.compactMap { info in
                guard (info[kCGWindowOwnerPID as String] as? Int32) == processID,
                      ((info[kCGWindowLayer as String] as? Int) ?? 1) == 0 else {
                    return nil
                }
                return CGWindowDiagnostic(
                    number: info[kCGWindowNumber as String] as? Int ?? 0,
                    name: info[kCGWindowName as String] as? String ?? "",
                    layer: info[kCGWindowLayer as String] as? Int ?? 0,
                    alpha: info[kCGWindowAlpha as String] as? Double ?? 0,
                    bounds: cgWindowFrame(info[kCGWindowBounds as String])
                )
            }
        } else {
            cgWindows = []
        }

        var timeoutCode: Int32?
        var timeoutName: String?
        var diagnostics: [AXAttributeDiagnostic] = []
        if AXIsProcessTrusted(), let processID {
            let root = AXUIElementCreateApplication(processID)
            let timeoutResult = AXUIElementSetMessagingTimeout(root, 2)
            timeoutCode = timeoutResult.rawValue
            timeoutName = axErrorName(timeoutResult)
            diagnostics = [
                diagnostic(root, attribute: kAXRoleAttribute as CFString),
                diagnostic(root, attribute: kAXWindowsAttribute as CFString),
                diagnostic(root, attribute: kAXMainWindowAttribute as CFString),
                diagnostic(root, attribute: kAXFocusedWindowAttribute as CFString),
            ]
        }

        return ObservationDiagnostic(
            accessibilityTrusted: AXIsProcessTrusted(),
            screenCaptureTrusted: CGPreflightScreenCaptureAccess(),
            guiSessionPresent: session != nil,
            onConsole: session?[kCGSessionOnConsoleKey as String] as? Bool,
            loginComplete: session?[kCGSessionLoginDoneKey as String] as? Bool,
            bundleIdentifier: bundleID,
            matchingApplicationCount: apps.count,
            processID: processID,
            active: app?.isActive,
            expectedExecutablePath: normalizedExpected,
            actualExecutablePath: actualExecutablePath,
            executableMatches: normalizedExpected.flatMap { expected in
                actualExecutablePath.map { expected == $0 }
            },
            cgWindows: cgWindows,
            messagingTimeoutErrorCode: timeoutCode,
            messagingTimeoutErrorName: timeoutName,
            attributes: diagnostics
        )
    }

    private static func diagnostic(
        _ element: AXUIElement,
        attribute name: CFString
    ) -> AXAttributeDiagnostic {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        let valueCount: Int?
        let summary: String?
        if error != .success || value == nil {
            valueCount = nil
            summary = nil
        } else if let values = value as? [AXUIElement] {
            valueCount = values.count
            summary = values.map { child in
                let role = string(child, kAXRoleAttribute) ?? "<no role>"
                let title = string(child, kAXTitleAttribute) ?? ""
                return title.isEmpty ? role : "\(role):\(title)"
            }.joined(separator: ", ")
        } else if let text = value as? String {
            valueCount = 1
            summary = text
        } else if let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            valueCount = 1
            summary = "AXUIElement"
        } else {
            valueCount = 1
            summary = value.map(String.init(describing:))
        }
        return AXAttributeDiagnostic(
            attribute: name as String,
            errorCode: error.rawValue,
            errorName: axErrorName(error),
            valueCount: valueCount,
            value: summary
        )
    }

    private static func axErrorName(_ error: AXError) -> String {
        switch error {
        case .success: "success"
        case .failure: "failure"
        case .illegalArgument: "illegalArgument"
        case .invalidUIElement: "invalidUIElement"
        case .invalidUIElementObserver: "invalidUIElementObserver"
        case .cannotComplete: "cannotComplete"
        case .attributeUnsupported: "attributeUnsupported"
        case .actionUnsupported: "actionUnsupported"
        case .notificationUnsupported: "notificationUnsupported"
        case .notImplemented: "notImplemented"
        case .notificationAlreadyRegistered: "notificationAlreadyRegistered"
        case .notificationNotRegistered: "notificationNotRegistered"
        case .apiDisabled: "apiDisabled"
        case .noValue: "noValue"
        case .parameterizedAttributeUnsupported: "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: "notEnoughPrecision"
        @unknown default: "unknown"
        }
    }

    private static func cgWindowFrame(_ value: Any?) -> AXFrame? {
        guard let bounds = value as? [String: Any],
              let x = (bounds["X"] as? NSNumber)?.doubleValue,
              let y = (bounds["Y"] as? NSNumber)?.doubleValue,
              let width = (bounds["Width"] as? NSNumber)?.doubleValue,
              let height = (bounds["Height"] as? NSNumber)?.doubleValue else {
            return nil
        }
        return AXFrame(x: x, y: y, width: width, height: height)
    }

    private static func elements(_ element: AXUIElement, attribute name: CFString) -> [AXUIElement] {
        attribute(element, name) as? [AXUIElement] ?? []
    }

    /// Some macOS menu transitions can temporarily make `AXWindows` return the
    /// application element itself. Accept only actual windows and fall back to
    /// the application's main/focused-window attributes when that occurs.
    private static func windowElements(_ root: AXUIElement) -> [AXUIElement] {
        let listed = elements(root, attribute: kAXWindowsAttribute as CFString).filter {
            string($0, kAXRoleAttribute) == (kAXWindowRole as String)
        }
        if listed.isEmpty == false { return listed }

        var recovered: [AXUIElement] = []
        for name in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            guard let value = attribute(root, name as CFString),
                  CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
            let window = value as! AXUIElement
            guard string(window, kAXRoleAttribute) == (kAXWindowRole as String),
                  recovered.contains(where: { CFEqual($0, window) }) == false else { continue }
            recovered.append(window)
        }
        return recovered
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name as CFString) as? String
    }

    private static func stringValue(_ element: AXUIElement, _ name: String) -> String? {
        guard let value = attribute(element, name as CFString) else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if CFGetTypeID(value) == AXValueGetTypeID() { return nil }
        return String(describing: value)
    }

    private static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        (attribute(element, name as CFString) as? NSNumber)?.boolValue
    }

    private static func frame(_ element: AXUIElement) -> AXFrame? {
        guard let positionValue = attribute(element, kAXPositionAttribute as CFString),
              let sizeValue = attribute(element, kAXSizeAttribute as CFString),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return AXFrame(
            x: position.x,
            y: position.y,
            width: size.width,
            height: size.height
        )
    }

    private static func modifierFlags(_ raw: String?) -> CGEventFlags {
        guard let raw else { return [] }
        return raw.split(separator: ",").reduce(into: CGEventFlags()) { flags, part in
            switch part.trimmingCharacters(in: .whitespaces).lowercased() {
            case "command", "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "option", "alt": flags.insert(.maskAlternate)
            case "control", "ctrl": flags.insert(.maskControl)
            default: break
            }
        }
    }

    private static func pointValues(
        _ arguments: [String],
        count: Int,
        command: String
    ) throws -> [CGFloat] {
        guard arguments.count >= count else {
            throw ProbeError.usage("\(command) requires \(count) numeric coordinate values.")
        }
        return try arguments.prefix(count).map { raw in
            guard let value = Double(raw), value.isFinite else {
                throw ProbeError.usage("\(command) received an invalid coordinate: \(raw)")
            }
            return CGFloat(value)
        }
    }

    private static func exactWindow(title: String, in root: AXUIElement) throws -> AXUIElement {
        let matches = windowElements(root).filter {
            (attribute($0, kAXTitleAttribute as CFString) as? String) == title
        }
        guard matches.count == 1, let window = matches.first else {
            throw ProbeError.actionFailed(
                matches.isEmpty
                    ? "No window exactly matches \(title)."
                    : "More than one window matches \(title)."
            )
        }
        return window
    }

    private static func enforcePointSafety(_ point: CGPoint, root: AXUIElement) throws {
        let isInsideSongbirdWindow = windowElements(root).contains { window in
            guard let frame = frame(window) else { return false }
            return CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
                .contains(point)
        }
        guard isInsideSongbirdWindow else {
            throw ProbeError.actionFailed(
                "Blocked by safety policy: coordinate is outside every Songbird window."
            )
        }
    }

    private static func enforceMeasurementOutputSafety(
        _ outputDirectory: URL,
        allowedTestRoot: String?
    ) throws {
        guard let allowedTestRoot else {
            throw ProbeError.actionFailed(
                "Blocked by safety policy: no disposable test root was configured."
            )
        }
        let profile = URL(fileURLWithPath: allowedTestRoot, isDirectory: true)
            .standardizedFileURL
        let runRoot = profile.deletingLastPathComponent()
        let prefix = runRoot.path.hasSuffix("/") ? runRoot.path : runRoot.path + "/"
        guard runRoot.path.contains("/.build/usability/runs/"),
              outputDirectory.path.hasPrefix(prefix) else {
            throw ProbeError.actionFailed(
                "Blocked by safety policy: frame evidence must stay inside the disposable run."
            )
        }
    }

    private static func postMouseClicks(
        at point: CGPoint,
        flags: CGEventFlags,
        count: Int,
        button: CGMouseButton = .left,
        traceID: UInt64
    ) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ProbeError.actionFailed("Could not create a mouse event source.")
        }
        let downType: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        for clickIndex in 1...max(1, count) {
            guard let down = CGEvent(
                    mouseEventSource: source,
                    mouseType: downType,
                    mouseCursorPosition: point,
                    mouseButton: button
                  ),
                  let up = CGEvent(
                    mouseEventSource: source,
                    mouseType: upType,
                    mouseCursorPosition: point,
                    mouseButton: button
                  ) else {
                throw ProbeError.actionFailed("Could not create mouse events.")
            }
            let clickState = Int64(clickIndex)
            down.setIntegerValueField(.mouseEventClickState, value: clickState)
            up.setIntegerValueField(.mouseEventClickState, value: clickState)
            down.setIntegerValueField(.eventSourceUserData, value: Int64(traceID))
            up.setIntegerValueField(.eventSourceUserData, value: Int64(traceID))
            down.flags = flags
            up.flags = flags
            down.post(tap: .cghidEventTap)
            usleep(20_000)
            up.post(tap: .cghidEventTap)
            if clickIndex < count {
                usleep(80_000)
            }
        }
    }

    private static func postDrag(
        from start: CGPoint,
        to end: CGPoint,
        flags: CGEventFlags,
        traceID: UInt64
    ) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: start,
                mouseButton: .left
              ),
              let drag = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: end,
                mouseButton: .left
              ),
              let up = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: end,
                mouseButton: .left
              ) else {
            throw ProbeError.actionFailed("Could not create drag events.")
        }
        down.flags = flags
        drag.flags = flags
        up.flags = flags
        for event in [down, drag, up] {
            event.setIntegerValueField(.eventSourceUserData, value: Int64(traceID))
        }
        down.post(tap: .cghidEventTap)
        usleep(50_000)
        for step in 1...8 {
            let fraction = CGFloat(step) / 8
            let point = CGPoint(
                x: start.x + (end.x - start.x) * fraction,
                y: start.y + (end.y - start.y) * fraction
            )
            guard let move = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else { continue }
            move.flags = flags
            move.setIntegerValueField(.eventSourceUserData, value: Int64(traceID))
            move.post(tap: .cghidEventTap)
            usleep(20_000)
        }
        drag.post(tap: .cghidEventTap)
        usleep(20_000)
        up.post(tap: .cghidEventTap)
    }

    private static func postKey(_ key: String, flags: CGEventFlags, traceID: UInt64) throws {
        let keyCodes: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
            "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
            "n": 45, "m": 46, ".": 47, "`": 50,
            "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51,
            "escape": 53, "esc": 53, "left": 123, "right": 124, "down": 125,
            "up": 126,
        ]
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ProbeError.actionFailed("Could not create keyboard event source.")
        }
        let normalized = key.lowercased()
        let keyCode = keyCodes[normalized] ?? 0
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw ProbeError.actionFailed("Could not create keyboard events.")
        }
        if keyCodes[normalized] == nil {
            let utf16 = Array(key.utf16)
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: Int64(traceID))
        up.setIntegerValueField(.eventSourceUserData, value: Int64(traceID))
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func postScroll(
        at point: CGPoint,
        deltaX: Int32,
        deltaY: Int32,
        flags: CGEventFlags,
        traceID: UInt64
    ) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 2,
                wheel1: deltaY,
                wheel2: deltaX,
                wheel3: 0
              ) else {
            throw ProbeError.actionFailed("Could not create scroll event.")
        }
        event.location = point
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: Int64(traceID))
        event.post(tap: .cghidEventTap)
    }

    private static func captureWindow(
        pid: pid_t,
        destination: String,
        title: String? = nil,
        expectedFrame: AXFrame? = nil
    ) throws -> String {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            throw ProbeError.screenshotFailed("Could not enumerate windows.")
        }
        let candidates = info.filter {
            ($0[kCGWindowOwnerPID as String] as? Int32) == pid
                && (($0[kCGWindowLayer as String] as? Int) ?? 1) == 0
                && (($0[kCGWindowAlpha as String] as? Double) ?? 0) > 0
        }
        let titled = title.map { expected in
            candidates.filter { ($0[kCGWindowName as String] as? String) == expected }
        } ?? []
        let eligible = titled.isEmpty ? candidates : titled
        let best: [String: Any]?
        if let expectedFrame {
            best = eligible.min {
                windowDistance($0, expected: expectedFrame)
                    < windowDistance($1, expected: expectedFrame)
            }
        } else {
            best = eligible.max { windowArea($0) < windowArea($1) }
        }
        guard let number = best?[kCGWindowNumber as String] as? Int else {
            throw ProbeError.screenshotFailed("Songbird has no capturable on-screen window.")
        }
        let url = URL(fileURLWithPath: destination)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-l", String(number), url.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: url.path) else {
            throw ProbeError.screenshotFailed(
                "Window capture failed. Grant Screen Recording permission to SongbirdUIProbe."
            )
        }
        return url.path
    }

    private static func windowArea(_ info: [String: Any]) -> Double {
        guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? Double,
              let height = bounds["Height"] as? Double else { return 0 }
        return width * height
    }

    private static func windowDistance(
        _ info: [String: Any],
        expected: AXFrame
    ) -> Double {
        guard let frame = cgWindowFrame(info[kCGWindowBounds as String]) else {
            return .greatestFiniteMagnitude
        }
        let dx = frame.x - expected.x
        let dy = frame.y - expected.y
        let dw = frame.width - expected.width
        let dh = frame.height - expected.height
        return dx * dx + dy * dy + dw * dw + dh * dh
    }

    private static func writeServerState(
        _ state: ProbeServerState,
        to url: URL
    ) throws {
        try JSONEncoder.usability.encode(state).write(to: url, options: .atomic)
    }

    private static func readServerState(from url: URL) throws -> ProbeServerState {
        try JSONDecoder.usability.decode(ProbeServerState.self, from: Data(contentsOf: url))
    }

    private static func jsonString<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder.usability.encode(value), as: UTF8.self)
    }

    private static func jsonString(_ value: [String: Any]) throws -> String {
        String(
            decoding: try JSONSerialization.data(
                withJSONObject: value,
                options: [.prettyPrinted, .sortedKeys]
            ),
            as: UTF8.self
        )
    }
}

private extension JSONEncoder {
    static var usability: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}

private extension JSONDecoder {
    static var usability: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
