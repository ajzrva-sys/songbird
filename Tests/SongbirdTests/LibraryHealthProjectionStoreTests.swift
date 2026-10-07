import Combine
import Foundation
import SwiftData
import Testing
@testable import SongbirdLib

@Suite("Library Health projection store", .serialized)
struct LibraryHealthProjectionStoreTests {
    @Test("File checks stay not checked until explicitly requested and publish paired results")
    @MainActor
    func explicitFileCheckPublishesPairedResults() async throws {
        let schema = Schema([
            Track.self, Album.self, Artist.self, Playlist.self, AlbumFavorite.self, TrackFavorite.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                "HealthProjection-\(UUID().uuidString)",
                schema: schema,
                isStoredInMemoryOnly: true
            )]
        )
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-health-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let missing = Track(
            path: folder.appendingPathComponent("missing.flac").path,
            title: "Missing"
        )
        let unavailable = Track(
            path: "/Volumes/songbird-unmounted-\(UUID().uuidString)/unavailable.flac",
            title: "Unavailable"
        )
        container.mainContext.insert(missing)
        container.mainContext.insert(unavailable)
        try container.mainContext.save()

        let snapshots = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await snapshots.refresh()
        let health = LibraryHealthProjectionStore(
            snapshots: snapshots,
            configuredSearchRoots: { [] }
        )
        health.observe(category: .missingFiles)

        guard case .notChecked = health.state(for: .missingFiles) else {
            Issue.record("Observing a file category must not probe the filesystem")
            return
        }
        guard case .notChecked = health.state(for: .unavailableVolumes) else {
            Issue.record("The paired category must remain not checked")
            return
        }

        health.check(category: .missingFiles)
        let missingResult = try await readyResult(for: .missingFiles, in: health)
        let unavailableResult = try await readyResult(for: .unavailableVolumes, in: health)

        #expect(missingResult.affectedTrackIDs == [missing.id])
        #expect(unavailableResult.affectedTrackIDs == [unavailable.id])
        #expect(missingResult.sourceRevision == unavailableResult.sourceRevision)
        #expect(missingResult.checkedAt == unavailableResult.checkedAt)
    }

    @Test("Explicit file check publishes configured-root relocation evidence")
    @MainActor
    func fileCheckPublishesRelocationEvidence() async throws {
        let schema = Schema([
            Track.self, Album.self, Artist.self, Playlist.self, AlbumFavorite.self, TrackFavorite.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                "HealthRelocation-\(UUID().uuidString)",
                schema: schema,
                isStoredInMemoryOnly: true
            )]
        )
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-health-relocation-projection-\(UUID().uuidString)")
        let root = base.appendingPathComponent("configured")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let candidate = root.appendingPathComponent("found.flac")
        try Data([1, 2, 3]).write(to: candidate)
        let track = Track(path: base.appendingPathComponent("missing/found.flac").path, title: "Found")
        track.checksum = Track.contentChecksum(at: candidate.path)
        container.mainContext.insert(track)
        try container.mainContext.save()

        let snapshots = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await snapshots.refresh()
        let health = LibraryHealthProjectionStore(
            snapshots: snapshots,
            configuredSearchRoots: { [root.path] }
        )
        health.check(category: .missingFiles)
        let result = try await readyResult(for: .missingFiles, in: health)
        let finding = try #require(result.fileReport?.findings.first)

        #expect(finding.trackID == track.id)
        #expect(finding.relocationCandidates.count == 1)
        #expect(finding.relocationCandidates.first?.path == candidate.path)
        #expect(finding.relocationCandidates.first?.checksumMatchesCatalog == true)
    }

    @Test("Missing Artwork uses canonical multi-disc album groups")
    @MainActor
    func artworkUsesCanonicalGroups() async throws {
        let schema = Schema([
            Track.self, Album.self, Artist.self, Playlist.self, AlbumFavorite.self, TrackFavorite.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                "HealthArtwork-\(UUID().uuidString)",
                schema: schema,
                isStoredInMemoryOnly: true
            )]
        )
        for disc in 1...2 {
            let album = Album(title: "Collection CD \(disc)", artist: "Artist")
            let track = Track(
                path: "/Music/Collection/CD \(disc)/01.flac",
                title: "Disc \(disc)",
                artist: "Artist",
                album: album.title
            )
            track.albumArtist = "Artist"
            track.albumRelation = album
            container.mainContext.insert(album)
            container.mainContext.insert(track)
        }
        try container.mainContext.save()
        let snapshots = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await snapshots.refresh()
        let health = LibraryHealthProjectionStore(snapshots: snapshots, configuredSearchRoots: { [] })

        health.check(category: .missingArtwork)
        let result = try await readyResult(for: .missingArtwork, in: health)
        let finding = try #require(result.artworkReport?.findings.first)
        #expect(result.artworkReport?.findings.count == 1)
        #expect(finding.albumIDs.count == 2)
        #expect(finding.trackIDs.count == 2)
        #expect(finding.title != "CD 1")
    }

    @Test("Artwork rescan counts missing albums and reuses shared-folder evidence")
    @MainActor
    func artworkRescanScopeAndProgress() async throws {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self, AlbumFavorite.self, TrackFavorite.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(
            "ArtworkScope-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true
        )])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("songbird-artwork-scope-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cover = folder.appendingPathComponent("cover.jpg")
        try Data([1]).write(to: cover)
        for index in 0..<3 {
            let album = Album(title: "Album \(index)", artist: "Artist")
            if index == 2 { album.artworkData = Data([1]) }
            container.mainContext.insert(album)
            for number in 0..<4 {
                let track = Track(path: folder.appendingPathComponent("\(index)-\(number).flac").path,
                                  title: "Track \(number)", artist: "Artist", album: album.title)
                track.albumRelation = album
                container.mainContext.insert(track)
            }
        }
        try container.mainContext.save()
        let snapshots = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await snapshots.refresh()
        let health = LibraryHealthProjectionStore(snapshots: snapshots, configuredSearchRoots: { [] })
        var observed: [LibraryHealthCheckProgress] = []
        let subscription = health.objectWillChange.sink {
            observed.append(health.progress(for: .missingArtwork))
        }
        defer { subscription.cancel() }
        health.rescanLocalEvidence(category: .missingArtwork)
        #expect(health.progress(for: .missingArtwork).total == 0, "Do not initially advertise the whole track count")
        let result = try await readyResult(for: .missingArtwork, in: health)
        #expect(result.artworkReport?.findings.count == 2)
        #expect(result.affectedTrackCount == 8)
        #expect(result.artworkReport?.findings.allSatisfy { $0.localCandidatePaths == [cover.path] } == true)
        #expect(observed.contains { $0.total == 2 })
        #expect(observed.allSatisfy { $0.total <= 2 })

        let groups = try await LibraryAlbumProjectionWorker().project(snapshots.snapshot)
            .filter { $0.artworkReference == nil }
        let recorder = ArtworkProgressRecorder()
        let worker = LibraryArtworkEvidenceWorker()
        let candidates = try await worker.candidatePaths(for: groups, snapshot: snapshots.snapshot) { completed, total in
            await recorder.append(LibraryHealthCheckProgress(completed: completed, total: total))
            if completed == 1 {
                // A second enumeration would see this new name. Shared-folder
                // groups must reuse the first evidence for this run instead.
                try? FileManager.default.removeItem(at: cover)
                try? Data([2]).write(to: folder.appendingPathComponent("folder.jpg"))
            }
        }
        #expect(candidates.values.allSatisfy { $0 == [cover.path] })
        #expect(await recorder.values == [.init(completed: 1, total: 2), .init(completed: 2, total: 2)])
        let refreshed = try await worker.candidatePaths(for: groups, snapshot: snapshots.snapshot)
        #expect(refreshed.values.allSatisfy { $0 == [folder.appendingPathComponent("folder.jpg").path] })
    }

    @MainActor
    private func readyResult(
        for category: LibraryHealthCategory,
        in store: LibraryHealthProjectionStore
    ) async throws -> LibraryHealthCategoryResult {
        // Parallel SwiftData suites can briefly saturate the shared test process.
        // This helper verifies eventual publication, not a UI latency budget.
        for _ in 0..<1_000 {
            if case .ready(let result) = store.state(for: category) { return result }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw ProjectionTestError.timedOut(category)
    }

    private enum ProjectionTestError: Error {
        case timedOut(LibraryHealthCategory)
    }
}

private actor ArtworkProgressRecorder {
    var values: [LibraryHealthCheckProgress] = []
    func append(_ value: LibraryHealthCheckProgress) { values.append(value) }
}
