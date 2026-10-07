import AppKit
import Combine
import SwiftData

public typealias TrackMetadataTagWriting = @Sendable (
    String, [TrackMetadataField: TrackMetadataValue], Data?, Bool
) async throws -> Void

private struct MetadataFileWriteSummary {
    var attempted = 0
    var written = 0
    var failures: [LibraryActivityFailure] = []
}

public struct PlaylistCreationRequest: Identifiable, Equatable {
    public let id = UUID()
    public let trackIDs: [UUID]
    public let bringMainPlayerForward: Bool
}

public struct PlaylistAddSummary: Equatable, Sendable {
    public let requested: Int
    public let added: Int
    public let duplicateSkipped: Int
    public let missing: Int

    public init(requested: Int, added: Int, duplicateSkipped: Int, missing: Int) {
        self.requested = requested
        self.added = added
        self.duplicateSkipped = duplicateSkipped
        self.missing = missing
    }
}

/// Executes library-item commands independently from the view that presents them.
@MainActor
public final class LibraryItemActionHandler: ObservableObject {
    @Published public var playlistCreationRequest: PlaylistCreationRequest?
    @Published public var playlistDestinationRequest: PlaylistDestinationRequest?
    @Published public private(set) var sidebarPlaylistTargetRequest: SidebarPlaylistTargetRequest?
    @Published public private(set) var healthUndoAvailable = false

    private let modelContainer: ModelContainer
    private let playbackSession: PlaybackSession
    private let librarySnapshots: LibrarySnapshotStore
    private let navigation: LibraryNavigationCoordinator
    private var metadataTask: Task<Void, Never>?
    private let fileAvailabilityWorker: FileAvailabilityWorker
    private let revealFiles: @MainActor ([URL]) -> Void
    private let importExclusions: LibraryImportExclusionStore
    private let healthMutations: LibraryHealthMutationService
    private let trackMetadataMutations: TrackMetadataMutationService
    private let fileTagRepairs: LibraryFileTagRepairService
    private let fileTagRecovery = LibraryFileTagRecoveryWorker()
    private var cancelFileTagRecovery = false
    private var cancelFileTagRepair = false
    private var cancelFileArtworkRepair = false
    private var fileArtworkRepairRunning = false
    private let artworkScopeWorker = LibraryAlbumProjectionWorker()
    private var latestHealthReceipt: LibraryHealthMutationReceipt?
    private var finderTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var artworkSearchTask: Task<Void, Never>?
    private let folderArtworkLoader: @Sendable (URL) -> Data?
    private let metadataTagWriter: TrackMetadataTagWriting
    private let activity: LibraryActivityStore

    public init(
        modelContainer: ModelContainer,
        playbackSession: PlaybackSession,
        librarySnapshots: LibrarySnapshotStore,
        navigation: LibraryNavigationCoordinator,
        fileAvailabilityWorker: FileAvailabilityWorker = FileAvailabilityWorker(),
        importExclusions: LibraryImportExclusionStore = .shared,
        folderArtworkLoader: (@Sendable (URL) -> Data?)? = nil,
        fileTagRepairs: LibraryFileTagRepairService = LibraryFileTagRepairService(),
        metadataTagWriter: TrackMetadataTagWriting? = nil,
        activity: LibraryActivityStore? = nil,
        revealFiles: @escaping @MainActor ([URL]) -> Void = {
            NSWorkspace.shared.activateFileViewerSelecting($0)
        }
    ) {
        self.modelContainer = modelContainer
        self.playbackSession = playbackSession
        self.librarySnapshots = librarySnapshots
        self.navigation = navigation
        self.fileAvailabilityWorker = fileAvailabilityWorker
        self.importExclusions = importExclusions
        self.folderArtworkLoader = folderArtworkLoader ?? { TrackImporter.folderArtworkData(for: $0) }
        self.revealFiles = revealFiles
        self.fileTagRepairs = fileTagRepairs
        self.metadataTagWriter = metadataTagWriter ?? { path, fields, artwork, cleared in
            try await TagWriterService.writeTags(path: path, fields: fields,
                artworkData: artwork, artworkCleared: cleared)
        }
        self.activity = activity ?? LibraryStatus.shared.activity
        healthMutations = LibraryHealthMutationService(modelContainer: modelContainer)
        trackMetadataMutations = TrackMetadataMutationService(modelContainer: modelContainer)
    }

    public func applyHealthPlan(
        _ plan: LibraryRemediationPlan
    ) async -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError> {
        await recordHealthMutation(total: Set(plan.changes.map(\.target.trackID)).count) {
            await performHealthPlan(plan)
        }
    }

    private func performHealthPlan(
        _ plan: LibraryRemediationPlan
    ) async -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError> {
        do {
            let (outcome, receipt) = try await healthMutations.apply(plan)
            await librarySnapshots.refresh()
            latestHealthReceipt = receipt
            healthUndoAvailable = true
            return .success(outcome)
        } catch let error as LibraryHealthMutationError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(.persistence("The Library Health change was cancelled."))
        } catch {
            return .failure(.persistence(error.localizedDescription))
        }
    }

    /// Saves only checked safe missing-field proposals. Catalog values are
    /// updated only for files whose existing or newly saved tag was verified.
    public func saveHealthTagsToFiles(_ plan: LibraryRemediationPlan) async -> LibraryFileTagRepairSummary {
        cancelFileTagRepair = false
        let tracks = librarySnapshots.resolveTracks(ids: plan.safeMissingFileTagChanges.map(\.target.trackID))
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        var rejected: [LibraryFileTagRepairResult] = []
        let requests = plan.safeMissingFileTagChanges.compactMap { change -> LibraryFileTagRepairRequest? in
            let track = byID[change.target.trackID]
            let request = LibraryFileTagRepairRequest(trackID: change.target.trackID, path: track?.path ?? "", change: change)
            guard let track, Self.catalogHealthValue(track, field: change.target.field) == change.expectedValue else {
                rejected.append(LibraryFileTagRepairResult(request: request,
                    status: .failed("The catalog finding changed or disappeared. Check it again before saving file tags.")))
                return nil
            }
            return request
        }
        let operationID = LibraryStatus.shared.beginOperation(message: "Saving verified file tags…", total: requests.count,
            activityKind: .fileTagWrite, source: .metadata,
            cancellation: { [weak self] in self?.cancelFileTagRepair = true })
        let fileSummary = await fileTagRepairs.apply(requests, isCanceled: {
            await MainActor.run { self.cancelFileTagRepair }
        }) { completed, total in
            await MainActor.run {
                LibraryStatus.shared.updateOperation(completed: completed, message: "Saving file tags \(completed) of \(total)…", operationID: operationID)
            }
        }
        var summary = LibraryFileTagRepairSummary(results: rejected + fileSummary.results, canceled: fileSummary.canceled)
        let verified = Set(summary.results.filter {
            $0.status == .written || $0.status == .alreadyPresent
        }.map { $0.request.change })
        let verifiedPlan = LibraryRemediationPlan(category: plan.category, proposals: plan.proposals.compactMap { proposal in
            let changes = proposal.changes.filter { verified.contains($0) }
            guard !changes.isEmpty else { return nil }
            return LibraryRemediationProposal(issue: proposal.issue, proposedValue: proposal.proposedValue,
                candidateValues: proposal.candidateValues, confidence: proposal.confidence,
                evidence: proposal.evidence, changes: changes)
        })
        if !verified.isEmpty {
            switch await applyHealthPlan(verifiedPlan) {
            case .success:
                // Health Undo applies to the catalog only. Do not offer it as file Undo.
                latestHealthReceipt = nil
                healthUndoAvailable = false
            case .failure(let error): summary.catalogError = error.localizedDescription
            }
        }
        let warning = summary.conflicts > 0 || summary.failed > 0 || summary.catalogError != nil || summary.canceled
        LibraryStatus.shared.endOperation(
            message: "Saved \(summary.written) files, already tagged \(summary.alreadyPresent), conflicts \(summary.conflicts), failed \(summary.failed)\(summary.canceled ? " · canceled" : "")",
            severity: warning ? .warning : .success,
            operationID: operationID,
            activityStatus: summary.canceled ? .cancelled : (warning ? .completedWithWarnings : .succeeded),
            failures: summary.results.compactMap { result in
                switch result.status {
                case .conflict: return LibraryActivityFailure(fileName: result.request.path, category: .verificationFailed)
                case .failed: return LibraryActivityFailure(fileName: result.request.path, category: .ioFailure)
                default: return nil
                }
            },
            counts: LibraryActivityCounts(filesAttempted: requests.count, filesSaved: summary.written, filesFailed: summary.failed)
        )
        return summary
    }

    private static func catalogHealthValue(_ track: Track, field: LibraryHealthField) -> String? {
        switch field {
        case .artist: track.artist
        case .album: track.album
        case .albumArtist: track.albumArtist
        case .genre: track.genre
        case .year: String(track.year)
        case .trackNumber: String(track.trackNumber)
        default: nil
        }
    }

    /// Covers saved on albums are distinct from pictures embedded in audio files.
    /// Resolve the whole current catalog, including albums absent from missing-cover findings.
    public func saveLibraryArtworkToFiles() async -> LibraryFileArtworkSummary {
        guard !fileArtworkRepairRunning else {
            return LibraryFileArtworkSummary(results: [], scopeError: "Library artwork is already being saved to files.")
        }
        fileArtworkRepairRunning = true
        cancelFileArtworkRepair = false
        defer { fileArtworkRepairRunning = false }
        let requests: [LibraryFileArtworkRequest]
        do { requests = try libraryArtworkRequests() }
        catch {
            let activityID = activity.begin(kind: .artworkWrite, source: .metadata, liveMessage: error.localizedDescription)
            activity.finish(id: activityID, status: .failed, severity: .error)
            return LibraryFileArtworkSummary(results: [], scopeError: error.localizedDescription)
        }
        let total = Set(requests.map(\.path)).count
        let operationID = LibraryStatus.shared.beginOperation(message: "Checking files for missing artwork…", total: total,
            activityKind: .artworkWrite, source: .metadata,
            cancellation: { [weak self] in self?.cancelFileArtworkRepair = true })
        let summary = await fileTagRepairs.applyArtwork(requests, isCanceled: {
            await MainActor.run { self.cancelFileArtworkRepair }
        }, catalogIsCurrent: { request in
            await MainActor.run { self.libraryArtworkIsCurrent(request) }
        }) { completed, total in
            await MainActor.run {
                LibraryStatus.shared.updateOperation(completed: completed,
                    message: "Saving library artwork \(completed) of \(total) files…", operationID: operationID)
            }
        }
        LibraryStatus.shared.endOperation(
            message: "Saved artwork to \(summary.written) files, preserved \(summary.preserved), conflicts \(summary.conflicts), failed \(summary.failed)\(summary.canceled ? " · canceled" : "")",
            severity: summary.conflicts > 0 || summary.failed > 0 || summary.canceled ? .warning : .success,
            operationID: operationID,
            activityStatus: summary.canceled ? .cancelled : (summary.conflicts > 0 || summary.failed > 0 ? .completedWithWarnings : .succeeded),
            failures: summary.results.compactMap { result in
                switch result.status {
                case .conflict: return LibraryActivityFailure(fileName: result.request.path, category: .verificationFailed)
                case .failed: return LibraryActivityFailure(fileName: result.request.path, category: .ioFailure)
                default: return nil
                }
            },
            counts: LibraryActivityCounts(filesAttempted: total, filesSaved: summary.written, filesFailed: summary.failed)
        )
        return summary
    }

    private func libraryArtworkRequests() throws -> [LibraryFileArtworkRequest] {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        return try context.fetch(FetchDescriptor<Album>()).flatMap { album -> [LibraryFileArtworkRequest] in
            // One read per album; Data shares its storage across all track requests.
            guard let artwork = album.artworkData else { return [] }
            return album.tracks.map { track in
                LibraryFileArtworkRequest(trackID: track.id, albumID: album.id,
                    path: track.path, artworkData: artwork)
            }
        }
    }

    private func libraryArtworkIsCurrent(_ request: LibraryFileArtworkRequest) -> Bool {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let id = request.trackID
        var descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let track = try? context.fetch(descriptor).first,
              track.path == request.path, let album = track.albumRelation,
              album.id == request.albumID else { return false }
        return album.artworkData == request.artworkData
    }

    /// Bulk recovery is intentionally fill-only and reads tags without BPM analysis.
    /// A dedicated context keeps cancellation/save failure away from unrelated edits.
    public func recoverMissingFileTags(trackIDs: [UUID]) async -> LibraryFileTagRecoverySummary {
        cancelFileTagRecovery = false
        let wanted = Set(trackIDs)
        let targets = librarySnapshots.snapshot.tracks.filter { wanted.contains($0.id) }
        let pathsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.path) })
        let targetsByPath = Dictionary(grouping: targets, by: \.path)
        let paths = targetsByPath.keys.sorted()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        var recovered = 0, checked = 0, missing = 0, unavailable = 0, failed = 0
        var failureDetails: [LibraryActivityFailure] = []
        var saveError: String?
        let operationID = LibraryStatus.shared.beginOperation(message: "Reading file tags…", total: paths.count,
            activityKind: .readFileTags, source: .metadata,
            cancellation: { [weak self] in self?.cancelFileTagRecovery = true })
        librarySnapshots.beginBulkUpdates()
        defer { librarySnapshots.endBulkUpdates() }
        do {
            var metadataByPath: [String: AudioMetadata] = [:]
            var changedIDs = Set<UUID>()
            var recoveredArtwork: [UUID: Data] = [:]
            for start in stride(from: 0, to: paths.count, by: 4) {
                if Task.isCancelled || cancelFileTagRecovery { break }
                let batch = Array(paths[start..<min(start + 4, paths.count)])
                let results = await fileTagRecovery.readBatch(paths: batch)
                for (path, outcome, metadata) in results {
                    switch outcome {
                    case .refreshed:
                        if var metadata {
                            // Retain image bytes only for genuinely missing catalog covers.
                            if targetsByPath[path, default: []].allSatisfy({ $0.artworkReference != nil }) {
                                metadata.artworkData = nil
                            }
                            metadataByPath[path] = metadata
                        }
                    case .fileMissing:
                        missing += 1
                        failureDetails.append(LibraryActivityFailure(fileName: path, category: .missingFile))
                    case .fileUnavailable:
                        unavailable += 1
                        failureDetails.append(LibraryActivityFailure(fileName: path, category: .unavailableFile))
                    case .unreadable:
                        failed += 1
                        failureDetails.append(LibraryActivityFailure(fileName: path, category: .ioFailure))
                    }
                    checked += 1
                    LibraryStatus.shared.updateOperation(completed: checked, message: "Reading file tags \(checked) of \(paths.count)…", operationID: operationID)
                }
            }
            // Resolve fresh catalog values after the I/O pass, preserving edits
            // saved while files were being read and ignoring relocated records.
            let tracks = try context.fetch(FetchDescriptor<Track>()).filter { wanted.contains($0.id) }
            for track in tracks {
                guard track.path == pathsByID[track.id], let metadata = metadataByPath[track.path] else { continue }
                let changed = TrackImporter.recoverMissingFields(metadata, for: track)
                let artwork = track.resolvedArtworkData == nil ? metadata.artworkData : nil
                if let artwork { recoveredArtwork[track.id] = ArtworkStorage.normalized(artwork) }
                if changed || artwork != nil { changedIDs.insert(track.id); recovered += 1 }
            }
            if !changedIDs.isEmpty {
                _ = try AlbumRelationshipReconciler.reconcile(in: context, affectedTrackIDs: changedIDs)
                var artists = Dictionary(try context.fetch(FetchDescriptor<Artist>()).map { ($0.name, $0) },
                    uniquingKeysWith: { first, _ in first })
                for track in tracks where changedIDs.contains(track.id) {
                    if let artwork = recoveredArtwork[track.id], track.albumRelation?.artworkData == nil {
                        track.albumRelation?.artworkData = artwork
                    }
                    if let artist = artists[track.artist] { track.artistRelation = artist }
                    else {
                        let artist = Artist(name: track.artist)
                        context.insert(artist); artists[track.artist] = artist; track.artistRelation = artist
                    }
                }
                try context.save()
                await librarySnapshots.refreshAfterMutation()
            }
        } catch {
            context.rollback()
            recovered = 0
            saveError = error.localizedDescription
        }
        let canceled = Task.isCancelled || cancelFileTagRecovery
        LibraryStatus.shared.endOperation(
            message: "Recovered \(recovered), checked \(checked), missing \(missing), unavailable \(unavailable), failed \(failed)\(canceled ? " · canceled" : "")",
            severity: missing > 0 || unavailable > 0 || failed > 0 || saveError != nil ? .warning : .success,
            operationID: operationID,
            activityStatus: canceled ? .cancelled : (saveError != nil ? .failed : (missing + unavailable + failed > 0 ? .completedWithWarnings : .succeeded)),
            failures: failureDetails,
            counts: LibraryActivityCounts(catalogSaved: recovered, filesFailed: failed + missing + unavailable)
        )
        return LibraryFileTagRecoverySummary(recovered: recovered, checked: checked, missing: missing,
            unavailable: unavailable, failed: failed, canceled: canceled, saveError: saveError)
    }

    public func applyMissingFileRelocations(
        _ changes: [LibraryPathChange]
    ) async -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError> {
        await recordHealthMutation(total: changes.count) {
            await performMissingFileRelocations(changes)
        }
    }

    private func performMissingFileRelocations(
        _ changes: [LibraryPathChange]
    ) async -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError> {
        guard let expectedRevision = changes.first?.sourceRevision else {
            return .failure(.emptyPlan)
        }
        guard changes.allSatisfy({ $0.sourceRevision == expectedRevision }) else {
            return .failure(.sourceRevisionDrift(
                expected: expectedRevision,
                actual: librarySnapshots.snapshot.revision
            ))
        }
        let actualRevision = librarySnapshots.snapshot.revision
        guard actualRevision == expectedRevision else {
            return .failure(.sourceRevisionDrift(expected: expectedRevision, actual: actualRevision))
        }
        do {
            let (outcome, receipt) = try await healthMutations.applyRelocations(changes)
            await librarySnapshots.refresh()
            latestHealthReceipt = receipt
            healthUndoAvailable = true
            return .success(outcome)
        } catch let error as LibraryHealthMutationError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(.persistence("File relocation was cancelled."))
        } catch {
            return .failure(.persistence(error.localizedDescription))
        }
    }

    func applyDiscogsYears(
        _ suggestions: [DiscogsYearSuggestion],
        clock: () -> DiscogsFetchStamp? = DiscogsClock.sample
    ) async -> Result<DiscogsYearApplyResult, LibraryHealthMutationError> {
        do {
            let outcome = try DiscogsYearApplier.apply(suggestions, in: modelContainer.mainContext, clock: clock)
            await librarySnapshots.refreshAfterMutation()
            return .success(outcome)
        } catch let error as LibraryHealthMutationError {
            return .failure(error)
        } catch {
            return .failure(.persistence(error.localizedDescription))
        }
    }

    func applyDiscogsGenres(
        _ suggestions: [DiscogsGenreAlbumSuggestion],
        clock: () -> DiscogsFetchStamp? = DiscogsClock.sample
    ) async -> Result<DiscogsGenreBulkApplyResult, LibraryHealthMutationError> {
        do {
            let outcome = try DiscogsGenreBulkApplier.apply(suggestions, in: modelContainer.mainContext, clock: clock)
            await librarySnapshots.refreshAfterMutation()
            return .success(outcome)
        } catch let error as LibraryHealthMutationError {
            return .failure(error)
        } catch {
            return .failure(.persistence(error.localizedDescription))
        }
    }

    public func applyArtwork(
        _ changes: [LibraryArtworkChange],
        clock: @Sendable () -> DiscogsFetchStamp? = { DiscogsClock.sample() }
    ) async -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError> {
        await recordHealthMutation(total: changes.count) {
            await performArtwork(changes, clock: clock)
        }
    }

    private func performArtwork(
        _ changes: [LibraryArtworkChange],
        clock: @Sendable () -> DiscogsFetchStamp?
    ) async -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError> {
        do {
            let (outcome, receipt) = try await healthMutations.applyArtwork(changes, clock: clock)
            await librarySnapshots.refreshAfterMutation()
            latestHealthReceipt = receipt
            healthUndoAvailable = true
            return .success(outcome)
        } catch let error as LibraryHealthMutationError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(.persistence("Artwork application was cancelled."))
        } catch {
            return .failure(.persistence(error.localizedDescription))
        }
    }

    /// Opening an existing album can discover art added beside its audio after import,
    /// and can pick up embedded covers the first import missed.
    /// Disk reads/normalization stay off-main; a fresh write context protects newer edits.
    public func discoverFolderArtwork(albumIDs: [UUID]) async {
        for id in Set(albumIDs).sorted(by: { $0.uuidString < $1.uuidString }) {
            guard !Task.isCancelled else { return }
            guard let album = librarySnapshots.snapshot.albumsByID[id],
                  album.artworkReference == nil else { continue }
            let paths = album.trackIDs.compactMap { librarySnapshots.snapshot.tracksByID[$0]?.path }
            guard paths.isEmpty == false else { continue }
            let uniquePaths = Array(Set(paths)).sorted()
            let load = Task.detached(priority: .utility) { [folderArtworkLoader] () -> Data? in
                var folders = Set<String>()
                for path in uniquePaths {
                    guard !Task.isCancelled else { return nil }
                    let url = URL(fileURLWithPath: path)
                    if folders.insert(url.deletingLastPathComponent().path).inserted {
                        if let data = folderArtworkLoader(url), ArtworkStorage.pixelSize(of: data) != nil {
                            return ArtworkStorage.normalized(data)
                        }
                    }
                }
                // Folder art missing: re-read embedded tags (m4a/MP3 covr, FLAC picture).
                for path in uniquePaths {
                    guard !Task.isCancelled else { return nil }
                    let url = URL(fileURLWithPath: path)
                    if let meta = await MetadataReader.read(from: url, detectMissingBPM: false),
                       let data = meta.artworkData,
                       ArtworkStorage.pixelSize(of: data) != nil {
                        return ArtworkStorage.normalized(data)
                    }
                }
                return nil
            }
            let data = await withTaskCancellationHandler {
                await load.value
            } onCancel: {
                load.cancel()
            }
            guard !Task.isCancelled else { return }
            guard let data else { continue }
            do {
                let context = ModelContext(modelContainer)
                context.autosaveEnabled = false
                var query = FetchDescriptor<Album>(predicate: #Predicate { $0.id == id })
                query.fetchLimit = 1
                guard let current = try context.fetch(query).first,
                      current.artworkData == nil,
                      current.tracks.allSatisfy({ $0.artworkData == nil }),
                      Set(current.tracks.map(\.path)) == Set(uniquePaths) else { continue }
                current.artworkData = data
                try context.save()
                // Automatic discovery must not replace the user's existing Undo receipt.
                await librarySnapshots.refreshAfterMutation()
            } catch {
                LibraryStatus.shared.showNotice(
                    "Could not save album artwork: \(error.localizedDescription)", severity: .warning
                )
            }
        }
    }

    public func removeMissingCatalogRecords(
        _ removals: [LibraryMissingRecordRemoval]
    ) async -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError> {
        await recordHealthMutation(total: removals.count) {
            await performMissingCatalogRemoval(removals)
        }
    }

    private func performMissingCatalogRemoval(
        _ removals: [LibraryMissingRecordRemoval]
    ) async -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError> {
        guard let expectedRevision = removals.first?.sourceRevision else {
            return .failure(.emptyPlan)
        }
        let actualRevision = librarySnapshots.snapshot.revision
        guard removals.allSatisfy({ $0.sourceRevision == expectedRevision }),
              expectedRevision == actualRevision else {
            return .failure(.sourceRevisionDrift(expected: expectedRevision, actual: actualRevision))
        }
        let targetIDs = Set(removals.map(\.trackID))
        if let currentID = playbackSession.queue.currentTrack?.id, targetIDs.contains(currentID) {
            return .failure(.currentlyPlaying(currentID))
        }
        let queueBefore = playbackSession.queue.identitySnapshot()
        let playlistOrderBefore = PlaylistOrderStore.fullSnapshot()
        let exclusionsBefore = importExclusions.snapshot()
        do {
            let (outcome, catalogReceipt) = try await healthMutations.removeMissingCatalogRecords(removals)
            _ = playbackSession.queue.removeTracks(trackIDs: targetIDs)
            importExclusions.exclude(paths: removals.map(\.expectedPath))
            let receipt = catalogReceipt.withCrossDomain(LibraryHealthCrossDomainReceipt(
                queueBefore: queueBefore,
                queueAfter: playbackSession.queue.identitySnapshot(),
                playlistOrderBefore: playlistOrderBefore,
                playlistOrderAfter: PlaylistOrderStore.fullSnapshot(),
                exclusionsBefore: exclusionsBefore,
                exclusionsAfter: importExclusions.snapshot()
            ))
            await librarySnapshots.refresh()
            latestHealthReceipt = receipt
            healthUndoAvailable = true
            return .success(outcome)
        } catch let error as LibraryHealthMutationError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(.persistence("Catalog removal was cancelled."))
        } catch {
            return .failure(.persistence(error.localizedDescription))
        }
    }

    public func undoLatestHealthMutation()
        async -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError> {
        await recordHealthMutation(total: 0) { await performHealthUndo() }
    }

    private func performHealthUndo()
        async -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError> {
        guard let receipt = latestHealthReceipt else { return .failure(.noUndoAvailable) }
        if let cross = receipt.crossDomain {
            guard playbackSession.queue.identitySnapshot() == cross.queueAfter else {
                return .failure(.crossDomainDrift("The play queue"))
            }
            guard PlaylistOrderStore.fullSnapshot() == cross.playlistOrderAfter else {
                return .failure(.crossDomainDrift("Playlist order"))
            }
            guard importExclusions.snapshot() == cross.exclusionsAfter else {
                return .failure(.crossDomainDrift("Import exclusions"))
            }
        }
        do {
            let outcome = try await healthMutations.undo(receipt)
            await librarySnapshots.refreshAfterMutation()
            if let cross = receipt.crossDomain {
                PlaylistOrderStore.restoreFullSnapshot(cross.playlistOrderBefore)
                importExclusions.restore(cross.exclusionsBefore)
                guard playbackSession.queue.restoreIdentitySnapshot(
                    cross.queueBefore,
                    resolve: { [librarySnapshots] in librarySnapshots.resolveTrack(id: $0) }
                ) else {
                    return .failure(.crossDomainDrift("The restored play queue"))
                }
            }
            latestHealthReceipt = nil
            healthUndoAvailable = false
            return .success(outcome)
        } catch let error as LibraryHealthMutationError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(.persistence("Undo was cancelled."))
        } catch {
            return .failure(.persistence(error.localizedDescription))
        }
    }

    public func prepareTrackArtworkScope(trackIDs: [UUID]) async throws -> TrackArtworkScope {
        let snapshot = librarySnapshots.snapshot
        let wanted = Set(trackIDs)
        guard wanted.isEmpty == false else { throw TrackMetadataMutationError.emptySelection }
        for id in wanted where snapshot.tracksByID[id] == nil {
            throw TrackMetadataMutationError.missingTarget(id)
        }
        let groups = try await artworkScopeWorker.project(snapshot).filter { group in
            group.trackIDs.contains(where: wanted.contains)
        }
        try Task.checkCancellation()
        let scope = try await trackMetadataMutations.captureArtworkScope(groups: groups, snapshot: snapshot)
        guard wanted.isSubset(of: Set(scope.targets.map(\.trackID))) else {
            throw TrackMetadataMutationError.artworkScopeChanged
        }
        return scope
    }

    public func applyTrackMetadata(
        _ changeSet: TrackMetadataChangeSet,
        decisions: [TrackMetadataConflictDecision] = [],
        writePolicy: TrackMetadataWritePolicy? = nil
    ) async throws -> TrackMetadataApplyOutcome {
        let destination = writePolicy ?? (LibrarySettings.writeTagsToFiles ? .catalogAndFileTags : .catalogOnly)
        let activityID = activity.begin(kind: .metadataEdit, source: .metadata, total: changeSet.baselines.count)
        do {
        var scopedChanges = changeSet
        if changeSet.edits[.artwork] != nil {
            let scope: TrackArtworkScope
            if let captured = changeSet.artworkScope {
                scope = captured
            } else {
                scope = try await prepareTrackArtworkScope(trackIDs: changeSet.baselines.map(\.trackID))
            }
            guard scope.sourceStructureRevision == librarySnapshots.snapshot.albumStructureRevision else {
                throw TrackMetadataMutationError.artworkScopeChanged
            }
            scopedChanges = TrackMetadataChangeSet(
                baselines: changeSet.baselines, edits: changeSet.edits, artworkScope: scope
            )
        }
        let result = try await trackMetadataMutations.applyWithReceipt(scopedChanges, decisions: decisions)
        var fileSummary = MetadataFileWriteSummary()
        if case .saved(let count) = result.outcome, count > 0 {
            await librarySnapshots.refreshAfterMutation()
            if destination == .catalogAndFileTags {
                fileSummary = await writeTagsToFiles(result.fileWrites)
            }
        }
        switch result.outcome {
        case .saved(let count):
            activity.update(id: activityID, completed: changeSet.baselines.count)
            activity.finish(id: activityID,
                status: fileSummary.failures.isEmpty ? .succeeded : .completedWithWarnings,
                severity: fileSummary.failures.isEmpty ? .success : .warning,
                failures: fileSummary.failures,
                counts: LibraryActivityCounts(catalogSaved: count, filesAttempted: fileSummary.attempted,
                    filesSaved: fileSummary.written, filesFailed: fileSummary.failures.count))
        case .conflicts:
            activity.update(id: activityID, completed: 0,
                liveMessage: "Metadata changed elsewhere. Review the values before saving.")
            activity.finish(id: activityID, status: .completedWithWarnings, severity: .warning,
                counts: LibraryActivityCounts())
        }
        return result.outcome
        } catch is CancellationError {
            activity.finish(id: activityID, status: .cancelled, severity: .information)
            throw CancellationError()
        } catch {
            activity.update(id: activityID, completed: 0, liveMessage: error.localizedDescription)
            activity.finish(id: activityID, status: .failed, severity: .error)
            throw error
        }
    }

    private func writeTagsToFiles(_ writes: [TrackMetadataFileWrite]) async -> MetadataFileWriteSummary {
        let supportedWrites = writes.compactMap { write -> TrackMetadataFileWrite? in
            let fields = write.fields.filter { $0.key.supportsAudioTagWriting }
            guard !fields.isEmpty else { return nil }
            return TrackMetadataFileWrite(trackID: write.trackID, path: write.path, fields: fields)
        }
        var summary = MetadataFileWriteSummary(attempted: supportedWrites.count)
        guard !supportedWrites.isEmpty else { return summary }
        let activityID = activity.begin(kind: .fileTagWrite, source: .metadata, total: supportedWrites.count)
        for (index, write) in supportedWrites.enumerated() {
            let path = write.path
            let isArtwork = write.fields.keys.contains(.artwork)
            let artworkData: Data? = isArtwork ? {
                if case .artwork(let data) = write.fields[.artwork] { return data }
                return nil
            }() : nil
            let artworkCleared = isArtwork && artworkData == nil
            do {
                try await metadataTagWriter(path, write.fields, artworkData, artworkCleared)
                summary.written += 1
            } catch {
                summary.failures.append(LibraryActivityFailure(fileName: path,
                    category: Self.fileWriteFailureCategory(error)))
                LibraryStatus.shared.showNotice(
                    "Could not write tags to \(path): \(error.localizedDescription)",
                    severity: .warning,
                    autoDismissAfter: 6,
                    source: .metadata,
                    activityOperationID: activityID
                )
            }
            activity.update(id: activityID, completed: index + 1)
        }
        activity.finish(id: activityID,
            status: summary.failures.isEmpty ? .succeeded : .completedWithWarnings,
            severity: summary.failures.isEmpty ? .success : .warning,
            failures: summary.failures,
            counts: LibraryActivityCounts(filesAttempted: summary.attempted,
                filesSaved: summary.written, filesFailed: summary.failures.count))
        return summary
    }

    private static func fileWriteFailureCategory(_ error: Error) -> LibraryActivityFailureCategory {
        if let tagError = error as? TagWriterError, case .unsupportedFormat = tagError { return .unsupportedFormat }
        let cocoa = error as NSError
        if cocoa.domain == NSCocoaErrorDomain {
            switch cocoa.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return .missingFile
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return .permissionDenied
            default: break
            }
        }
        return .ioFailure
    }

    private func recordHealthMutation(
        total: Int,
        operation: () async -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError>
    ) async -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError> {
        let activityID = activity.begin(kind: .healthRepair, source: .library, total: total)
        let result = await operation()
        switch result {
        case .success(let outcome):
            activity.update(id: activityID, completed: total)
            activity.finish(id: activityID, status: .succeeded,
                counts: LibraryActivityCounts(catalogSaved: outcome.affectedTrackCount))
        case .failure(let error):
            activity.update(id: activityID, completed: 0, liveMessage: error.localizedDescription)
            activity.finish(id: activityID, status: Task.isCancelled ? .cancelled : .failed,
                severity: Task.isCancelled ? .information : .error)
        }
        return result
    }

    public var manualPlaylists: [LibraryPlaylistSnapshot] {
        librarySnapshots.snapshot.playlists.filter { $0.isSmart == false }
    }

    public var recentManualPlaylists: [LibraryPlaylistSnapshot] {
        Array(manualPlaylists.sorted { $0.dateModified > $1.dateModified }.prefix(8))
    }

    @discardableResult
    public func play(
        trackIDs: [UUID],
        shuffled: Bool = false
    ) -> Result<Void, PlaybackStartError> {
        var tracks = librarySnapshots.resolveTracks(ids: trackIDs)
        guard tracks.isEmpty == false else {
            let error = PlaybackStartError.emptySelection
            LibraryStatus.shared.showPlaybackError(error.localizedDescription)
            return .failure(error)
        }

        var skippedUnavailableTracks = 0
        while tracks.isEmpty == false {
            let result = playbackSession.startReplacement(PlaybackStartRequest(
                tracks: tracks,
                randomizesTracks: shuffled
            ))
            switch result {
            case .success:
                if skippedUnavailableTracks > 0 {
                    let noun = skippedUnavailableTracks == 1 ? "track" : "tracks"
                    LibraryStatus.shared.showNotice(
                        "Skipped \(skippedUnavailableTracks) unavailable \(noun)",
                        severity: .warning,
                        autoDismissAfter: 4
                    )
                }
                return result
            case .failure(.fileNotFound(let path)):
                guard let unavailableIndex = tracks.firstIndex(where: { $0.path == path }) else {
                    LibraryStatus.shared.showPlaybackError(
                        PlaybackStartError.fileNotFound(path).localizedDescription
                    )
                    return result
                }
                tracks.remove(at: unavailableIndex)
                skippedUnavailableTracks += 1
                if tracks.isEmpty {
                    LibraryStatus.shared.showPlaybackError(
                        PlaybackStartError.fileNotFound(path).localizedDescription
                    )
                    return result
                }
            case .failure:
                return result
            }
        }

        return .failure(.emptySelection)
    }

    /// UI playback entry point. Filesystem resolution runs away from the main
    /// actor and a newer request cancels the previous unresolved request.
    public func requestPlay(trackIDs: [UUID], shuffled: Bool = false) {
        playbackTask?.cancel()
        let tracks = librarySnapshots.resolveTracks(ids: trackIDs)
        guard tracks.isEmpty == false else {
            LibraryStatus.shared.showPlaybackError(PlaybackStartError.emptySelection.localizedDescription)
            return
        }
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var candidates = tracks
            var skippedMissing = 0
            while !candidates.isEmpty, !Task.isCancelled {
                let result = await self.playbackSession.startReplacementResolving(
                    PlaybackStartRequest(tracks: candidates, randomizesTracks: shuffled)
                )
                switch result {
                case .success:
                    if skippedMissing > 0 {
                        let noun = skippedMissing == 1 ? "track" : "tracks"
                        LibraryStatus.shared.showNotice(
                            "Skipped \(skippedMissing) missing \(noun)",
                            severity: .warning,
                            autoDismissAfter: 4
                        )
                    }
                    return
                case .failure(.fileNotFound(let path)):
                    guard let index = candidates.firstIndex(where: { $0.path == path }) else {
                        LibraryStatus.shared.showPlaybackError(
                            PlaybackStartError.fileNotFound(path).localizedDescription
                        )
                        return
                    }
                    candidates.remove(at: index)
                    skippedMissing += 1
                    if candidates.isEmpty {
                        LibraryStatus.shared.showPlaybackError(
                            PlaybackStartError.fileNotFound(path).localizedDescription
                        )
                        return
                    }
                case .failure(.cancelled):
                    return
                case .failure:
                    return
                }
            }
        }
    }

    public func requestPlay(playlistID: UUID) {
        guard let playlist = librarySnapshots.snapshot.playlists.first(where: {
            $0.id == playlistID
        }) else {
            requestPlay(trackIDs: [])
            return
        }
        let trackIDs = playlist.isSmart
            ? (playlist.rules?.filter(librarySnapshots.snapshot.tracks).map(\.id) ?? [])
            : playlist.trackIDs
        requestPlay(trackIDs: trackIDs)
    }

    public func requestPlayNow(trackID: UUID) {
        playbackTask?.cancel()
        guard let track = librarySnapshots.resolveTrack(id: trackID) else { return }
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.playbackSession.playTrackNowResolving(track)
            if case .failure(let error) = result, error != .cancelled {
                LibraryStatus.shared.showPlaybackError(error.userFacingMessage)
            }
        }
    }

    public func requestPlayQueueEntry(entryID: PlaybackQueueEntry.ID) {
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            _ = await self?.playbackSession.playOccurrenceResolving(entryID: entryID)
        }
    }

    @discardableResult
    public func play(playlistID: UUID) -> Result<Void, PlaybackStartError> {
        guard let playlist = librarySnapshots.snapshot.playlists.first(where: {
            $0.id == playlistID
        }) else {
            return play(trackIDs: [])
        }

        let trackIDs: [UUID]
        if playlist.isSmart, let rules = playlist.rules {
            trackIDs = rules.filter(librarySnapshots.snapshot.tracks).map(\.id)
        } else {
            trackIDs = playlist.trackIDs
        }
        return play(trackIDs: trackIDs)
    }

    @discardableResult
    public func playNow(trackID: UUID) -> Result<Void, PlaybackStartError> {
        guard let track = librarySnapshots.resolveTrack(id: trackID) else {
            return .failure(.emptySelection)
        }
        return playbackSession.playTrackNow(track)
    }

    @discardableResult
    public func playQueueEntry(
        entryID: PlaybackQueueEntry.ID
    ) -> Result<Void, PlaybackStartError> {
        playbackSession.playOccurrence(entryID: entryID)
    }

    public func playNext(trackIDs: [UUID]) {
        playbackSession.queue.enqueueNext(librarySnapshots.resolveTracks(ids: trackIDs))
    }

    public func addToQueue(trackIDs: [UUID]) {
        playbackSession.queue.enqueue(librarySnapshots.resolveTracks(ids: trackIDs))
    }

    @discardableResult
    public func addToPlaylist(trackIDs: [UUID], playlistID: UUID) -> LibraryActionResult {
        switch addTracks(trackIDs, toPlaylist: playlistID) {
        case .success: return .success(())
        case .failure(let error): return .failure(error)
        }
    }

    @discardableResult
    public func addTracks(
        _ trackIDs: [UUID],
        toPlaylist playlistID: UUID
    ) -> Result<PlaylistAddSummary, LibraryActionError> {
        guard let playlist = librarySnapshots.resolvePlaylist(id: playlistID),
              playlist.smartPlaylist == false else {
            return .failure(.unavailable("The selected playlist is not editable."))
        }
        let previousTracks = playlist.tracks
        let previousDate = playlist.dateModified
        let previousOrder = PlaylistOrderStore.order(
            playlistID: playlist.id,
            membership: previousTracks.map(\.id)
        )
        var seen = Set(playlist.tracks.map(\.id))
        let requestedUnique = trackIDs.reduce(into: [UUID]()) { result, id in
            if !result.contains(id) { result.append(id) }
        }
        let resolved = librarySnapshots.resolveTracks(ids: requestedUnique)
        let resolvedIDs = Set(resolved.map(\.id))
        let additions = resolved.filter { seen.insert($0.id).inserted }
        playlist.tracks.append(contentsOf: additions)
        playlist.dateModified = Date()
        let result = save("Could not add tracks to \(playlist.name)")
        if case .failure = result {
            playlist.tracks = previousTracks
            playlist.dateModified = previousDate
            if case .failure(let error) = result { return .failure(error) }
        } else {
            PlaylistOrderStore.set(previousOrder + additions.map(\.id), playlistID: playlist.id)
        }
        scheduleSnapshotRefresh()
        return .success(PlaylistAddSummary(
            requested: trackIDs.count,
            added: additions.count,
            duplicateSkipped: resolved.count - additions.count + (trackIDs.count - requestedUnique.count),
            missing: requestedUnique.count - resolvedIDs.count
        ))
    }

    @discardableResult
    public func removeTracks(
        _ trackIDs: [UUID],
        fromPlaylist playlistID: UUID
    ) -> LibraryActionResult {
        guard let playlist = librarySnapshots.resolvePlaylist(id: playlistID),
              playlist.smartPlaylist == false else {
            return .failure(.unavailable("Smart playlists cannot be edited manually."))
        }
        let previousTracks = playlist.tracks
        let previousDate = playlist.dateModified
        let previousOrder = PlaylistOrderStore.order(
            playlistID: playlist.id,
            membership: previousTracks.map(\.id)
        )
        let removed = Set(trackIDs)
        playlist.tracks.removeAll { removed.contains($0.id) }
        playlist.dateModified = Date()
        let result = save("Could not remove tracks from \(playlist.name)")
        if case .failure = result {
            playlist.tracks = previousTracks
            playlist.dateModified = previousDate
        } else {
            PlaylistOrderStore.set(previousOrder.filter { removed.contains($0) == false }, playlistID: playlist.id)
            scheduleSnapshotRefresh()
        }
        return result
    }

    @discardableResult
    public func reorderPlaylist(
        playlistID: UUID,
        expectedOrder: [UUID],
        newOrder: [UUID]
    ) -> LibraryActionResult {
        guard let playlist = librarySnapshots.resolvePlaylist(id: playlistID),
              playlist.smartPlaylist == false else {
            return .failure(.unavailable("Smart playlists cannot be reordered."))
        }
        let currentOrder = PlaylistOrderStore.order(
            playlistID: playlist.id,
            membership: playlist.tracks.map(\.id)
        )
        guard currentOrder == expectedOrder else {
            return .failure(.unavailable("The playlist changed. Refresh it before reordering."))
        }
        guard newOrder.count == currentOrder.count, Set(newOrder) == Set(currentOrder) else {
            return .failure(.unavailable("The reordered playlist must contain the same tracks."))
        }
        let tracksByID = Dictionary(uniqueKeysWithValues: playlist.tracks.map { ($0.id, $0) })
        let previousDate = playlist.dateModified
        playlist.tracks = newOrder.compactMap { tracksByID[$0] }
        playlist.dateModified = Date()
        let result = save("Could not reorder \(playlist.name)")
        if case .failure = result {
            playlist.tracks = expectedOrder.compactMap { tracksByID[$0] }
            playlist.dateModified = previousDate
        } else {
            PlaylistOrderStore.set(newOrder, playlistID: playlist.id)
            scheduleSnapshotRefresh()
        }
        return result
    }

    @discardableResult
    public func renamePlaylist(
        playlistID: UUID,
        expectedName: String,
        newName: String
    ) -> LibraryActionResult {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.unavailable("Enter a playlist name.")) }
        guard let playlist = librarySnapshots.resolvePlaylist(id: playlistID),
              !playlist.isSystemSmartPlaylist else {
            return .failure(.unavailable("This system playlist cannot be renamed."))
        }
        guard playlist.name == expectedName else {
            return .failure(.unavailable("The playlist name changed. Refresh before renaming it."))
        }
        let previousDate = playlist.dateModified
        playlist.name = trimmed
        playlist.dateModified = Date()
        let result = save("Could not rename the playlist")
        if case .failure = result {
            playlist.name = expectedName
            playlist.dateModified = previousDate
        } else {
            scheduleSnapshotRefresh()
        }
        return result
    }

    @discardableResult
    public func deletePlaylist(playlistID: UUID) -> LibraryActionResult {
        guard let playlist = librarySnapshots.resolvePlaylist(id: playlistID),
              !playlist.isSystemSmartPlaylist else {
            return .failure(.unavailable("This system playlist cannot be deleted."))
        }
        modelContainer.mainContext.delete(playlist)
        let result = save("Could not delete the playlist")
        if case .success = result {
            PlaylistOrderStore.remove(playlistID: playlistID)
            scheduleSnapshotRefresh()
        }
        return result
    }

    public func exportPlaylist(playlistID: UUID) {
        guard let snapshot = librarySnapshots.snapshot.playlists.first(where: { $0.id == playlistID }),
              let playlist = librarySnapshots.resolvePlaylist(id: playlistID) else { return }
        let ids = snapshot.isSmart
            ? (snapshot.rules?.filter(librarySnapshots.snapshot.tracks).map(\.id) ?? [])
            : snapshot.trackIDs
        PlaylistExporter.exportM3U(
            playlist: playlist,
            tracks: librarySnapshots.resolveTracks(ids: ids)
        )
    }

    public func requestNewPlaylist(
        trackIDs: [UUID],
        bringMainPlayerForward: Bool = false
    ) {
        playlistCreationRequest = PlaylistCreationRequest(
            trackIDs: trackIDs,
            bringMainPlayerForward: bringMainPlayerForward
        )
        if bringMainPlayerForward {
            NotificationCenter.default.post(name: .showMainPlayer, object: nil)
        }
    }

    public func requestPlaylistDestination(
        trackIDs: [UUID],
        bringMainPlayerForward: Bool = false
    ) {
        playlistDestinationRequest = PlaylistDestinationRequest(
            trackIDs: trackIDs,
            bringMainPlayerForward: bringMainPlayerForward
        )
        if bringMainPlayerForward {
            NotificationCenter.default.post(name: .showMainPlayer, object: nil)
        }
    }

    public func beginSidebarPlaylistTargeting(
        sourceID: String,
        sourceName: String,
        trackIDs: [UUID]
    ) {
        guard trackIDs.isEmpty == false else { return }
        if sidebarPlaylistTargetRequest?.sourceID == sourceID {
            sidebarPlaylistTargetRequest = nil
        } else {
            sidebarPlaylistTargetRequest = SidebarPlaylistTargetRequest(
                sourceID: sourceID,
                sourceName: sourceName,
                trackIDs: trackIDs
            )
        }
    }

    public func cancelSidebarPlaylistTargeting(sourceID: String? = nil) {
        if let sourceID, sidebarPlaylistTargetRequest?.sourceID != sourceID { return }
        sidebarPlaylistTargetRequest = nil
    }

    @discardableResult
    public func addSidebarTargetToPlaylist(playlistID: UUID) -> LibraryActionResult {
        guard let request = sidebarPlaylistTargetRequest,
              let playlist = manualPlaylists.first(where: { $0.id == playlistID }) else {
            return .failure(.unavailable("Choose an editable playlist."))
        }
        let result = addToPlaylist(trackIDs: request.trackIDs, playlistID: playlistID)
        if case .success = result {
            sidebarPlaylistTargetRequest = nil
            LibraryStatus.shared.showNotice(
                "Added “\(request.sourceName)” to “\(playlist.name)”",
                severity: .success,
                autoDismissAfter: 3
            )
        }
        return result
    }

    public func requestNewPlaylistForSidebarTarget() {
        guard let request = sidebarPlaylistTargetRequest else { return }
        requestNewPlaylist(trackIDs: request.trackIDs)
    }

    @discardableResult
    public func createPlaylist(
        name: String,
        request: PlaylistCreationRequest
    ) -> Result<UUID, LibraryActionError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return .failure(.unavailable("Enter a playlist name."))
        }
        let playlist = Playlist(name: trimmed)
        var seen: Set<UUID> = []
        playlist.tracks = librarySnapshots.resolveTracks(ids: request.trackIDs).filter {
            seen.insert($0.id).inserted
        }
        modelContainer.mainContext.insert(playlist)
        switch save("Could not create playlist \(trimmed)") {
        case .failure(let error):
            return .failure(error)
        case .success:
            PlaylistOrderStore.set(playlist.tracks.map(\.id), playlistID: playlist.id)
        }
        playlistCreationRequest = nil
        if sidebarPlaylistTargetRequest?.trackIDs == request.trackIDs {
            sidebarPlaylistTargetRequest = nil
        }
        navigation.selectRoot(.playlist(playlist.id))
        return .success(playlist.id)
    }

    public func showAlbum(albumID: UUID, bringMainPlayerForward: Bool = false) {
        navigation.showAlbum(albumID: albumID, bringMainPlayerForward: bringMainPlayerForward)
    }

    public func showArtist(name: String, bringMainPlayerForward: Bool = false) {
        navigation.showArtist(name: name, bringMainPlayerForward: bringMainPlayerForward)
    }

    public func showInfo(trackIDs: [UUID]) {
        let tracks = librarySnapshots.resolveTracks(ids: trackIDs)
        guard tracks.isEmpty == false else { return }
        TrackInfoWindowPresenter.show(
            tracks: tracks,
            actions: self,
            snapshots: librarySnapshots
        )
    }

    func canonicalArtworkAlbumIDs(containing albumIDs: [UUID]) async throws -> [UUID] {
        let snapshot = librarySnapshots.snapshot
        let wanted = Set(albumIDs)
        for id in wanted where snapshot.albumsByID[id] == nil {
            throw LibraryHealthMutationError.missingAlbum(id)
        }
        let groups = try await artworkScopeWorker.project(snapshot)
        let related = groups.filter { $0.albumIDs.contains(where: wanted.contains) }.flatMap(\.albumIDs)
        return Array(wanted.union(related)).sorted { $0.uuidString < $1.uuidString }
    }

    public func searchForArtwork(
        albumIDs: [UUID], title: String,
        completion: @escaping @MainActor () -> Void = {}
    ) {
        artworkSearchTask?.cancel()
        artworkSearchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let ids = try await canonicalArtworkAlbumIDs(containing: albumIDs)
                try Task.checkCancellation()
                let albums = ids.compactMap(librarySnapshots.resolveAlbum(id:))
                guard albums.count == ids.count, let album = albums.first else {
                    throw TrackMetadataMutationError.artworkScopeChanged
                }
                DiscogsSearchWindowPresenter.show(
                    album: album, relatedAlbums: albums, searchTitle: title,
                    modelContext: modelContainer.mainContext, actions: self,
                    completion: completion
                )
            } catch is CancellationError {
                return
            } catch {
                LibraryStatus.shared.showNotice(error.localizedDescription, severity: .warning)
            }
        }
    }

    public func showLyrics(trackID: UUID) {
        guard let track = librarySnapshots.resolveTrack(id: trackID) else { return }
        LyricsWindowPresenter.show(track: track)
    }

    public func showInFinder(trackIDs: [UUID]) {
        let paths = trackIDs.compactMap { librarySnapshots.trackSnapshot(id: $0)?.path }
        guard paths.isEmpty == false else { return }
        finderTask?.cancel()
        finderTask = Task { @MainActor [weak self, fileAvailabilityWorker] in
            let urls = await fileAvailabilityWorker.existingFileURLs(paths: paths)
            guard let self, Task.isCancelled == false else { return }
            guard urls.isEmpty == false else {
                let subject = paths.count == 1 ? "file is" : "files are"
                LibraryStatus.shared.showNotice(
                    "The selected \(subject) unavailable.",
                    severity: .warning,
                    autoDismissAfter: 4
                )
                return
            }
            revealFiles(urls)
        }
    }

    public func canShowInFinder(trackIDs: [UUID]) -> Bool {
        trackIDs.contains { librarySnapshots.trackSnapshot(id: $0) != nil }
    }

    public func canRefreshMetadata(trackIDs: [UUID]) -> Bool {
        canShowInFinder(trackIDs: trackIDs)
    }

    /// Set or clear the love state for tracks using the dedicated TrackFavorite model.
    /// This does NOT modify the track's numeric rating field.
    @discardableResult
    public func setTrackLoved(_ loved: Bool, trackIDs: [UUID]) -> LibraryActionResult {
        let context = modelContainer.mainContext
        let wanted = Set(trackIDs)
        let records: [TrackFavorite]
        do {
            records = try context.fetch(FetchDescriptor<TrackFavorite>())
        } catch {
            LibraryStatus.shared.showNotice(
                "Could not read track favorites: \(error.localizedDescription)",
                severity: .error,
                source: .metadata
            )
            return .failure(.persistence("Could not read track favorites: \(error.localizedDescription)"))
        }
        let existing = Dictionary(uniqueKeysWithValues: records.map { ($0.trackID, $0) })
        for trackID in wanted {
            if loved, existing[trackID] == nil {
                context.insert(TrackFavorite(trackID: trackID))
            } else if loved == false, let record = existing[trackID] {
                context.delete(record)
            }
        }
        return save("Could not update track favorites")
    }

    /// Set the numeric star rating (0-5) for tracks. Independent of love state.
    /// Optimistically updates the snapshot for immediate UI feedback.
    @discardableResult
    public func setTrackRating(_ rating: Int, trackIDs: [UUID]) -> LibraryActionResult {
        let tracks = librarySnapshots.resolveTracks(ids: trackIDs)
        let clamped = max(0, min(5, rating))
        let previous = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0.rating) })

        // Optimistic snapshot update for immediate UI feedback
        let optimisticRatings = Dictionary(uniqueKeysWithValues: trackIDs.map { ($0, clamped) })
        librarySnapshots.updateTrackRatings(optimisticRatings)

        for track in tracks {
            track.rating = clamped
        }
        let result = save("Could not update rating")
        if case .failure = result {
            for track in tracks { track.rating = previous[track.id] ?? track.rating }
            // Revert optimistic update on failure
            librarySnapshots.updateTrackRatings(previous)
        }
        return result
    }

    @discardableResult
    public func setAlbumFavorite(_ favorite: Bool, albumIDs: [UUID]) -> LibraryActionResult {
        let context = modelContainer.mainContext
        let wanted = Set(albumIDs)
        let records: [AlbumFavorite]
        do {
            records = try context.fetch(FetchDescriptor<AlbumFavorite>())
        } catch {
            LibraryStatus.shared.showNotice(
                "Could not read album favorites: \(error.localizedDescription)",
                severity: .error,
                source: .metadata
            )
            return .failure(.persistence("Could not read album favorites: \(error.localizedDescription)"))
        }
        let existing = Dictionary(uniqueKeysWithValues: records.map { ($0.albumID, $0) })
        for albumID in wanted {
            if favorite, existing[albumID] == nil {
                context.insert(AlbumFavorite(albumID: albumID))
            } else if favorite == false, let record = existing[albumID] {
                context.delete(record)
            }
        }
        return save("Could not update album favorites")
    }

    public func refreshMetadata(trackIDs: [UUID]) {
        metadataTask?.cancel()
        let tracks = librarySnapshots.resolveTracks(ids: trackIDs)
        guard tracks.isEmpty == false else { return }
        let operationID = LibraryStatus.shared.beginOperation(
            message: "Re-reading metadata…",
            total: tracks.count,
            activityKind: .readFileTags,
            source: .metadata,
            cancellation: { [weak self] in self?.metadataTask?.cancel() }
        )
        metadataTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var completed = 0
            var refreshed = 0
            var missing = 0
            var unavailable = 0
            var failed = 0
            var failureDetails: [LibraryActivityFailure] = []
            do {
                for track in tracks {
                    guard Task.isCancelled == false else {
                        LibraryStatus.shared.endOperation(message: "Metadata update canceled", operationID: operationID, activityStatus: .cancelled)
                        return
                    }
                    do {
                        switch try await TrackImporter.refreshMetadata(
                            for: track,
                            in: self.modelContainer.mainContext
                        ) {
                        case .refreshed:
                            refreshed += 1
                        case .fileMissing:
                            missing += 1
                            failureDetails.append(LibraryActivityFailure(fileName: track.path, category: .missingFile))
                        case .fileUnavailable:
                            unavailable += 1
                            failureDetails.append(LibraryActivityFailure(fileName: track.path, category: .unavailableFile))
                        case .unreadable:
                            failed += 1
                            failureDetails.append(LibraryActivityFailure(fileName: track.path, category: .ioFailure))
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        failed += 1
                        failureDetails.append(LibraryActivityFailure(fileName: track.path, category: .ioFailure))
                    }
                    completed += 1
                    LibraryStatus.shared.updateOperation(
                        completed: completed,
                        message: "Re-reading metadata \(completed) of \(tracks.count)…",
                        operationID: operationID
                    )
                }
                if refreshed > 0 {
                    _ = try AlbumRelationshipReconciler.reconcile(
                        in: self.modelContainer.mainContext,
                        affectedTrackIDs: Set(tracks.map(\.id))
                    )
                }
                if refreshed == 0 || self.save("Could not save refreshed metadata").isSuccess {
                    let summary = "Refreshed \(refreshed), unavailable \(unavailable), missing \(missing), failed \(failed)"
                    let severity: LibraryNoticeSeverity = unavailable > 0 || missing > 0 || failed > 0
                        ? .warning
                        : .success
                    LibraryStatus.shared.endOperation(message: summary, severity: severity,
                        operationID: operationID, activityStatus: severity == .warning ? .completedWithWarnings : .succeeded,
                        failures: failureDetails,
                        counts: LibraryActivityCounts(catalogSaved: refreshed, filesFailed: failed + missing + unavailable))
                } else {
                    LibraryStatus.shared.endOperation(
                        message: "Metadata update was not saved",
                        severity: .error, operationID: operationID, activityStatus: .failed, failures: failureDetails
                    )
                }
            } catch is CancellationError {
                self.modelContainer.mainContext.rollback()
                LibraryStatus.shared.endOperation(message: "Metadata update canceled", operationID: operationID, activityStatus: .cancelled, failures: failureDetails)
            } catch {
                self.modelContainer.mainContext.rollback()
                LibraryStatus.shared.endOperation(
                    message: "Could not re-read metadata: \(error.localizedDescription)",
                    severity: .error, operationID: operationID, activityStatus: .failed, failures: failureDetails
                )
            }
        }
    }

    public func consolidateDuplicateTracks(
        trackIDs: [UUID],
        keeperID: UUID,
        expectedChecksum: String
    ) async -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError> {
        var seen = Set<UUID>()
        let uniqueIDs = trackIDs.filter { seen.insert($0).inserted }
        guard uniqueIDs.count > 1, uniqueIDs.contains(keeperID) else {
            return .failure(.emptyPlan)
        }
        let tracks = librarySnapshots.resolveTracks(ids: uniqueIDs)
        guard tracks.count == uniqueIDs.count,
              tracks.allSatisfy({ $0.checksum == expectedChecksum && $0.checksum.isEmpty == false }),
              let keeper = tracks.first(where: { $0.id == keeperID }) else {
            return .failure(.persistence("The duplicate group changed. Analyze it again before removing copies."))
        }
        let redundant = tracks.filter { $0.id != keeperID }
        let redundantIDs = Set(redundant.map(\.id))
        let removedPaths = redundant.map(\.path)
        if let currentID = playbackSession.queue.currentTrack?.id,
           redundantIDs.contains(currentID) {
            return .failure(.currentlyPlaying(currentID))
        }
        let queueBefore = playbackSession.queue.identitySnapshot()
        let orderBefore = PlaylistOrderStore.fullSnapshot()
        let exclusionsBefore = importExclusions.snapshot()
        do {
            let (outcome, catalogReceipt) = try await healthMutations.consolidateDuplicateTracks(
                LibraryDuplicateConsolidation(
                    trackIDs: uniqueIDs,
                    keeperID: keeperID,
                    expectedChecksum: expectedChecksum
                )
            )
            _ = playbackSession.queue.replaceTrackReferences(from: redundantIDs, with: keeper)
            for (playlistID, order) in orderBefore {
                var orderSeen = Set<UUID>()
                let updated = order.map { redundantIDs.contains($0) ? keeperID : $0 }
                    .filter { orderSeen.insert($0).inserted }
                PlaylistOrderStore.set(updated, playlistID: playlistID)
            }
            importExclusions.exclude(paths: removedPaths)
            let receipt = catalogReceipt.withCrossDomain(.init(
                queueBefore: queueBefore,
                queueAfter: playbackSession.queue.identitySnapshot(),
                playlistOrderBefore: orderBefore,
                playlistOrderAfter: PlaylistOrderStore.fullSnapshot(),
                exclusionsBefore: exclusionsBefore,
                exclusionsAfter: importExclusions.snapshot()
            ))
            await librarySnapshots.refresh()
            latestHealthReceipt = receipt
            healthUndoAvailable = true
            return .success(outcome)
        } catch let error as LibraryHealthMutationError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(.persistence("Duplicate consolidation was cancelled."))
        } catch {
            return .failure(.persistence(error.localizedDescription))
        }
    }

    @discardableResult
    public func deleteTracks(trackIDs: [UUID]) -> LibraryActionResult {
        let removedPaths = deleteTrackModels(trackIDs: trackIDs)
        let result = save("Could not delete tracks from the library")
        if case .success = result {
            importExclusions.exclude(paths: removedPaths)
            removeFromPlayback(trackIDs: trackIDs)
        }
        return result
    }

    @discardableResult
    public func deleteAlbum(albumIDs: [UUID], trackIDs: [UUID]) -> LibraryActionResult {
        let removedPaths = deleteTrackModels(trackIDs: trackIDs)
        let context = modelContainer.mainContext
        let removedAlbumIDs = Set(albumIDs)
        let favorites: [AlbumFavorite]
        do {
            favorites = try context.fetch(FetchDescriptor<AlbumFavorite>())
        } catch {
            context.rollback()
            LibraryStatus.shared.showNotice(
                "Could not read album favorites: \(error.localizedDescription)",
                severity: .error,
                source: .metadata
            )
            return .failure(.persistence("Could not read album favorites: \(error.localizedDescription)"))
        }
        for favorite in favorites where removedAlbumIDs.contains(favorite.albumID) {
            context.delete(favorite)
        }
        for album in albumIDs.compactMap(librarySnapshots.resolveAlbum(id:)) {
            context.delete(album)
        }
        let result = save("Could not delete the album from the library")
        if case .success = result {
            importExclusions.exclude(paths: removedPaths)
            removeFromPlayback(trackIDs: trackIDs)
        }
        return result
    }

    private func deleteTrackModels(trackIDs: [UUID]) -> [String] {
        let tracks = librarySnapshots.resolveTracks(ids: trackIDs)
        for track in tracks {
            modelContainer.mainContext.delete(track)
        }
        return tracks.map(\.path)
    }

    private func removeFromPlayback(trackIDs: [UUID]) {
        let removed = Set(trackIDs)
        let queue = playbackSession.queue
        if queue.removeTracks(trackIDs: removed) {
            playbackSession.engine.stop()
        }
    }

    @discardableResult
    private func save(_ failureMessage: String) -> LibraryActionResult {
        do {
            try modelContainer.mainContext.save()
            return .success(())
        } catch {
            modelContainer.mainContext.rollback()
            let message = "\(failureMessage): \(error.localizedDescription)"
            LibraryStatus.shared.showNotice(message, severity: .error, source: .library)
            return .failure(.persistence(message))
        }
    }

    private func scheduleSnapshotRefresh() {
        Task { @MainActor [weak librarySnapshots] in
            await librarySnapshots?.refresh()
        }
    }

    /// Batch re-analyze BPM for all tracks missing it.
    public func reanalyzeBPM() {
        metadataTask?.cancel()
        metadataTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let context = self.modelContainer.mainContext
            let descriptor = FetchDescriptor<Track>(
                predicate: #Predicate { $0.beatsPerMinute == 0 }
            )
            guard let tracks = try? context.fetch(descriptor), !tracks.isEmpty else {
                LibraryStatus.shared.showNotice("All tracks already have BPM data.", severity: .information)
                self.metadataTask = nil
                return
            }

            let status = LibraryStatus.shared
            let operationID = status.beginOperation(message: "Analyzing BPM…", total: tracks.count,
                activityKind: .bpmAnalysis, source: .metadata) { [weak self] in
                self?.metadataTask?.cancel()
            }

            NSLog("Songbird: BPM analysis starting for %d tracks", tracks.count)
            var analyzed = 0
            var processed = 0
            for track in tracks {
                if Task.isCancelled { break }
                let resolution = await self.fileAvailabilityWorker.resolve(path: track.path)
                guard case .available(let url) = resolution else {
                    processed += 1
                    status.updateOperation(
                        completed: processed,
                        message: "BPM: \(track.title) → unavailable", operationID: operationID
                    )
                    continue
                }
                let bpm = await MetadataReader.detectBPM(from: url)
                processed += 1
                if bpm > 0 {
                    track.beatsPerMinute = bpm
                    analyzed += 1
                } else {
                    NSLog("Songbird: BPM detection returned 0 for %@", track.path)
                }
                status.updateOperation(
                    completed: processed,
                    message: "BPM: \(track.title) → \(bpm > 0 ? "\(bpm)" : "—")", operationID: operationID
                )
            }

            var saved = false
            if !Task.isCancelled {
                if self.save("Could not save BPM results").isSuccess {
                    saved = true
                    await self.librarySnapshots.refresh()
                }
            }
            status.endOperation(
                message: Task.isCancelled ? "BPM analysis canceled" : (saved ? "BPM analysis complete: \(analyzed)/\(tracks.count) tracks updated." : "BPM results could not be saved"),
                severity: Task.isCancelled ? .information : (saved ? .success : .error),
                operationID: operationID,
                activityStatus: Task.isCancelled ? .cancelled : (saved ? .succeeded : .failed),
                counts: LibraryActivityCounts(catalogSaved: saved ? analyzed : 0)
            )
            NSLog("Songbird: BPM analysis finished: %d/%d updated", analyzed, tracks.count)
            self.metadataTask = nil
        }
    }
}

private extension Result where Success == Void, Failure == LibraryActionError {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
