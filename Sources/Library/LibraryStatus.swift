import Combine
import Foundation

public enum LibraryOperationPhase: String, Equatable, Sendable {
    case idle
    case running
    case cancelling
    case succeeded
    case failed
}

public struct ImportProgress: Equatable, Sendable {
    public var phase: LibraryOperationPhase
    public var completed: Int
    public var total: Int
    public var message: String

    public var isRunning: Bool {
        get { phase == .running || phase == .cancelling }
        set { phase = newValue ? .running : .idle }
    }

    public init(
        isRunning: Bool = false,
        phase: LibraryOperationPhase? = nil,
        completed: Int = 0,
        total: Int = 0,
        message: String = ""
    ) {
        self.phase = phase ?? (isRunning ? .running : .idle)
        self.completed = completed
        self.total = total
        self.message = message
    }
}

/// Shared operation value used by imports, maintenance, metadata, and external services.
/// `ImportProgress` remains the source name for compatibility with existing callers.
public typealias LibraryOperationState = ImportProgress

@MainActor
public final class ImportProgressState: ObservableObject {
    @Published public fileprivate(set) var value = ImportProgress()

    public init() {}

    fileprivate func update(_ value: ImportProgress) {
        guard self.value != value else { return }
        self.value = value
    }
}

@MainActor
public final class LibrarySelectionState: ObservableObject {
    @Published public var selectedTrack: Track?
    @Published public private(set) var selectedLibraryTrackID: UUID?

    public init() {}

    public func updateLibrarySelection(trackID: UUID?, track: Track?) {
        selectedLibraryTrackID = trackID
        selectedTrack = track
    }
}

@MainActor
public final class LibrarySummaryState: ObservableObject {
    @Published public private(set) var summary: LibraryContentSummary = .none
    private var activeOwner: LibraryContentSummaryOwner?

    public init() {}

    public func activate(
        owner: LibraryContentSummaryOwner,
        initial: LibraryContentSummary = .none
    ) {
        activeOwner = owner
        if summary != initial { summary = initial }
    }

    public func update(owner: LibraryContentSummaryOwner, summary: LibraryContentSummary) {
        guard activeOwner == owner, self.summary != summary else { return }
        self.summary = summary
    }

    public func clear(owner: LibraryContentSummaryOwner) {
        guard activeOwner == owner else { return }
        activeOwner = nil
        summary = .none
    }
}

public struct LibraryContentSummaryOwner: Hashable, Sendable {
    private let id: UUID
    public init() { id = UUID() }
}

public enum LibraryContentSummary: Hashable, Sendable {
    case none
    case tracks(count: Int, duration: TimeInterval)
    case albums(albumCount: Int, trackCount: Int)
    case healthDashboard(issueCount: Int, checkedCount: Int)
    case healthDetail(findingCount: Int, affectedTrackCount: Int)

    public var text: String {
        switch self {
        case .none:
            ""
        case .tracks(let count, let duration):
            "\(count) track\(count == 1 ? "" : "s") · \(LibraryStatusPresentation.formatDuration(duration))"
        case .albums(let albums, let tracks):
            "\(albums) album\(albums == 1 ? "" : "s") · \(tracks) track\(tracks == 1 ? "" : "s")"
        case .healthDashboard(let issues, let checks):
            "\(issues) issue\(issues == 1 ? "" : "s") across \(checks) checked check\(checks == 1 ? "" : "s")"
        case .healthDetail(let findings, let tracks):
            "\(findings) finding\(findings == 1 ? "" : "s") · \(tracks) affected track\(tracks == 1 ? "" : "s")"
        }
    }
}

@MainActor
public final class UserNoticeState: ObservableObject {
    @Published public private(set) var notice: LibraryNotice?
    private var pending: [LibraryNotice] = []

    public var message: String {
        get { notice?.message ?? "" }
        set {
            if newValue.isEmpty {
                notice = nil
                pending.removeAll()
            } else {
                enqueue(LibraryNotice(message: newValue, severity: .information))
            }
        }
    }

    public init() {}

    public func enqueue(_ newNotice: LibraryNotice) {
        guard let current = notice else {
            notice = newNotice
            return
        }
        if current.severity.isSticky, newNotice.severity.isSticky == false {
            pending.append(newNotice)
        } else if current.severity.isSticky == false, newNotice.severity.isSticky {
            pending.insert(current, at: 0)
            notice = newNotice
        } else {
            pending.append(newNotice)
        }
    }

    public func dismissCurrent() {
        notice = pending.isEmpty ? nil : pending.removeFirst()
    }

    public func dismiss(id: UUID) {
        if notice?.id == id {
            dismissCurrent()
        } else {
            pending.removeAll { $0.id == id }
        }
    }

    public func clear(source: LibraryNoticeSource) {
        pending.removeAll { $0.source == source }
        if notice?.source == source {
            dismissCurrent()
        }
    }
}

public enum LibraryNoticeSeverity: String, Equatable, Sendable {
    case information
    case success
    case warning
    case error

    public var isSticky: Bool { self == .warning || self == .error }
}

public enum LibraryNoticeSource: String, Equatable, Sendable {
    case library
    case playback
    case importing
    case metadata
    case discogs
    case fileIO
}

public struct LibraryNotice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let message: String
    public let severity: LibraryNoticeSeverity
    public let isDismissible: Bool
    public let source: LibraryNoticeSource
    public let autoDismissAfter: TimeInterval?

    public init(
        id: UUID = UUID(),
        message: String,
        severity: LibraryNoticeSeverity,
        isDismissible: Bool = true,
        source: LibraryNoticeSource = .library,
        autoDismissAfter: TimeInterval? = nil
    ) {
        self.id = id
        self.message = message
        self.severity = severity
        self.isDismissible = isDismissible
        self.source = source
        self.autoDismissAfter = autoDismissAfter
    }
}

/// Presentation for the resting status bar state (item count + total duration).
public enum LibraryStatusPresentation: Equatable {
    case resting(count: Int, duration: TimeInterval)
    case empty

    public var text: String {
        switch self {
        case .resting(let count, let duration):
            let itemWord = count == 1 ? "item" : "items"
            let formatted = Self.formatDuration(duration)
            return "\(count) \(itemWord) · \(formatted)"
        case .empty:
            return ""
        }
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        guard duration > 0 else { return "0:00" }
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Non-observable facade retained for scanner, ripper, and playback command call sites.
@MainActor
public final class LibraryStatus {
    public static let shared = LibraryStatus()

    public let importProgress = ImportProgressState()
    public let selection = LibrarySelectionState()
    public let summary = LibrarySummaryState()
    public let notices = UserNoticeState()

    private var importCancellation: (() -> Void)?
    private var noticeDismissalTask: Task<Void, Never>?

    private init() {}

    public var isScanning: Bool { importProgress.value.isRunning }
    public var scannedCount: Int { importProgress.value.completed }
    public var totalCount: Int { importProgress.value.total }
    public var statusMessage: String {
        get { isScanning ? importProgress.value.message : notices.message }
        set {
            if isScanning {
                var progress = importProgress.value
                progress.message = newValue
                importProgress.update(progress)
            } else if notices.message != newValue {
                notices.message = newValue
            }
        }
    }
    public var selectedTrack: Track? {
        get { selection.selectedTrack }
        set { selection.selectedTrack = newValue }
    }

    public func beginScan(
        total: Int,
        completed: Int = 0,
        message: String? = nil
    ) {
        importProgress.update(ImportProgress(
            isRunning: true,
            completed: completed,
            total: total,
            message: message
                ?? (total > 0 ? "Importing \(completed) of \(total)…" : "Importing…")
        ))
    }

    public func updateScan(
        scanned: Int,
        total: Int? = nil,
        message: String? = nil
    ) {
        let resolvedTotal = total ?? importProgress.value.total
        importProgress.update(ImportProgress(
            isRunning: true,
            completed: scanned,
            total: resolvedTotal,
            message: message ?? "Importing \(scanned) of \(resolvedTotal)…"
        ))
    }

    public func endScan(added: Int) {
        let message = added > 0 ? "Added \(added) track\(added == 1 ? "" : "s")" : "No new tracks"
        importProgress.update(ImportProgress(
            phase: .succeeded,
            completed: importProgress.value.completed,
            total: importProgress.value.total,
            message: message
        ))
        importCancellation = nil
        showNotice(message, severity: added > 0 ? .success : .information, autoDismissAfter: 3)
    }

    public func setImportCancellation(_ cancellation: @escaping () -> Void) {
        importCancellation = cancellation
    }

    public func beginOperation(
        message: String,
        total: Int,
        cancellation: @escaping () -> Void
    ) {
        importProgress.update(ImportProgress(
            isRunning: true,
            completed: 0,
            total: total,
            message: message
        ))
        importCancellation = cancellation
    }

    public func updateOperation(completed: Int, message: String) {
        importProgress.update(ImportProgress(
            isRunning: true,
            completed: completed,
            total: importProgress.value.total,
            message: message
        ))
    }

    public func endOperation(
        message: String,
        severity: LibraryNoticeSeverity = .success
    ) {
        let phase: LibraryOperationPhase
        if message.localizedCaseInsensitiveContains("cancel") {
            phase = .idle
        } else if severity == .error {
            phase = .failed
        } else {
            phase = .succeeded
        }
        importProgress.update(ImportProgress(
            phase: phase,
            completed: importProgress.value.completed,
            total: importProgress.value.total,
            message: message
        ))
        importCancellation = nil
        showNotice(
            message,
            severity: severity,
            autoDismissAfter: severity == .error || severity == .warning ? nil : 3
        )
    }

    public func cancelImport() {
        guard importProgress.value.phase == .running,
              let cancellation = importCancellation else { return }
        var progress = importProgress.value
        progress.phase = .cancelling
        progress.message = "Cancelling…"
        importProgress.update(progress)
        importCancellation = nil
        cancellation()
    }

    public func showPlaybackError(_ message: String) {
        showNotice(message, severity: .error, source: .library)
    }

    public func showNotice(
        _ message: String,
        severity: LibraryNoticeSeverity = .information,
        autoDismissAfter seconds: TimeInterval? = nil,
        source: LibraryNoticeSource = .library
    ) {
        let notice = LibraryNotice(
            message: message,
            severity: severity,
            source: source,
            autoDismissAfter: seconds
        )
        notices.enqueue(notice)
        scheduleAutoDismissIfNeeded()
    }

    private func scheduleAutoDismissIfNeeded() {
        noticeDismissalTask?.cancel()
        noticeDismissalTask = nil
        guard let notice = notices.notice,
              let seconds = notice.autoDismissAfter else { return }
        noticeDismissalTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            guard let self,
                  self.isScanning == false,
                  self.notices.notice?.id == notice.id else { return }
            self.notices.dismiss(id: notice.id)
            self.scheduleAutoDismissIfNeeded()
        }
    }

    public func dismissCurrentNotice() {
        noticeDismissalTask?.cancel()
        noticeDismissalTask = nil
        notices.dismissCurrent()
        scheduleAutoDismissIfNeeded()
    }

    public func clearPlaybackError() {
        noticeDismissalTask?.cancel()
        noticeDismissalTask = nil
        if isScanning == false {
            notices.clear(source: .playback)
            scheduleAutoDismissIfNeeded()
        }
    }
}
