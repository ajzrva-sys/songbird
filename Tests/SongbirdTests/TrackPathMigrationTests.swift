import SwiftData
import XCTest
@testable import SongbirdLib

final class TrackPathMigrationTests: XCTestCase {
    func testV1MigrationMergesDuplicatePathsIntoOldestTrack() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-path-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appendingPathComponent("library.store")
        let path = folder.appendingPathComponent("Album/../Album/song.flac").path
        let standardized = Track.standardizedPath(path)
        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)
        let lastPlayed = Date(timeIntervalSince1970: 300)

        try seedV1Store(
            at: storeURL,
            path: path,
            oldDate: oldDate,
            newDate: newDate,
            lastPlayed: lastPlayed
        )

        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: SongbirdMigrationPlan.self,
            configurations: config
        )
        let context = ModelContext(container)
        let tracks = try context.fetch(FetchDescriptor<Track>())
        let playlists = try context.fetch(FetchDescriptor<Playlist>())

        XCTAssertEqual(tracks.count, 1)
        let survivor = try XCTUnwrap(tracks.first)
        XCTAssertEqual(survivor.path, standardized)
        XCTAssertEqual(survivor.dateAdded, oldDate)
        XCTAssertEqual(survivor.title, "Newest Metadata")
        XCTAssertEqual(survivor.rating, 5)
        XCTAssertEqual(survivor.playCount, 42)
        XCTAssertEqual(survivor.lastPlayed, lastPlayed)
        XCTAssertEqual(playlists.first?.tracks.count, 1)
        XCTAssertEqual(playlists.first?.tracks.first?.id, survivor.id)
    }

    func testUniquePathUpsertsInsteadOfCreatingASecondTrack() throws {
        let schema = Schema(versionedSchema: SongbirdSchemaV2.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let rawPath = "/Music/Album/../Album/song.flac"

        context.insert(Track(path: rawPath, title: "First"))
        try context.save()
        context.insert(Track(path: rawPath, title: "Second"))
        try context.save()

        let tracks = try context.fetch(FetchDescriptor<Track>())
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks.first?.path, Track.standardizedPath(rawPath))
    }

    func testDifferentPathsWithSameChecksumRemainSeparate() throws {
        let schema = Schema(versionedSchema: SongbirdSchemaV2.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let first = Track(path: "/Music/one.flac", title: "One")
        let second = Track(path: "/Music/two.flac", title: "Two")
        first.checksum = "same"
        second.checksum = "same"
        context.insert(first)
        context.insert(second)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Track>()), 2)
    }

    func testCurrentStoreSnapshotMigrationWhenProvided() throws {
        guard let fixture = ProcessInfo.processInfo.environment["SONGBIRD_V1_STORE_FIXTURE"],
              !fixture.isEmpty else {
            throw XCTSkip("Set SONGBIRD_V1_STORE_FIXTURE to rehearse a real library migration.")
        }
        let storeURL = URL(fileURLWithPath: fixture)
        let schema = Schema(versionedSchema: SongbirdSchemaV2.self)
        let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: SongbirdMigrationPlan.self,
            configurations: config
        )
        let context = ModelContext(container)
        let tracks = try context.fetch(FetchDescriptor<Track>())
        XCTAssertFalse(tracks.isEmpty)
        XCTAssertEqual(Set(tracks.map(\.path)).count, tracks.count)
    }

    @MainActor
    func testCurrentStoreSnapshotCompatibilityWhenProvided() async throws {
        guard let fixture = ProcessInfo.processInfo.environment["SONGBIRD_STORE_FIXTURE"],
              !fixture.isEmpty else {
            throw XCTSkip("Set SONGBIRD_STORE_FIXTURE to rehearse opening a current library snapshot.")
        }

        let sourceURL = URL(fileURLWithPath: fixture)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-store-compatibility-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appendingPathComponent("library.store")

        for source in MediaLibraryStore.storeSidecars(for: sourceURL)
            where FileManager.default.fileExists(atPath: source.path) {
            let suffix = String(source.path.dropFirst(sourceURL.path.count))
            try FileManager.default.copyItem(
                at: source,
                to: URL(fileURLWithPath: storeURL.path + suffix)
            )
        }

        let schema = Schema(versionedSchema: SongbirdSchemaV3.self)
        let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let opened = MediaLibrary.openContainer(schema: schema, configuration: config)

        XCTAssertNil(opened.error)
        XCTAssertGreaterThan(
            try opened.container.mainContext.fetchCount(FetchDescriptor<Track>()),
            0
        )

        let snapshots = LibrarySnapshotStore(
            modelContainer: opened.container,
            startsImmediately: false
        )
        let clock = ContinuousClock()
        let snapshotStart = clock.now
        await snapshots.refresh()
        let snapshotDuration = snapshotStart.duration(to: clock.now)
        let albums = LibraryAlbumProjectionStore()
        let albumStart = clock.now
        await albums.update(from: snapshots.snapshot)
        let albumDuration = albumStart.duration(to: clock.now)
        let tableStart = clock.now
        _ = try await TrackTableProjectionWorker().project(
            snapshot: snapshots.snapshot,
            request: TrackTableRequest(collection: .allTracks),
            albumGroups: albums.groups
        )
        let tableDuration = tableStart.duration(to: clock.now)
        print(
            "Production library timings — snapshot: \(snapshotDuration), "
                + "albums: \(albumDuration), table: \(tableDuration)"
        )
        XCTAssertLessThan(snapshotDuration, .seconds(5))
        XCTAssertLessThan(albumDuration, .seconds(5))
        XCTAssertLessThan(tableDuration, .seconds(1))
    }

    func testOverlappingImportsProduceOneTrackForAPath() async throws {
        let schema = Schema(versionedSchema: SongbirdSchemaV2.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-overlap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/tone-44100-mono-16.wav")
        try FileManager.default.copyItem(
            at: fixture,
            to: folder.appendingPathComponent("song.wav")
        )

        async let first = LibraryImportPipeline.run(
            roots: [folder],
            container: container
        ) { _, _ in }
        async let second = LibraryImportPipeline.run(
            roots: [folder],
            container: container
        ) { _, _ in }
        _ = await (first, second)

        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Track>()), 1)
    }

    private func seedV1Store(
        at url: URL,
        path: String,
        oldDate: Date,
        newDate: Date,
        lastPlayed: Date
    ) throws {
        let schema = Schema(versionedSchema: SongbirdSchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let old = SongbirdSchemaV1.Track(path: path)
        old.title = "Old Metadata"
        old.dateAdded = oldDate
        old.dateModified = oldDate
        old.rating = 5
        old.playCount = 3

        let newer = SongbirdSchemaV1.Track(path: path)
        newer.title = "Newest Metadata"
        newer.dateAdded = newDate
        newer.dateModified = newDate
        newer.playCount = 42
        newer.lastPlayed = lastPlayed

        let playlist = SongbirdSchemaV1.Playlist(name: "Favorites")
        playlist.tracks = [old, newer]
        context.insert(old)
        context.insert(newer)
        context.insert(playlist)
        try context.save()
    }
}
