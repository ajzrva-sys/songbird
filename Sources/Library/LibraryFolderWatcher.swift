import Foundation
import CoreServices
import AppKit
import SwiftData

struct LibraryFolderImportCycle {
    private(set) var isRunning = false
    private(set) var hasPendingRequest = false

    mutating func request() -> Bool {
        hasPendingRequest = true
        guard isRunning == false else { return false }
        isRunning = true
        hasPendingRequest = false
        return true
    }

    mutating func completeAndBeginNextIfNeeded() -> Bool {
        guard isRunning else { return false }
        guard hasPendingRequest else {
            isRunning = false
            return false
        }
        hasPendingRequest = false
        return true
    }

    mutating func cancel() {
        isRunning = false
        hasPendingRequest = false
    }
}

struct LibraryFolderEventFilter {
    static func importablePaths(
        _ eventPaths: Set<String>,
        watchedRoots: [String]
    ) -> Set<String> {
        let roots = Set(watchedRoots.map { ($0 as NSString).standardizingPath })
        return Set(eventPaths.filter { path in
            roots.contains((path as NSString).standardizingPath) == false
        })
    }
}

struct LibraryFolderWatchPolicy {
    static func watchablePaths(
        _ paths: [String],
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        volumeIsLocal: (URL) -> Bool? = { url in
            let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey])
            return values?.volumeIsLocal
        }
    ) -> [String] {
        paths
            .map { ($0 as NSString).standardizingPath }
            .filter { path in
                guard !path.isEmpty, fileExists(path) else { return false }
                let url = URL(fileURLWithPath: path, isDirectory: true)
                // Fail closed so an unavailable locality value cannot start
                // automatic work against a remote or unclassified volume.
                return volumeIsLocal(url) == true
            }
    }
}

public enum LibraryFolderMode: String, Codable, Sendable {
    case watching
    case manualScanOnly
}

public struct LibraryFolderConfiguration: Codable, Hashable, Identifiable, Sendable {
    public let path: String
    public var mode: LibraryFolderMode

    public var id: String { path }

    public init(path: String, mode: LibraryFolderMode) {
        self.path = (path as NSString).standardizingPath
        self.mode = mode
    }
}

public struct LibraryFolderSetupOutcome: Equatable, Sendable {
    public let configurations: [LibraryFolderConfiguration]
    public let scannedPaths: [String]
    public let manualOnlyPaths: [String]

    public init(
        configurations: [LibraryFolderConfiguration],
        scannedPaths: [String],
        manualOnlyPaths: [String]
    ) {
        self.configurations = configurations
        self.scannedPaths = scannedPaths
        self.manualOnlyPaths = manualOnlyPaths
    }
}

/// The shared Settings/first-run boundary for persisting folder intent,
/// optionally starting one explicit scan, and refreshing automatic watching.
@MainActor
public struct LibraryFolderSetupCoordinator {
    private let appendConfigurations: ([String], LibraryFolderMode) -> [LibraryFolderConfiguration]
    private let applyWatching: () -> Void
    private let startScan: ([URL]) -> Void
    private let fileExists: (String) -> Bool

    public init(
        appendConfigurations: @escaping ([String], LibraryFolderMode) -> [LibraryFolderConfiguration],
        applyWatching: @escaping () -> Void,
        startScan: @escaping ([URL]) -> Void,
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.appendConfigurations = appendConfigurations
        self.applyWatching = applyWatching
        self.startScan = startScan
        self.fileExists = fileExists
    }

    public static var live: Self {
        Self(
            appendConfigurations: { paths, mode in
                LibraryFolderConfigurationStore.append(paths: paths, preferredMode: mode)
            },
            applyWatching: { LibraryFolderWatcher.shared.applySettingsFromDefaults() },
            startScan: { LibraryImportCoordinator.shared.start($0) }
        )
    }

    @discardableResult
    public func add(
        _ urls: [URL],
        scanImmediately: Bool,
        preferredMode: LibraryFolderMode = .watching
    ) -> LibraryFolderSetupOutcome {
        let standardized = urls.map(\.standardizedFileURL)
        let configurations = appendConfigurations(standardized.map(\.path), preferredMode)
        applyWatching()
        let available = standardized.filter { fileExists($0.path) }
        if scanImmediately, available.isEmpty == false {
            startScan(available)
        }
        let selectedPaths = Set(standardized.map(\.path))
        let manualOnly = configurations
            .filter { selectedPaths.contains($0.path) && $0.mode == .manualScanOnly }
            .map(\.path)
        return LibraryFolderSetupOutcome(
            configurations: configurations,
            scannedPaths: scanImmediately ? available.map(\.path) : [],
            manualOnlyPaths: manualOnly
        )
    }
}

@MainActor
public enum LibraryFolderConfigurationStore {
    public static let configurationsKey = "songbird.libraryFolderConfigurations.v1"
    private static let migrationKey = "songbird.libraryFolderConfigurations.didMigrate"

    public static func load(defaults: UserDefaults = .standard) -> [LibraryFolderConfiguration] {
        migrateIfNeeded(defaults: defaults)
        guard let data = defaults.data(forKey: configurationsKey),
              let decoded = try? JSONDecoder().decode([LibraryFolderConfiguration].self, from: data) else {
            return []
        }
        return normalized(decoded)
    }

    public static func save(
        _ configurations: [LibraryFolderConfiguration],
        defaults: UserDefaults = .standard
    ) {
        let configurations = normalized(configurations)
        if let data = try? JSONEncoder().encode(configurations) {
            defaults.set(data, forKey: configurationsKey)
        }
        defaults.set(true, forKey: migrationKey)
        let paths = configurations.map(\.path)
        if let pathData = try? JSONEncoder().encode(paths),
           let rawPaths = String(data: pathData, encoding: .utf8) {
            defaults.set(rawPaths, forKey: LibraryFolderWatcher.pathsKey)
        }
        if let first = paths.first {
            defaults.set(first, forKey: LibraryFolderWatcher.pathKey)
        } else {
            defaults.removeObject(forKey: LibraryFolderWatcher.pathKey)
        }
        defaults.set(configurations.contains { $0.mode == .watching }, forKey: LibraryFolderWatcher.enabledKey)
    }

    @discardableResult
    public static func append(
        paths: [String],
        preferredMode: LibraryFolderMode,
        defaults: UserDefaults = .standard,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        volumeIsLocal: (URL) -> Bool? = { try? $0.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal }
    ) -> [LibraryFolderConfiguration] {
        var configurations = load(defaults: defaults)
        for rawPath in paths {
            let path = (rawPath as NSString).standardizingPath
            guard path.isEmpty == false else { continue }
            let requestedWatching = preferredMode == .watching
            let available = fileExists(path)
            let local = available
                ? volumeIsLocal(URL(fileURLWithPath: path, isDirectory: true)) == true
                : requestedWatching
            let mode: LibraryFolderMode = requestedWatching && local ? .watching : .manualScanOnly
            if let index = configurations.firstIndex(where: { $0.path == path }) {
                configurations[index].mode = mode
            } else {
                configurations.append(.init(path: path, mode: mode))
            }
        }
        save(configurations, defaults: defaults)
        return configurations
    }

    public static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: migrationKey) == false else { return }
        LibraryFolderWatcher.migrateLegacyPathIfNeeded(defaults: defaults)
        let paths = LibraryFolderWatcher.decodePaths(defaults.string(forKey: LibraryFolderWatcher.pathsKey) ?? "[]")
        let legacyEnabled = defaults.bool(forKey: LibraryFolderWatcher.enabledKey)
        let configurations = paths.map { path in
            let watchable = legacyEnabled && LibraryFolderWatchPolicy.watchablePaths([path]).isEmpty == false
            return LibraryFolderConfiguration(path: path, mode: watchable ? .watching : .manualScanOnly)
        }
        save(configurations, defaults: defaults)
    }

    private static func normalized(
        _ configurations: [LibraryFolderConfiguration]
    ) -> [LibraryFolderConfiguration] {
        var seen = Set<String>()
        return configurations.compactMap { configuration in
            let path = (configuration.path as NSString).standardizingPath
            guard path.isEmpty == false, seen.insert(path).inserted else { return nil }
            return LibraryFolderConfiguration(path: path, mode: configuration.mode)
        }
    }
}

/// Watches configured library folder(s) via FSEvents and re-imports / refreshes audio.
@MainActor
public final class LibraryFolderWatcher {
    public static let shared = LibraryFolderWatcher()

    public static let pathKey = "songbird.libraryFolderPath"
    public static let pathsKey = "songbird.libraryFolderPaths"
    public static let enabledKey = "songbird.watchFolderEnabled"

    private var stream: FSEventStreamRef?
    private var watchedPaths: [String] = []
    private var debounceItem: DispatchWorkItem?
    private var pendingEventPaths = Set<String>()
    private var forceFullRescan = false
    private var importCycle = LibraryFolderImportCycle()
    private var importTask: Task<Void, Never>?
    private var importGeneration = 0
    private var activeScanner: LibraryScanner?
    private let callbackQueue = DispatchQueue(label: "com.songbird.folder-watcher")
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    private init() {
        sleepObserver = NotificationCenter.default.addObserver(
            forName: .systemWillSleep,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pauseForSleep() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resumeAfterWake() }
        }
    }

    isolated deinit {
        if let sleepObserver { NotificationCenter.default.removeObserver(sleepObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    // MARK: - Path helpers

    public static var folderPaths: [String] {
        LibraryFolderConfigurationStore.load().map(\.path)
    }

    public static func decodePaths(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr.map { ($0 as NSString).standardizingPath }.filter { !$0.isEmpty }
    }

    public static func encodePaths(_ paths: [String]) -> String {
        let cleaned = paths.map { ($0 as NSString).standardizingPath }.filter { !$0.isEmpty }
        guard let data = try? JSONEncoder().encode(cleaned),
              let s = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        UserDefaults.standard.set(s, forKey: pathsKey)
        if let first = cleaned.first {
            UserDefaults.standard.set(first, forKey: pathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: pathKey)
        }
        return s
    }

    @discardableResult
    public static func migrateLegacyPathIfNeeded(defaults: UserDefaults = .standard) -> Bool {
        let existing = decodePaths(defaults.string(forKey: pathsKey) ?? "[]")
        if !existing.isEmpty { return false }
        let legacy = defaults.string(forKey: pathKey) ?? ""
        let standardized = (legacy as NSString).standardizingPath
        guard !standardized.isEmpty else { return false }
        if let data = try? JSONEncoder().encode([standardized]),
           let raw = String(data: data, encoding: .utf8) {
            defaults.set(raw, forKey: pathsKey)
        }
        return true
    }

    public func applySettingsFromDefaults() {
        guard Self.automaticWatchingIsAllowed() else {
            stop()
            return
        }
        let paths = LibraryFolderConfigurationStore.load()
            .filter { $0.mode == .watching }
            .map(\.path)
        if !paths.isEmpty {
            start(paths: paths)
        } else {
            stop()
        }
    }

    public static func automaticWatchingIsAllowed(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> Bool {
        SongbirdUIRuntime.isTesting(
            environment: environment,
            infoDictionary: infoDictionary
        ) == false
    }

    public func start(path: String) {
        start(paths: [path])
    }

    public func start(paths: [String]) {
        let watchablePaths = LibraryFolderWatchPolicy.watchablePaths(paths)
        guard !watchablePaths.isEmpty else {
            stop()
            return
        }
        if stream != nil, watchedPaths == watchablePaths { return }
        stop()
        watchedPaths = watchablePaths
        createStream(for: watchablePaths)
    }

    public func stop() {
        debounceItem?.cancel()
        debounceItem = nil
        importGeneration &+= 1
        importTask?.cancel()
        importTask = nil
        activeScanner?.cancel()
        activeScanner = nil
        importCycle.cancel()
        pendingEventPaths.removeAll()
        forceFullRescan = false
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        watchedPaths = []
    }

    private func pauseForSleep() {
        if let stream {
            FSEventStreamStop(stream)
        }
    }

    private func resumeAfterWake() {
        if !watchedPaths.isEmpty {
            // Resume from the stream's checkpoint. FSEvents will request a
            // full scan explicitly if changes were dropped while asleep.
            if stream != nil {
                FSEventStreamStart(stream!)
            } else {
                createStream(for: watchedPaths)
            }
        } else {
            applySettingsFromDefaults()
        }
    }

    private func createStream(for paths: [String]) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let cfPaths = paths as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, numEvents, eventPaths, eventFlags, _ in
                guard let info else { return }
                let watcher = Unmanaged<LibraryFolderWatcher>.fromOpaque(info).takeUnretainedValue()
                let pathArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
                var collected: [String] = []
                var needsFull = false
                for i in 0..<numEvents {
                    let path = (pathArray[i] as? String) ?? ""
                    let flags = eventFlags[i]
                    if flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0
                        || flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0 {
                        needsFull = true
                    }
                    if !path.isEmpty {
                        collected.append((path as NSString).standardizingPath)
                    }
                }
                Task { @MainActor in
                    watcher.noteEvents(paths: collected, forceFull: needsFull)
                }
            },
            &context,
            cfPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.5,
            flags
        ) else {
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, callbackQueue)
        FSEventStreamStart(stream)
    }

    private func noteEvents(paths: [String], forceFull: Bool) {
        if forceFull { forceFullRescan = true }
        for path in paths {
            pendingEventPaths.insert(path)
        }
        // Huge batches are cheaper as a full root scan.
        if pendingEventPaths.count > 400 {
            forceFullRescan = true
        }
        scheduleImport()
    }

    private func scheduleImport() {
        debounceItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.beginScheduledImport()
            }
        }
        debounceItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func beginScheduledImport() {
        guard importCycle.request() else { return }
        importGeneration &+= 1
        let generation = importGeneration
        importTask = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                await self.processPendingEvents()
                guard Task.isCancelled == false,
                      generation == self.importGeneration else { return }
            } while self.importCycle.completeAndBeginNextIfNeeded()
            if generation == self.importGeneration {
                self.importTask = nil
            }
        }
    }

    private func processPendingEvents() async {
        let full = forceFullRescan
        let events = LibraryFolderEventFilter.importablePaths(
            pendingEventPaths,
            watchedRoots: watchedPaths
        )
        pendingEventPaths.removeAll()
        forceFullRescan = false

        if full {
            await importWatchedFolders()
            return
        }
        if events.isEmpty {
            return
        }

        let context = ModelContext(MediaLibrary.shared.container)
        var removedPaths: [String] = []
        var audioURLs: [URL] = []

        for path in events {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            if !exists {
                removedPaths.append(path)
                continue
            }
            if isDir.boolValue {
                // Let the shared pipeline enumerate directories off the main actor.
                audioURLs.append(URL(fileURLWithPath: path))
            } else if supportedExtensions.contains((path as NSString).pathExtension.lowercased()) {
                audioURLs.append(URL(fileURLWithPath: path))
            }
        }

        for path in removedPaths {
            _ = LibraryHygiene.removeTrackIfPresent(path: path, in: context)
        }

        await scan(audioURLs)
        guard Task.isCancelled == false else { return }
        if !removedPaths.isEmpty {
            do {
                try context.save()
                LibraryStatus.shared.showNotice(
                    "Watch: cleaned \(removedPaths.count)",
                    severity: .success,
                    autoDismissAfter: 3
                )
            } catch {
                context.rollback()
                LibraryStatus.shared.showPlaybackError(
                    "Could not save folder-watch changes: \(error.localizedDescription)"
                )
            }
        }
    }

    private func importWatchedFolders() async {
        let paths = watchedPaths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        await scan(urls)
    }

    private func scan(_ urls: [URL]) async {
        guard urls.isEmpty == false, Task.isCancelled == false else { return }
        let scanner = LibraryScanner(
            modelContainer: MediaLibrary.shared.container,
            automatic: true
        )
        activeScanner = scanner
        await scanner.scanFolders(urls)
        if activeScanner === scanner {
            activeScanner = nil
        }
    }
}
