import Combine
import Foundation

public enum LibraryFileHealthStatus: Equatable, Hashable, Sendable {
    case missing
    case unavailable(LibraryFileUnavailableReason)
}

public struct LibraryFileRelocationCandidate: Identifiable, Equatable, Hashable, Sendable {
    public let path: String
    public let checksum: String
    public let checksumMatchesCatalog: Bool

    public var id: String { path }

    public init(path: String, checksum: String, checksumMatchesCatalog: Bool) {
        self.path = path
        self.checksum = checksum
        self.checksumMatchesCatalog = checksumMatchesCatalog
    }
}

public enum LibraryFileRootFailureReason: Equatable, Hashable, Sendable {
    case missing
    case unavailable(LibraryFileUnavailableReason)
    case enumerationFailed

    public var message: String {
        switch self {
        case .missing: "Configured root was not found."
        case .unavailable(let reason): reason.message
        case .enumerationFailed: "Songbird could not enumerate this configured root."
        }
    }
}

public struct LibraryFileRootFailure: Identifiable, Equatable, Hashable, Sendable {
    public let path: String
    public let reason: LibraryFileRootFailureReason
    public var id: String { path }

    public init(path: String, reason: LibraryFileRootFailureReason) {
        self.path = path
        self.reason = reason
    }
}

public enum LibraryFileUnavailableReason: Equatable, Hashable, Sendable {
    case volumeNotMounted(String)
    case permissionDenied(String)
    case ioFailure(path: String, code: Int32)
    case ambiguousUnicode(String)

    init(_ reason: FileUnavailableReason) {
        switch reason {
        case .volumeNotMounted(let path): self = .volumeNotMounted(path)
        case .permissionDenied(let path): self = .permissionDenied(path)
        case .ioFailure(let path, let code): self = .ioFailure(path: path, code: code)
        case .ambiguousUnicode(let path): self = .ambiguousUnicode(path)
        }
    }

    public var message: String {
        switch self {
        case .volumeNotMounted(let path): "Library volume is unavailable: \(path)"
        case .permissionDenied(let path): "Songbird does not have permission to access: \(path)"
        case .ioFailure(let path, _): "The file is temporarily unavailable: \(path)"
        case .ambiguousUnicode(let path): "More than one filesystem entry matches: \(path)"
        }
    }
}

public struct LibraryFileHealthFinding: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let trackID: UUID
    public let expectedPath: String
    public let status: LibraryFileHealthStatus
    public let relocationCandidates: [LibraryFileRelocationCandidate]

    public init(
        trackID: UUID,
        expectedPath: String,
        status: LibraryFileHealthStatus,
        relocationCandidates: [LibraryFileRelocationCandidate] = []
    ) {
        self.trackID = trackID
        self.expectedPath = expectedPath
        self.status = status
        self.relocationCandidates = relocationCandidates.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        id = LibraryHealthStableID.make(
            "file|\(trackID.uuidString)|\(expectedPath)|\(String(describing: status))"
        )
    }
}

public struct LibraryFileHealthReport: Equatable, Sendable {
    public let findings: [LibraryFileHealthFinding]
    public let rootFailures: [LibraryFileRootFailure]

    public init(
        findings: [LibraryFileHealthFinding],
        rootFailures: [LibraryFileRootFailure] = []
    ) {
        self.findings = findings.sorted {
            if $0.expectedPath == $1.expectedPath {
                return $0.trackID.uuidString < $1.trackID.uuidString
            }
            return $0.expectedPath.localizedStandardCompare($1.expectedPath) == .orderedAscending
        }
        self.rootFailures = rootFailures.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    public var affectedTrackIDs: [UUID] { findings.map(\.trackID) }
}

public struct LibraryArtworkHealthFinding: Identifiable, Equatable, Sendable {
    public let id: String
    public let groupID: String
    public let title: String
    public let artist: String
    public let albumIDs: [UUID]
    public let trackIDs: [UUID]
    public let evidence: [LibraryHealthEvidence]
    public let confidence: LibraryRemediationConfidence
    public let localCandidatePaths: [String]

    public init(
        group: LibraryAlbumGroupSnapshot,
        localCandidatePaths: [String] = []
    ) {
        id = group.id
        groupID = group.id
        title = group.title
        artist = group.artist
        albumIDs = group.albumIDs.sorted { $0.uuidString < $1.uuidString }
        trackIDs = group.trackIDs.sorted { $0.uuidString < $1.uuidString }
        self.localCandidatePaths = Array(Set(localCandidatePaths)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        evidence = [LibraryHealthEvidence(
            kind: self.localCandidatePaths.isEmpty ? .missingArtwork : .folderName,
            summary: self.localCandidatePaths.isEmpty
                ? "No catalog artwork is attached to this album group."
                : "Reviewed local image candidates were found beside this album's tracks."
        )]
        confidence = self.localCandidatePaths.isEmpty ? .unresolved : .reviewRequired
    }
}

public struct LibraryArtworkHealthReport: Equatable, Sendable {
    public let findings: [LibraryArtworkHealthFinding]

    public init(findings: [LibraryArtworkHealthFinding]) {
        self.findings = findings.sorted {
            let title = $0.title.localizedCaseInsensitiveCompare($1.title)
            if title != .orderedSame { return title == .orderedAscending }
            return $0.id < $1.id
        }
    }

    public var affectedTrackIDs: [UUID] { findings.flatMap(\.trackIDs) }
    public var affectedAlbumIDs: [UUID] { findings.flatMap(\.albumIDs) }
}

public enum LibraryHealthReportBody: Equatable, Sendable {
    case remediation(LibraryRemediationPlan)
    case fileAvailability(LibraryFileHealthReport)
    case artwork(LibraryArtworkHealthReport)
}

public struct LibraryHealthCategoryResult: Equatable, Sendable {
    public let category: LibraryHealthCategory
    public let sourceRevision: Int
    public let checkedAt: Date
    public let body: LibraryHealthReportBody

    public init(
        category: LibraryHealthCategory,
        sourceRevision: Int,
        checkedAt: Date = Date(),
        body: LibraryHealthReportBody
    ) {
        self.category = category
        self.sourceRevision = sourceRevision
        self.checkedAt = checkedAt
        self.body = body
    }

    public init(
        category: LibraryHealthCategory,
        sourceRevision: Int,
        checkedAt: Date = Date(),
        plan: LibraryRemediationPlan
    ) {
        self.init(
            category: category,
            sourceRevision: sourceRevision,
            checkedAt: checkedAt,
            body: .remediation(plan)
        )
    }

    public var remediationPlan: LibraryRemediationPlan? {
        guard case .remediation(let plan) = body else { return nil }
        return plan
    }

    public var fileReport: LibraryFileHealthReport? {
        guard case .fileAvailability(let report) = body else { return nil }
        return report
    }

    public var artworkReport: LibraryArtworkHealthReport? {
        guard case .artwork(let report) = body else { return nil }
        return report
    }

    public var findingCount: Int {
        switch body {
        case .remediation(let plan): plan.proposals.count
        case .fileAvailability(let report): report.findings.count + report.rootFailures.count
        case .artwork(let report): report.findings.count
        }
    }

    public var affectedTrackIDs: [UUID] {
        switch body {
        case .remediation(let plan):
            var seen = Set<UUID>()
            return plan.proposals.flatMap(\.issue.grouping.trackIDs).filter {
                seen.insert($0).inserted
            }
        case .fileAvailability(let report):
            return report.affectedTrackIDs
        case .artwork(let report):
            return report.affectedTrackIDs
        }
    }
    public var affectedTrackCount: Int { affectedTrackIDs.count }
    public var affectedAlbumCount: Int {
        guard case .artwork(let report) = body else { return 0 }
        return Set(report.affectedAlbumIDs).count
    }
}

public enum LibraryHealthCheckState: Equatable, Sendable {
    case notChecked
    case checking(lastGood: LibraryHealthCategoryResult?)
    case ready(LibraryHealthCategoryResult)
    case stale(lastGood: LibraryHealthCategoryResult)
    case failed(message: String, lastGood: LibraryHealthCategoryResult?)

    public var lastGood: LibraryHealthCategoryResult? {
        switch self {
        case .notChecked: nil
        case .checking(let result), .failed(_, let result): result
        case .ready(let result), .stale(let result): result
        }
    }
}

public struct LibraryHealthCheckProgress: Equatable, Sendable {
    public let completed: Int
    public let total: Int

    public init(completed: Int = 0, total: Int = 0) {
        self.completed = completed
        self.total = total
    }
}

private actor LibraryHealthLocalEvidenceWorker {
    func embeddedAlbum(for track: LibraryTrackSnapshot) async -> String? {
        guard FileManager.default.fileExists(atPath: track.path),
              let metadata = await MetadataReader.read(
                from: URL(fileURLWithPath: track.path),
                detectMissingBPM: false
              ) else {
            return nil
        }
        let value = metadata.album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.caseInsensitiveCompare("Unknown Album") != .orderedSame else {
            return nil
        }
        return value
    }
}

actor LibraryArtworkEvidenceWorker {
    private let names = ["cover", "folder", "front", "album", "artwork"]
    private let extensions = Set(["jpg", "jpeg", "png", "heic", "tiff", "webp"])

    func candidatePaths(
        for groups: [LibraryAlbumGroupSnapshot],
        snapshot: LibrarySnapshot,
        progress: @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async throws -> [String: [String]] {
        var result: [String: [String]] = [:]
        // One folder can contain several catalog albums. Reuse its evidence only
        // within this explicit check so the next rescan sees filesystem changes.
        var candidatesByDirectory: [URL: Set<String>] = [:]
        for (index, group) in groups.enumerated() {
            try Task.checkCancellation()
            let directories = Set(group.trackIDs.compactMap { snapshot.tracksByID[$0] }.map {
                URL(fileURLWithPath: $0.path).deletingLastPathComponent().standardizedFileURL
            })
            var candidates = Set<String>()
            for directory in directories {
                try Task.checkCancellation()
                if let cached = candidatesByDirectory[directory] {
                    candidates.formUnion(cached)
                    continue
                }
                var directoryCandidates = Set<String>()
                guard let urls = try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    candidatesByDirectory[directory] = []
                    continue
                }
                for url in urls where extensions.contains(url.pathExtension.lowercased()) {
                    let stem = url.deletingPathExtension().lastPathComponent.lowercased()
                    if names.contains(stem),
                       (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                        directoryCandidates.insert(url.standardizedFileURL.path)
                    }
                }
                candidatesByDirectory[directory] = directoryCandidates
                candidates.formUnion(directoryCandidates)
            }
            result[group.id] = candidates.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
            try Task.checkCancellation()
            await progress(index + 1, groups.count)
        }
        return result
    }
}

/// Publishes immutable, independently retained Health results. Snapshot-only checks react to
/// catalog revisions; filesystem metadata is read only after an explicit local-evidence rescan.
@MainActor
public final class LibraryHealthProjectionStore: ObservableObject {
    @Published private var states: [LibraryHealthCategory: LibraryHealthCheckState] = [:]
    @Published private var progressValues: [LibraryHealthCategory: LibraryHealthCheckProgress] = [:]

    private let snapshots: LibrarySnapshotStore
    private let service: LibraryHealthProposalService
    private let configuredSearchRoots: @MainActor () -> [String]
    private let evidenceWorker = LibraryHealthLocalEvidenceWorker()
    private let fileAvailabilityWorker = FileAvailabilityWorker()
    private let albumProjectionWorker = LibraryAlbumProjectionWorker()
    private let artworkEvidenceWorker = LibraryArtworkEvidenceWorker()
    private var tasks: [LibraryHealthCategory: Task<Void, Never>] = [:]
    private var fileAvailabilityTask: Task<Void, Never>?
    private var observation: AnyCancellable?
    private var observedCategories = Set<LibraryHealthCategory>()
    private var embeddedAlbums: [UUID: (path: String, value: String)] = [:]
    private let activity: LibraryActivityStore
    private var activityIDs: [LibraryHealthCategory: UUID] = [:]

    public init(
        snapshots: LibrarySnapshotStore,
        service: LibraryHealthProposalService = LibraryHealthProposalService(),
        activity: LibraryActivityStore? = nil,
        configuredSearchRoots: @escaping @MainActor () -> [String] = {
            let environment = ProcessInfo.processInfo.environment
            if environment["SONGBIRD_UI_TESTING"] == "1",
               environment["SONGBIRD_UI_FIXTURE"] == "health",
               let root = environment[MediaLibraryStore.uiTestRootEnvironmentKey] {
                return [URL(fileURLWithPath: root, isDirectory: true)
                    .appendingPathComponent("HealthRelocationRoot", isDirectory: true).path]
            }
            return LibraryFolderConfigurationStore.load().map(\.path)
        }
    ) {
        self.snapshots = snapshots
        self.service = service
        self.activity = activity ?? LibraryStatus.shared.activity
        self.configuredSearchRoots = configuredSearchRoots
        observation = snapshots.$snapshot.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            for category in self.observedCategories {
                if let lastGood = self.states[category]?.lastGood {
                    self.states[category] = .stale(lastGood: lastGood)
                }
                if category.isFileAvailabilityCheck == false {
                    self.derivePlan(category: category, readsFilesystem: false)
                }
            }
        }
    }

    isolated deinit {
        for task in tasks.values { task.cancel() }
        fileAvailabilityTask?.cancel()
    }

    public func state(for category: LibraryHealthCategory) -> LibraryHealthCheckState {
        states[category] ?? .notChecked
    }

    public func progress(for category: LibraryHealthCategory) -> LibraryHealthCheckProgress {
        progressValues[category] ?? LibraryHealthCheckProgress()
    }

    public func check(category: LibraryHealthCategory) {
        observedCategories.insert(category)
        if category.isFileAvailabilityCheck {
            checkFileAvailability()
        } else {
            derivePlan(category: category, readsFilesystem: false)
        }
    }

    /// Registers a destination for stale-state tracking without starting an explicit file probe.
    public func observe(category: LibraryHealthCategory) {
        observedCategories.insert(category)
    }

    public func checkCatalogCategories() {
        for category in LibraryHealthCategory.allCases where !Self.requiresExplicitFileCheck(category) {
            check(category: category)
        }
    }

    public func rescanLocalEvidence(category: LibraryHealthCategory) {
        observedCategories.insert(category)
        if category.isFileAvailabilityCheck {
            checkFileAvailability()
        } else {
            derivePlan(category: category, readsFilesystem: true)
        }
    }

    public func retry(category: LibraryHealthCategory) {
        rescanLocalEvidence(category: category)
    }

    public func cancel(category: LibraryHealthCategory) {
        finishActivity(activityIDs[category], status: .cancelled, severity: .information)
        if category.isFileAvailabilityCheck {
            fileAvailabilityTask?.cancel()
            fileAvailabilityTask = nil
            for fileCategory in [LibraryHealthCategory.missingFiles, .unavailableVolumes] {
                progressValues[fileCategory] = LibraryHealthCheckProgress()
                if let lastGood = states[fileCategory]?.lastGood {
                    states[fileCategory] = .stale(lastGood: lastGood)
                } else {
                    states[fileCategory] = .notChecked
                }
            }
            return
        }
        tasks[category]?.cancel()
        tasks[category] = nil
        progressValues[category] = LibraryHealthCheckProgress()
        if let lastGood = states[category]?.lastGood {
            states[category] = .stale(lastGood: lastGood)
        } else {
            states[category] = .notChecked
        }
    }

    private func checkFileAvailability() {
        finishActivity(activityIDs[.missingFiles], status: .cancelled, severity: .information)
        fileAvailabilityTask?.cancel()
        let categories: [LibraryHealthCategory] = [.missingFiles, .unavailableVolumes]
        for category in categories {
            observedCategories.insert(category)
            states[category] = .checking(lastGood: states[category]?.lastGood)
        }
        let snapshot = snapshots.snapshot
        let requests = snapshot.tracks.map { FileAvailabilityRequest(id: $0.id, path: $0.path) }
        let activityID = activity.begin(kind: .healthCheck, source: .library, total: requests.count)
        for category in categories { activityIDs[category] = activityID }
        activity.setCancellation(id: activityID) { [weak self] in self?.cancel(category: .missingFiles) }
        let searchRoots = configuredSearchRoots()
        let initialProgress = LibraryHealthCheckProgress(completed: 0, total: requests.count)
        for category in categories { progressValues[category] = initialProgress }
        fileAvailabilityTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let availability = try await fileAvailabilityWorker.availabilityCheckingCancellation(
                    requests
                )
                try Task.checkCancellation()
                let tracksByID = snapshot.tracksByID
                let relocation = try await fileAvailabilityWorker.relocationCandidates(
                    for: availability.missingIDs.compactMap { id in
                        guard let track = tracksByID[id] else { return nil }
                        return FileRelocationRequest(
                            trackID: id,
                            expectedPath: track.path,
                            expectedChecksum: track.checksum
                        )
                    },
                    searchRoots: searchRoots
                )
                let missing = availability.missingIDs.compactMap { id -> LibraryFileHealthFinding? in
                    guard let track = tracksByID[id] else { return nil }
                    return LibraryFileHealthFinding(
                        trackID: id,
                        expectedPath: track.path,
                        status: .missing,
                        relocationCandidates: relocation.candidatesByTrackID[id] ?? []
                    )
                }
                let unavailable = availability.unavailableReasons.compactMap { id, reason -> LibraryFileHealthFinding? in
                    guard let track = tracksByID[id] else { return nil }
                    return LibraryFileHealthFinding(
                        trackID: id,
                        expectedPath: track.path,
                        status: .unavailable(LibraryFileUnavailableReason(reason))
                    )
                }
                let checkedAt = Date()
                let missingRootFailures = relocation.rootFailures.filter {
                    if case .unavailable = $0.reason { return false }
                    return true
                }
                let unavailableRootFailures = relocation.rootFailures.filter {
                    if case .unavailable = $0.reason { return true }
                    return false
                }
                states[.missingFiles] = .ready(LibraryHealthCategoryResult(
                    category: .missingFiles,
                    sourceRevision: snapshot.revision,
                    checkedAt: checkedAt,
                    body: .fileAvailability(LibraryFileHealthReport(
                        findings: missing,
                        rootFailures: missingRootFailures
                    ))
                ))
                states[.unavailableVolumes] = .ready(LibraryHealthCategoryResult(
                    category: .unavailableVolumes,
                    sourceRevision: snapshot.revision,
                    checkedAt: checkedAt,
                    body: .fileAvailability(LibraryFileHealthReport(
                        findings: unavailable,
                        rootFailures: unavailableRootFailures
                    ))
                ))
                for category in categories { progressValues[category] = LibraryHealthCheckProgress() }
                activity.update(id: activityID, completed: requests.count)
                let failures = missing.map { LibraryActivityFailure(fileName: $0.expectedPath, category: .missingFile) }
                    + unavailable.map { LibraryActivityFailure(fileName: $0.expectedPath, category: .unavailableFile) }
                let hasFindings = !failures.isEmpty || !relocation.rootFailures.isEmpty
                finishActivity(activityID, status: hasFindings ? .completedWithWarnings : .succeeded,
                    severity: hasFindings ? .warning : .information, failures: failures)
                fileAvailabilityTask = nil
            } catch is CancellationError {
                finishActivity(activityID, status: .cancelled, severity: .information)
                return
            } catch {
                for category in categories {
                    states[category] = .failed(
                        message: error.localizedDescription,
                        lastGood: states[category]?.lastGood
                    )
                    progressValues[category] = LibraryHealthCheckProgress()
                }
                fileAvailabilityTask = nil
                activity.update(id: activityID, completed: 0, liveMessage: error.localizedDescription)
                finishActivity(activityID, status: .failed, severity: .error)
            }
        }
    }

    private func derivePlan(category: LibraryHealthCategory, readsFilesystem: Bool) {
        finishActivity(activityIDs[category], status: .cancelled, severity: .information)
        tasks[category]?.cancel()
        let lastGood = states[category]?.lastGood
        states[category] = .checking(lastGood: lastGood)
        let snapshot = snapshots.snapshot
        let snapshotTracks = snapshot.tracks
        progressValues[category] = LibraryHealthCheckProgress(
            completed: 0,
            total: readsFilesystem && category != .missingArtwork ? snapshotTracks.count : 0
        )
        let cachedEvidence = embeddedAlbums
        let activityID: UUID? = readsFilesystem
            ? activity.begin(kind: .healthCheck, source: .library, total: progressValues[category]?.total ?? 0)
            : nil
        if let activityID {
            activityIDs[category] = activityID
            activity.setCancellation(id: activityID) { [weak self] in self?.cancel(category: category) }
        }
        tasks[category] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if category == .missingArtwork {
                    let groups = try await albumProjectionWorker.project(snapshot)
                        .filter { $0.artworkReference == nil && $0.albumIDs.isEmpty == false }
                    try Task.checkCancellation()
                    var candidates: [String: [String]] = [:]
                    if readsFilesystem {
                        progressValues[category] = LibraryHealthCheckProgress(
                            completed: 0, total: groups.count
                        )
                        if let activityID { activity.update(id: activityID, completed: 0, total: groups.count) }
                        candidates = try await artworkEvidenceWorker.candidatePaths(
                            for: groups, snapshot: snapshot
                        ) { [weak self] completed, total in
                            guard !Task.isCancelled else { return }
                            await self?.updateArtworkProgress(completed: completed, total: total)
                        }
                    }
                    try Task.checkCancellation()
                    states[category] = .ready(LibraryHealthCategoryResult(
                        category: category,
                        sourceRevision: snapshot.revision,
                        body: .artwork(LibraryArtworkHealthReport(findings: groups.map {
                            LibraryArtworkHealthFinding(
                                group: $0,
                                localCandidatePaths: candidates[$0.id] ?? []
                            )
                        }))
                    ))
                    progressValues[category] = LibraryHealthCheckProgress()
                    if let activityID { activity.update(id: activityID, completed: groups.count) }
                    finishActivity(activityID, status: .succeeded, severity: .information)
                    tasks[category] = nil
                    return
                }
                var evidence = cachedEvidence.filter { id, item in
                    snapshotTracks.contains { $0.id == id && $0.path == item.path }
                }
                if readsFilesystem {
                    evidence = [:]
                    for (index, track) in snapshotTracks.enumerated() {
                        try Task.checkCancellation()
                        if let value = await evidenceWorker.embeddedAlbum(for: track) {
                            evidence[track.id] = (track.path, value)
                        }
                        progressValues[category] = LibraryHealthCheckProgress(
                            completed: index + 1,
                            total: snapshotTracks.count
                        )
                        if let activityID { activity.update(id: activityID, completed: index + 1) }
                    }
                }
                try Task.checkCancellation()
                let inputs = snapshotTracks.map { track in
                    LibraryHealthTrackInput(
                        id: track.id,
                        title: track.title,
                        path: track.path,
                        album: track.album,
                        artist: track.artist,
                        albumArtist: track.albumArtist,
                        genre: track.genre,
                        comment: track.comment,
                        year: track.year,
                        trackNumber: track.trackNumber,
                        bitrate: track.bitrate,
                        fileKind: track.fileKind,
                        albumID: track.albumID,
                        hasArtwork: track.artworkReference != nil,
                        embeddedAlbum: evidence[track.id]?.value
                    )
                }
                let plan = try await service.plan(category: category, tracks: inputs)
                try Task.checkCancellation()
                embeddedAlbums = evidence
                states[category] = .ready(LibraryHealthCategoryResult(
                    category: category,
                    sourceRevision: snapshot.revision,
                    plan: plan
                ))
                progressValues[category] = LibraryHealthCheckProgress()
                finishActivity(activityID, status: .succeeded, severity: .information)
                tasks[category] = nil
            } catch is CancellationError {
                finishActivity(activityID, status: .cancelled, severity: .information)
                return
            } catch {
                states[category] = .failed(
                    message: error.localizedDescription,
                    lastGood: lastGood
                )
                progressValues[category] = LibraryHealthCheckProgress()
                tasks[category] = nil
                let failureID = activityID ?? activity.begin(kind: .healthCheck, source: .library)
                activity.update(id: failureID, completed: 0, liveMessage: error.localizedDescription)
                if activityID == nil { activityIDs[category] = failureID }
                finishActivity(failureID, status: .failed, severity: .error)
            }
        }
    }

    private func updateArtworkProgress(completed: Int, total: Int) {
        guard !Task.isCancelled else { return }
        progressValues[.missingArtwork] = LibraryHealthCheckProgress(completed: completed, total: total)
        if let activityID = activityIDs[.missingArtwork] {
            activity.update(id: activityID, completed: completed, total: total)
        }
    }

    private func finishActivity(_ id: UUID?, status: LibraryActivityStatus, severity: LibraryNoticeSeverity,
                                failures: [LibraryActivityFailure] = []) {
        guard let id, activityIDs.values.contains(id) else { return }
        activityIDs = activityIDs.filter { $0.value != id }
        activity.finish(id: id, status: status, severity: severity, failures: failures)
    }

    private static func requiresExplicitFileCheck(_ category: LibraryHealthCategory) -> Bool {
        switch category {
        case .missingFiles, .unavailableVolumes, .duplicateTracks:
            true
        default:
            false
        }
    }
}
