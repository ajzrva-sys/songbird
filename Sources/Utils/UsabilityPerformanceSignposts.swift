import AppKit
import Foundation
import OSLog

/// Usability-runtime-only correlation between native input, app state commits,
/// retained Points of Interest, and a lightweight live JSONL acknowledgment.
@MainActor
enum UsabilityPerformanceSignposts {
    private static let pointsOfInterest = OSLog(
        subsystem: "com.songbird.player",
        category: .pointsOfInterest
    )
    private static let recorderQueue = DispatchQueue(
        label: "com.songbird.player.usability-performance-events",
        qos: .utility
    )
    private static var monitors: [Any] = []
    private static var currentTraceID: UInt64 = 0

    static func installInputMonitorIfNeeded() {
        guard monitors.isEmpty, isTestingRuntime else { return }
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .keyDown,
            .scrollWheel,
        ]
        let monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            inputObserved(event)
            return event
        }
        if let monitor {
            monitors.append(monitor)
        }
    }

    static func inputObserved(_ event: NSEvent) {
        guard isTestingRuntime,
              let rawTrace = event.cgEvent?.getIntegerValueField(.eventSourceUserData),
              rawTrace > 0 else {
            return
        }
        currentTraceID = UInt64(rawTrace)
        emit("Input observed", traceID: currentTraceID)
    }

    static func selectionCommitted(revision: Int? = nil) {
        let traceID = currentTraceID
        emit("Selection commit", traceID: traceID, revision: revision)
        if traceID > 0 { currentTraceID = 0 }
    }

    static func destinationCommitted(revision: Int? = nil) {
        emit("Destination commit", traceID: currentTraceID, revision: revision)
    }

    static func usefulProjectionPublished(revision: Int? = nil) {
        let traceID = currentTraceID
        emit("Useful projection published", traceID: traceID, revision: revision)
        if traceID > 0 { currentTraceID = 0 }
    }

    private static func emit(
        _ name: StaticString,
        traceID: UInt64,
        revision: Int? = nil
    ) {
        guard traceID > 0 else { return }
        let revisionValue = Int64(revision ?? -1)
        os_signpost(
            .event,
            log: pointsOfInterest,
            name: name,
            "trace=%{public}llu revision=%{public}lld",
            traceID,
            revisionValue
        )
        record(
            event: String(describing: name),
            traceID: traceID,
            revision: revision,
            timestampNS: DispatchTime.now().uptimeNanoseconds
        )
    }

    private static func record(
        event: String,
        traceID: UInt64,
        revision: Int?,
        timestampNS: UInt64
    ) {
        guard let rootPath = SongbirdUIRuntime.testRoot(
            environment: ProcessInfo.processInfo.environment,
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        ) else {
            return
        }
        let record: [String: Any] = [
            "event": event,
            "revision": revision ?? -1,
            "timestamp_ns": timestampNS,
            "trace_id": traceID,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record),
              var line = String(data: data, encoding: .utf8) else {
            return
        }
        line.append("\n")
        let url = URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent("performance-events.jsonl")
        let bytes = Data(line.utf8)
        recorderQueue.async {
            if FileManager.default.fileExists(atPath: url.path) == false {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: bytes)
            } catch {
                return
            }
        }
    }

    private static var isTestingRuntime: Bool {
        SongbirdUIRuntime.isTesting(
            environment: ProcessInfo.processInfo.environment,
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        )
    }
}
