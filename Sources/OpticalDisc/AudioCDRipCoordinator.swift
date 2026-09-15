import Combine
import Foundation
import SwiftData

public protocol AudioCDArtworkFetching: Sendable {
    func artworkData(from url: URL) async throws -> Data
}

public struct URLSessionAudioCDArtworkFetcher: AudioCDArtworkFetching {
    public init() {}

    public func artworkData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (200..<300).contains(response.statusCode),
              !data.isEmpty,
              data.count <= 25 * 1024 * 1024 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

@MainActor
public final class AudioCDRipCoordinator: ObservableObject {
    @Published public private(set) var isRipping = false
    @Published public private(set) var isImported = false
    @Published public private(set) var isCancelling = false
    @Published public private(set) var progress: AudioCDRipProgress?
    @Published public private(set) var completionMessage: String?
    @Published public private(set) var lastError: String?
    @Published public private(set) var destinationURL: URL?
    @Published public private(set) var needsMetadataRecovery = false

    private let ripper: AudioCDRipper
    private let artworkFetcher: any AudioCDArtworkFetching
    private let destinationRoot: URL
    private let clock: @Sendable () -> DiscogsFetchStamp?
    private let discogsArtworkFetcher: @Sendable (URL, DiscogsContentEvidence) async throws -> Data
    private var completedResults: [AudioCDRipResult] = []
    private var recoveryDiscID: DiscIdentifier?
    private var ripTask: Task<Void, Never>?
    private var lastProgressPublication = ContinuousClock.now - .seconds(1)

    public init(
        ripper: AudioCDRipper = AudioCDRipper(),
        artworkFetcher: any AudioCDArtworkFetching = URLSessionAudioCDArtworkFetcher(),
        destinationRoot: URL = AudioCDRipPaths.defaultRoot,
        clock: @escaping @Sendable () -> DiscogsFetchStamp? = { DiscogsClock.sample() },
        discogsArtworkFetcher: (@Sendable (URL, DiscogsContentEvidence) async throws -> Data)? = nil
    ) {
        self.ripper = ripper
        self.artworkFetcher = artworkFetcher
        self.destinationRoot = destinationRoot
        self.clock = clock
        self.discogsArtworkFetcher = discogsArtworkFetcher ?? { url, evidence in
            try await DiscogsClient(tokenProvider: { throw DiscogsError.tokenMissing })
                .downloadImage(from: url, evidence: evidence)
        }
    }

    deinit { ripTask?.cancel() }

    public func start(
        disc: AudioDisc,
        modelContext: ModelContext,
        playbackEngine: PlaybackEngine,
        opticalDiscs: OpticalDiscService,
        libraryStatus: LibraryStatus
    ) {
        guard !isRipping, !isImported else { return }
        if recoveryDiscID != disc.id { completedResults = [] }
        recoveryDiscID = disc.id
        needsMetadataRecovery = false
        playbackEngine.removeAudioCDTracks(for: [disc.id], reportRemoval: false)

        isRipping = true
        isCancelling = false
        progress = nil
        completionMessage = nil
        lastError = nil
        destinationURL = AudioCDRipPaths.albumDirectory(for: disc, root: destinationRoot)
        opticalDiscs.setImporting(true, discID: disc.id)
        LibrarySnapshotStore.active?.beginBulkUpdates()
        libraryStatus.beginScan(total: disc.tracks.count)
        libraryStatus.setImportCancellation { [weak self] in self?.cancel() }

        ripTask = Task {
            await self.performRip(
                disc: disc,
                modelContext: modelContext,
                opticalDiscs: opticalDiscs,
                libraryStatus: libraryStatus
            )
        }
    }

    public func cancel() {
        guard isRipping else { return }
        isCancelling = true
        ripTask?.cancel()
    }

    public func clearMessages() {
        completionMessage = nil
        lastError = nil
    }

    public func refreshImportStatus(for disc: AudioDisc, modelContext: ModelContext) {
        isImported = Self.hasCompleteLibraryImport(for: disc, modelContext: modelContext)
    }

    private func performRip(
        disc: AudioDisc,
        modelContext: ModelContext,
        opticalDiscs: OpticalDiscService,
        libraryStatus: LibraryStatus
    ) async {
        let importContext = ModelContext(modelContext.container)
        importContext.autosaveEnabled = false
        defer { if importContext.hasChanges { importContext.rollback() } }
        do {
            let results = try await ripper.rip(
                disc: disc,
                destinationRoot: destinationRoot,
                completed: completedResults
            ) { value in
                await self.receive(progress: value, libraryStatus: libraryStatus)
            }
            completedResults = results
            try Task.checkCancellation()

            try requireFresh(disc)
            let artworkData = await fetchArtwork(from: disc)
            try requireFresh(disc)
            var importedCount = 0
            for (index, result) in results.enumerated() {
                try Task.checkCancellation()
                if try await importResult(
                    result,
                    disc: disc,
                    artworkData: artworkData,
                    modelContext: importContext
                ) {
                    importedCount += 1
                }
                libraryStatus.updateScan(scanned: index + 1, total: results.count)
            }
            try requireFresh(disc)
            _ = try AlbumRelationshipReconciler.reconcile(in: importContext)
            try requireFresh(disc)
            try importContext.save()
            refreshImportStatus(for: disc, modelContext: importContext)
            completedResults = []
            needsMetadataRecovery = false

            libraryStatus.endScan(added: importedCount)
            let count = results.count
            completionMessage = "Imported \(count) track\(count == 1 ? "" : "s") as lossless ALAC."
        } catch AudioCDRipError.metadataExpired(let completed) {
            for result in completed {
                completedResults.removeAll { $0.track.source == result.track.source }
                completedResults.append(result)
            }
            needsMetadataRecovery = true
            libraryStatus.endScan(added: 0)
            lastError = "Discogs results expired. Completed audio was kept. Refresh metadata or use CD-Text to resume."
        } catch is CancellationError {
            libraryStatus.endScan(added: 0)
            libraryStatus.statusMessage = "CD import canceled"
            completionMessage = "CD import canceled. Completed files were kept so the import can resume."
        } catch {
            libraryStatus.endScan(added: 0)
            libraryStatus.statusMessage = "CD import failed"
            lastError = error.localizedDescription
        }

        isRipping = false
        isCancelling = false
        opticalDiscs.setImporting(false, discID: disc.id)
        LibrarySnapshotStore.active?.endBulkUpdates()
        ripTask = nil
    }

    private func receive(progress value: AudioCDRipProgress, libraryStatus: LibraryStatus) {
        let now = ContinuousClock.now
        guard now - lastProgressPublication >= .milliseconds(100)
                || value.completedDiscSectors >= value.totalDiscSectors else {
            return
        }
        lastProgressPublication = now
        progress = value
        libraryStatus.updateScan(
            scanned: max(0, value.trackIndex - 1),
            total: value.totalTracks
        )
        libraryStatus.statusMessage = "Importing CD track \(value.trackIndex) of \(value.totalTracks)…"
    }

    private func fetchArtwork(from disc: AudioDisc) async -> Data? {
        guard let url = disc.artworkURL else { return nil }
        if let evidence = disc.discogsEvidence {
            return try? await discogsArtworkFetcher(url, evidence)
        }
        return try? await artworkFetcher.artworkData(from: url)
    }

    private func requireFresh(_ disc: AudioDisc) throws {
        if let evidence = disc.discogsEvidence, !evidence.isFresh(at: clock()) {
            throw AudioCDRipError.metadataExpired(completed: completedResults)
        }
    }

    func importResult(
        _ result: AudioCDRipResult,
        disc: AudioDisc,
        artworkData: Data?,
        modelContext: ModelContext
    ) async throws -> Bool {
        try requireFresh(disc)
        let path = Track.standardizedPath(result.fileURL.path)
        let imported = try await TrackImporter.importURL(result.fileURL, into: modelContext)
        try requireFresh(disc)
        let libraryTrack: Track
        if let imported {
            libraryTrack = imported
        } else if let existing = try findTrack(at: path, in: modelContext) {
            libraryTrack = existing
        } else {
            let track = Track(path: path)
            modelContext.insert(track)
            libraryTrack = track
        }

        libraryTrack.title = result.track.title
        libraryTrack.artist = result.track.artist
        libraryTrack.album = disc.title
        libraryTrack.albumArtist = AudioCDRipPaths.albumArtist(for: disc)
        libraryTrack.year = disc.year ?? 0
        libraryTrack.trackNumber = result.track.number
        libraryTrack.duration = result.track.duration
        libraryTrack.sampleRate = 44_100
        if libraryTrack.bitrate == 0 {
            let size = (try? result.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if result.track.duration > 0 {
                libraryTrack.bitrate = Int(
                    (Double(size) * 8 / result.track.duration / 1_000).rounded()
                )
            }
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        libraryTrack.fileSize = (attributes?[.size] as? Int64) ?? libraryTrack.fileSize
        libraryTrack.dateModified = (attributes?[.modificationDate] as? Date) ?? Date()
        libraryTrack.checksum = Track.contentChecksum(at: path)
        try requireFresh(disc)
        try TrackImporter.linkRelations(for: libraryTrack, artworkData: artworkData, in: modelContext)
        return imported != nil
    }

    private func findTrack(at path: String, in context: ModelContext) throws -> Track? {
        try context.fetch(FetchDescriptor<Track>()).first { $0.path == path }
    }

    static func hasCompleteLibraryImport(
        for disc: AudioDisc,
        modelContext: ModelContext,
        fileManager: FileManager = .default
    ) -> Bool {
        guard !disc.tracks.isEmpty else { return false }

        let album = disc.title
        let albumArtist = AudioCDRipPaths.albumArtist(for: disc)
        let candidates: [Track]
        do {
            candidates = try modelContext.fetch(FetchDescriptor<Track>()).filter {
                $0.album == album && $0.albumArtist == albumArtist
            }
        } catch {
            LibraryStatus.shared.showNotice(
                "Could not verify the imported CD: \(error.localizedDescription)",
                severity: .warning
            )
            return false
        }

        return disc.tracks.allSatisfy { discTrack in
            candidates.contains { libraryTrack in
                libraryTrack.trackNumber == discTrack.number
                    && libraryTrack.title == discTrack.title
                    && libraryTrack.artist == discTrack.artist
                    && abs(libraryTrack.duration - discTrack.duration) <= (1.0 / 75.0)
                    && libraryTrack.sampleRate == 44_100
                    && libraryTrack.fileKind == "M4A"
                    && fileManager.fileExists(atPath: libraryTrack.path)
            }
        }
    }
}
