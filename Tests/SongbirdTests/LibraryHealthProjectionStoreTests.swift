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
