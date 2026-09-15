import Foundation
import SwiftData

public let supportedExtensions: Set<String> = [
    "mp3", "m4a", "aac", "flac", "wav", "aiff", "aif"
]

@MainActor
public final class LibraryScanner: ObservableObject {
    @Published public private(set) var progress = ImportProgress()

    public var isScanning: Bool { progress.isRunning }
    public var scannedCount: Int { progress.completed }
    public var totalCount: Int { progress.total }

    private let modelContainer: ModelContainer
    private let status: LibraryStatus
    private let automatic: Bool
    private var scanTask: Task<Void, Never>?
    private static let progressRootKey = "songbird.libraryImport.progressRoot"
    private static let progressCompletedKey = "songbird.libraryImport.progressCompleted"
    private static let progressTotalKey = "songbird.libraryImport.progressTotal"

    public init(
        modelContainer: ModelContainer,
        status: LibraryStatus? = nil,
        automatic: Bool = false
    ) {
        self.modelContainer = modelContainer
        self.status = status ?? LibraryStatus.shared
        self.automatic = automatic
    }

    public func cancel() {
        scanTask?.cancel()
        scanTask = nil
    }

    public func scanFolders(_ urls: [URL]) async {
        cancel()
        let task = Task { @MainActor in
            await self.runScan(urls)
        }
        scanTask = task
        await task.value
        scanTask = nil
    }

    private func runScan(_ urls: [URL]) async {
        LibrarySnapshotStore.active?.beginBulkUpdates()
        defer { LibrarySnapshotStore.active?.endBulkUpdates() }
        status.setImportCancellation { [weak self] in
            self?.cancel()
        }
        let rootKey = urls
            .map { $0.standardizedFileURL.path }
            .sorted()
            .joined(separator: "\u{1f}")
        let defaults = UserDefaults.standard
        let resumedCompleted: Int
        let resumedTotal: Int
        if defaults.string(forKey: Self.progressRootKey) == rootKey {
            resumedCompleted = max(0, defaults.integer(forKey: Self.progressCompletedKey))
            resumedTotal = max(resumedCompleted, defaults.integer(forKey: Self.progressTotalKey))
        } else {
            resumedCompleted = 0
            resumedTotal = 0
        }
        updateProgress(ImportProgress(
            isRunning: true,
            completed: resumedCompleted,
            total: resumedTotal,
            message: Self.progressMessage(
                automatic: automatic,
                completed: resumedCompleted,
                total: resumedTotal
            )
        ))
        status.beginScan(
            total: resumedTotal,
            completed: resumedCompleted,
            message: Self.progressMessage(
                automatic: automatic,
                completed: resumedCompleted,
                total: resumedTotal
            )
        )
        let progressReporter = LibraryImportProgressReporter(
            scanner: self,
            rootKey: rootKey
        )
        let result = await Self.runImport(
            roots: urls,
            container: modelContainer,
            automatic: automatic,
            progressReporter: progressReporter
        )
        Self.persistResume(
            defaults: defaults,
            rootKey: rootKey,
            processed: result.processed,
            total: result.discovered
        )
        updateProgress(ImportProgress())
        if let failureMessage = result.failureMessage {
            status.endOperation(message: failureMessage, severity: .error)
        } else if result.cancelled {
            status.endScan(added: result.added)
            status.statusMessage = "Import canceled"
        } else {
            status.endScan(added: result.added)
        }
    }

    private func updateProgress(_ value: ImportProgress) {
        guard progress != value else { return }
        progress = value
    }

    fileprivate func publishImportProgress(
        processed: Int,
        total: Int,
        decision: ImportProgressCadenceDecision,
        rootKey: String
    ) {
        if decision.publish {
            let value = ImportProgress(
                isRunning: true,
                completed: processed,
                total: total,
                message: Self.progressMessage(
                    automatic: automatic,
                    completed: processed,
                    total: total
                )
            )
            updateProgress(value)
            status.updateScan(
                scanned: processed,
                total: total,
                message: value.message
            )
        }
        if decision.persist {
            Self.persistResume(
                defaults: .standard,
                rootKey: rootKey,
                processed: processed,
                total: total
            )
        }
    }

    private nonisolated static func runImport(
        roots: [URL],
        container: ModelContainer,
        automatic: Bool,
        progressReporter: LibraryImportProgressReporter
    ) async -> LibraryImportResult {
        if automatic {
            return await LibraryImportPipeline.runAutomatic(
                roots: roots,
                container: container
            ) { processed, total in
                await progressReporter.receive(processed: processed, total: total)
            }
        } else {
            return await LibraryImportPipeline.run(
                roots: roots,
                container: container
            ) { processed, total in
                await progressReporter.receive(processed: processed, total: total)
            }
        }
    }

    private static func persistResume(
        defaults: UserDefaults,
        rootKey: String,
        processed: Int,
        total: Int
    ) {
        defaults.set(rootKey, forKey: progressRootKey)
        defaults.set(processed, forKey: progressCompletedKey)
        defaults.set(total, forKey: progressTotalKey)
    }

    nonisolated static func progressMessage(
        automatic: Bool,
        completed: Int,
        total: Int
    ) -> String {
        let activity = automatic ? "Checking library" : "Importing"
        return total > 0
            ? "\(activity) \(completed) of \(total)…"
            : "\(activity)…"
    }
}

private actor LibraryImportProgressReporter {
    private weak var scanner: LibraryScanner?
    private let rootKey: String
    private let cadence = ImportProgressCadence()

    init(scanner: LibraryScanner, rootKey: String) {
        self.scanner = scanner
        self.rootKey = rootKey
    }

    func receive(processed: Int, total: Int) async {
        let decision = await cadence.receive(processed: processed, total: total)
        guard decision.publish || decision.persist else { return }
        await scanner?.publishImportProgress(
            processed: processed,
            total: total,
            decision: decision,
            rootKey: rootKey
        )
    }
}

public struct ImportProgressCadenceDecision: Equatable, Sendable {
    public let publish: Bool
    public let persist: Bool
}

/// Enforces UI progress <=10 Hz and resume persistence <= once every two seconds.
public actor ImportProgressCadence {
    private let clock = ContinuousClock()
    private var lastPublication: ContinuousClock.Instant?
    private var lastPersistence: ContinuousClock.Instant?

    public init() {}

    public func receive(
        processed: Int,
        total: Int,
        force: Bool = false
    ) -> ImportProgressCadenceDecision {
        let now = clock.now
        let publish = force
            || lastPublication.map { $0.duration(to: now) >= .milliseconds(100) } != false
        let persist = force
            || lastPersistence.map { $0.duration(to: now) >= .seconds(2) } != false
        if publish { lastPublication = now }
        if persist { lastPersistence = now }
        return ImportProgressCadenceDecision(publish: publish, persist: persist)
    }
}

/// Owns the import after Setup hands its progress and cancellation to the main window.
@MainActor
public final class LibraryImportCoordinator {
    public static let shared = LibraryImportCoordinator()

    private var scanner: LibraryScanner?
    private var task: Task<Void, Never>?

    private init() {}

    public func start(_ urls: [URL]) {
        task?.cancel()
        let scanner = LibraryScanner(modelContainer: MediaLibrary.shared.container)
        self.scanner = scanner
        task = Task { [weak self] in
            await scanner.scanFolders(urls)
            guard !Task.isCancelled else { return }
            self?.scanner = nil
            self?.task = nil
        }
    }

    public func cancel() {
        task?.cancel()
        scanner?.cancel()
        task = nil
        scanner = nil
    }
}
