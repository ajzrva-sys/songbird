import Combine
import Foundation

@MainActor
public final class LibraryActivityStore: ObservableObject {
    @Published public private(set) var records: [LibraryActivityRecord] = []
    @Published public private(set) var liveMessages: [UUID: String] = [:]
    @Published public private(set) var storageIssue: LibraryActivityStorageIssue?
    private let storage: LibraryActivityStorage
    private let clock: () -> Date
    private var loadTask: Task<LibraryActivityLoadResult, Never>?
    private var loaded = false
    private var writeTask: Task<Void, Never>?
    private var pendingProgress: [UUID: Task<Void, Never>] = [:]
    private var lastProgressWrite: [UUID: Date] = [:]
    private var cancellations: [UUID: () -> Void] = [:]

    public init(storage: LibraryActivityStorage, clock: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.clock = clock
    }

    public convenience init() {
        self.init(storage: LibraryActivityStorage(url: MediaLibraryStore.songbirdDirectory
            .appendingPathComponent("activity-history.json")))
    }

    public var runningRecords: [LibraryActivityRecord] { records.filter { !$0.status.isTerminal } }
    public var attentionCount: Int {
        records.filter { $0.severity == .warning || $0.severity == .error }.count
    }

    public func load() async {
        guard !loaded else { return }
        if loadTask == nil {
            let storage = self.storage, now = clock()
            loadTask = Task { await storage.load(now: now) }
        }
        guard let result = await loadTask?.value, !loaded else { return }
        loaded = true
        storageIssue = result.issue
        let currentIDs = Set(records.map(\.id))
        records = LibraryActivityStorage.retained(records + result.records.filter { !currentIDs.contains($0.id) }, now: clock())
        // Recovering running rows to Interrupted is durably recorded as well.
        if result.issue == nil, !records.isEmpty { persist() }
    }

    @discardableResult
    public func begin(kind: LibraryActivityKind, source: LibraryNoticeSource = .library, total: Int = 0,
                      liveMessage: String? = nil) -> UUID {
        let record = LibraryActivityRecord(kind: kind, source: source, total: total, startedAt: clock())
        records.insert(record, at: 0)
        if let liveMessage { liveMessages[record.id] = liveMessage }
        lastProgressWrite[record.id] = clock()
        persist()
        return record.id
    }

    public func update(id: UUID, completed: Int, total: Int? = nil, liveMessage: String? = nil) {
        guard let index = records.firstIndex(where: { $0.id == id && !$0.status.isTerminal }) else { return }
        records[index].completed = max(0, completed)
        if let total { records[index].total = max(0, total) }
        records[index].updatedAt = clock()
        if let liveMessage { liveMessages[id] = liveMessage }
        if clock().timeIntervalSince(lastProgressWrite[id] ?? .distantPast) >= 2 {
            pendingProgress.removeValue(forKey: id)?.cancel()
            lastProgressWrite[id] = clock()
            persist()
        } else if pendingProgress[id] == nil {
            pendingProgress[id] = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self else { return }
                self.pendingProgress[id] = nil
                self.lastProgressWrite[id] = self.clock()
                self.persist()
            }
        }
    }

    public func setCancellation(id: UUID, action: @escaping () -> Void) {
        guard records.contains(where: { $0.id == id && $0.status == .running }) else { return }
        cancellations[id] = action
    }

    public func canCancel(id: UUID) -> Bool {
        cancellations[id] != nil && records.contains(where: { $0.id == id && $0.status == .running })
    }

    public func cancel(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id && $0.status == .running }),
              let cancellation = cancellations.removeValue(forKey: id) else { return }
        records[index].status = .cancelling
        records[index].updatedAt = clock()
        liveMessages[id] = "Cancelling…"
        pendingProgress.removeValue(forKey: id)?.cancel()
        persist()
        cancellation()
    }

    public func finish(id: UUID, status: LibraryActivityStatus, severity: LibraryNoticeSeverity = .success,
                       failures: [LibraryActivityFailure] = [], counts: LibraryActivityCounts? = nil,
                       liveMessage: String? = nil) {
        guard status.isTerminal,
              let index = records.firstIndex(where: { $0.id == id && !$0.status.isTerminal }) else { return }
        pendingProgress.removeValue(forKey: id)?.cancel()
        cancellations[id] = nil
        lastProgressWrite[id] = nil
        records[index].status = status
        records[index].severity = severity
        records[index].updatedAt = clock()
        records[index].finishedAt = clock()
        records[index].failures = Array(failures.prefix(100))
        let normalizedCounts = counts.map {
            LibraryActivityCounts(catalogSaved: $0.catalogSaved, filesAttempted: $0.filesAttempted,
                                  filesSaved: $0.filesSaved, filesFailed: $0.filesFailed)
        }
        records[index].failureCount = max(failures.count, normalizedCounts?.filesFailed ?? 0)
        records[index].counts = normalizedCounts
        if let liveMessage { liveMessages[id] = liveMessage }
        retain()
        persist()
    }

    public func recordNotice(id: UUID, source: LibraryNoticeSource, severity: LibraryNoticeSeverity, liveMessage: String) {
        guard !records.contains(where: { $0.id == id }) else { return }
        var record = LibraryActivityRecord(id: id, kind: .notice, source: source, startedAt: clock())
        record.status = severity == .error ? .failed : severity == .warning ? .completedWithWarnings : .succeeded
        record.severity = severity
        record.finishedAt = clock()
        records.insert(record, at: 0)
        liveMessages[id] = liveMessage
        retain()
        persist()
    }

    /// Clearing removes terminal history, preserving any current operations.
    public func clearHistory() async {
        await load()
        records.removeAll { $0.status.isTerminal }
        let retainedIDs = Set(records.map(\.id))
        liveMessages = liveMessages.filter { retainedIDs.contains($0.key) }
        persist(clearing: true)
        await flush()
    }

    public func flush() async {
        await load()
        for task in pendingProgress.values { task.cancel() }
        pendingProgress.removeAll()
        persist()
        await writeTask?.value
    }

    private func retain() {
        records = LibraryActivityStorage.retained(records, now: clock())
        let ids = Set(records.map(\.id))
        liveMessages = liveMessages.filter { ids.contains($0.key) }
    }

    private func persist(clearing: Bool = false) {
        // Observing the shared facade during unit tests must not open a normal
        // profile. Startup load explicitly activates persistence and merges rows
        // accumulated before activation; flush is the explicit test seam.
        guard loaded else { return }
        let previous = writeTask
        writeTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            let records = self.records, now = self.clock()
            let issue = await self.storage.save(records, now: now, clearing: clearing)
            self.storageIssue = issue
        }
    }
}
