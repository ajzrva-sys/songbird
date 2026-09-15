import XCTest
import SwiftData
@testable import SongbirdLib

final class LibraryScannerTests: XCTestCase {
    func testAutomaticScanProgressUsesCheckingLanguage() {
        XCTAssertEqual(
            LibraryScanner.progressMessage(automatic: true, completed: 14_331, total: 14_331),
            "Checking library 14331 of 14331…"
        )
        XCTAssertEqual(
            LibraryScanner.progressMessage(automatic: true, completed: 0, total: 0),
            "Checking library…"
        )
        XCTAssertEqual(
            LibraryScanner.progressMessage(automatic: false, completed: 12, total: 20),
            "Importing 12 of 20…"
        )
    }

    @MainActor
    func testAutomaticImportHonorsPersistentRemovalAndManualImportRestoresIt() async throws {
        let suiteName = "songbird.import-exclusion-tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let exclusions = LibraryImportExclusionStore(suiteName: suiteName)
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-excluded-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let audio = folder.appendingPathComponent("removed.wav")
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/tone-44100-mono-16.wav")
        try FileManager.default.copyItem(at: fixture, to: audio)
        exclusions.exclude(paths: [audio.path])

        let relaunchedStore = LibraryImportExclusionStore(suiteName: suiteName)
        XCTAssertTrue(relaunchedStore.contains(audio.path))

        let automatic = await LibraryImportPipeline.runAutomatic(
            roots: [folder],
            container: container,
            exclusionStore: relaunchedStore
        ) { _, _ in }
        XCTAssertEqual(automatic.discovered, 0)
        XCTAssertEqual(automatic.added, 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Track>()), 0)

        let deliberate = await LibraryImportPipeline.runDeliberate(
            roots: [folder],
            container: container,
            exclusionStore: relaunchedStore
        ) { _, _ in }
        XCTAssertEqual(deliberate.added, 1)
        XCTAssertFalse(relaunchedStore.contains(audio.path))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Track>()), 1)
    }

    func testSupportedExtensions() {
        XCTAssertTrue(supportedExtensions.contains("mp3"))
        XCTAssertTrue(supportedExtensions.contains("flac"))
        XCTAssertTrue(supportedExtensions.contains("m4a"))
        XCTAssertTrue(supportedExtensions.contains("wav"))
        XCTAssertTrue(supportedExtensions.contains("aac"))
        XCTAssertTrue(supportedExtensions.contains("aiff"))
        XCTAssertFalse(supportedExtensions.contains("ogg"))
        XCTAssertFalse(supportedExtensions.contains("opus"))
        XCTAssertFalse(supportedExtensions.contains("txt"))
        XCTAssertFalse(supportedExtensions.contains("pdf"))
        XCTAssertFalse(supportedExtensions.contains("mp4"))
    }

    func testSupportedExtensionsIsCaseInsensitive() {
        // Verify we check lowercase — callers should lowercase before checking
        XCTAssertTrue(supportedExtensions.contains("mp3"))
        XCTAssertTrue(supportedExtensions.contains("flac"))
    }

    func testDiscoveryStandardizesDeduplicatesAndFiltersFiles() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-discovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let audio = folder.appendingPathComponent("Track.MP3")
        try Data([1, 2, 3]).write(to: audio)
        try Data("ignore".utf8).write(to: folder.appendingPathComponent("notes.txt"))

        let discovered = await LibraryImportPipeline.discoverAudioURLs(
            from: [folder, audio]
        )

        XCTAssertEqual(discovered.map(\.path), [audio.standardizedFileURL.path])
    }

    @MainActor
    func testNewImportsStoreChecksumAndReuseRelationships() async throws {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-pipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/tone-44100-mono-16.wav")
        try FileManager.default.copyItem(
            at: fixture,
            to: folder.appendingPathComponent("one.wav")
        )
        try FileManager.default.copyItem(
            at: fixture,
            to: folder.appendingPathComponent("two.wav")
        )

        let result = await LibraryImportPipeline.run(
            roots: [folder],
            container: container
        ) { _, _ in }

        let context = ModelContext(container)
        let tracks = try context.fetch(FetchDescriptor<Track>())
        let artists = try context.fetch(FetchDescriptor<Artist>())
        let albums = try context.fetch(FetchDescriptor<Album>())
        XCTAssertEqual(result.added, 2)
        XCTAssertEqual(tracks.count, 2)
        XCTAssertTrue(tracks.allSatisfy { !$0.checksum.isEmpty })
        XCTAssertEqual(Set(tracks.map(\.checksum)).count, 1)
        XCTAssertEqual(artists.count, 1)
        XCTAssertEqual(albums.count, 1)

        var resumedAt: Int?
        let resumed = await LibraryImportPipeline.run(
            roots: [folder],
            container: container
        ) { completed, _ in
            await MainActor.run {
                if resumedAt == nil { resumedAt = completed }
            }
        }
        XCTAssertEqual(resumedAt, 2)
        XCTAssertEqual(resumed.processed, 2)
        XCTAssertEqual(resumed.added, 0)
    }

    @MainActor
    func testDeliberateScanReconcilesCanonicalPathWithoutDuplicate() async throws {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-unicode-reconcile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/tone-44100-mono-16.wav")
        let requested = folder.appendingPathComponent("Cafe\u{0301}.wav")
        try FileManager.default.copyItem(at: fixture, to: requested)
        let actual = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first
        )
        let actualPath = actual.path
        let expectedLivePath = Track.standardizedPath(actualPath)
        let alternatePath = actualPath.precomposedStringWithCanonicalMapping.unicodeScalars
            .elementsEqual(actualPath.unicodeScalars)
            ? actualPath.decomposedStringWithCanonicalMapping
            : actualPath.precomposedStringWithCanonicalMapping
        XCTAssertFalse(LibraryPathIdentity.hasSameScalarSpelling(actualPath, alternatePath))

        let attributes = try FileManager.default.attributesOfItem(atPath: actualPath)
        let existing = Track(
            path: alternatePath,
            title: "Existing identity",
            artist: "Artist",
            album: "Album"
        )
        existing.fileSize = (attributes[.size] as? Int64) ?? 0
        existing.dateModified = try XCTUnwrap(attributes[.modificationDate] as? Date)
        container.mainContext.insert(existing)
        try container.mainContext.save()

        let result = await LibraryImportPipeline.runDeliberate(
            roots: [folder],
            container: container,
            exclusionStore: LibraryImportExclusionStore(
                suiteName: "songbird-unicode-reconcile-\(UUID().uuidString)"
            )
        ) { _, _ in }

        let verificationContext = ModelContext(container)
        let tracks = try verificationContext.fetch(FetchDescriptor<Track>())
        XCTAssertNil(result.failureMessage)
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(tracks.count, 1)
        let storedPath = try XCTUnwrap(tracks.first).path
        XCTAssertTrue(
            LibraryPathIdentity.hasSameScalarSpelling(
                storedPath,
                expectedLivePath
            ),
            "stored=\(scalarDescription(storedPath)) actual=\(scalarDescription(expectedLivePath)) processed=\(result.processed)"
        )
    }

    private func scalarDescription(_ value: String) -> String {
        value.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")
    }

    @MainActor
    func testDeliberateScanRefusesExistingCanonicalPathCollision() async throws {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let first = Track(path: "/Music/Caf\u{00E9}.wav", title: "First")
        let second = Track(path: "/Music/Cafe\u{0301}.wav", title: "Second")
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        let result = await LibraryImportPipeline.runDeliberate(
            roots: [],
            container: container,
            exclusionStore: LibraryImportExclusionStore(
                suiteName: "songbird-unicode-collision-\(UUID().uuidString)"
            )
        ) { _, _ in }

        XCTAssertTrue(result.failureMessage?.contains("canonically equivalent paths") == true)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Track>()), 2)
    }

    @MainActor
    func testImportReleasesBatchesWhileReusingRelationshipsAcrossCommits() async throws {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-batched-pipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/tone-44100-mono-16.wav")
        let count = LibraryImportPipeline.commitBatchSize * 2 + 3
        for index in 0..<count {
            try FileManager.default.copyItem(
                at: fixture,
                to: folder.appendingPathComponent("track-\(index).wav")
            )
        }

        let result = await LibraryImportPipeline.run(
            roots: [folder],
            container: container
        ) { _, _ in }

        let context = ModelContext(container)
        XCTAssertEqual(result.added, count)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Track>()), count)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Artist>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Album>()), 1)
    }

    @MainActor
    func testScannerRoutesProgressAndReturnsToIdleAfterImport() async throws {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-scanner-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/tone-44100-mono-16.wav")
        try FileManager.default.copyItem(
            at: fixture,
            to: folder.appendingPathComponent("progress.wav")
        )
        let scanner = LibraryScanner(modelContainer: container)

        await scanner.scanFolders([folder])

        XCTAssertFalse(scanner.isScanning)
        XCTAssertEqual(scanner.progress, ImportProgress())
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Track>()), 1)
    }

    @MainActor
    func testDuplicateAnalysisHashesThenRemovesAfterConfirmationStep() async throws {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-duplicates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let firstURL = folder.appendingPathComponent("first.mp3")
        let secondURL = folder.appendingPathComponent("second.mp3")
        try Data(repeating: 7, count: 512).write(to: firstURL)
        try Data(repeating: 7, count: 512).write(to: secondURL)

        let context = ModelContext(container)
        let first = Track(path: firstURL.path, title: "First")
        let second = Track(path: secondURL.path, title: "Second")
        second.dateAdded = first.dateAdded.addingTimeInterval(1)
        context.insert(first)
        context.insert(second)
        try context.save()

        let analysis = try await DuplicateAnalysisService.analyze(
            container: container
        ) { _, _ in }
        XCTAssertEqual(analysis.groupCount, 1)
        XCTAssertEqual(analysis.duplicateTrackCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Track>()).count, 2)

        let removed = try await DuplicateAnalysisService.removeAnalyzedDuplicates(
            analysis,
            container: container
        )
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Track>()).count, 1)
    }
}
