import Foundation
import SwiftData
import Testing
@testable import SongbirdLib

@Suite("Folder-watch import lifecycle", .serialized)
struct LibraryFolderWatcherImportLifecycleTests {
    @Test("Only explicitly local existing folders are eligible for automatic watching")
    func automaticWatchingExcludesRemoteAndUnknownVolumes() {
        let local = "/Volumes/Local Music"
        let remote = "/Volumes/Network Music"
        let unknown = "/Volumes/Unknown Music"
        let missing = "/Volumes/Missing Music"

        let paths = LibraryFolderWatchPolicy.watchablePaths(
            [local, remote, unknown, missing],
            fileExists: { $0 != missing },
            volumeIsLocal: { url in
                switch url.path {
                case local: return true
                case remote: return false
                default: return nil
                }
            }
        )

        #expect(paths == [local])
    }

    @Test("Foundation identifies a local temporary folder as watchable")
    func localTemporaryFolderIsWatchable() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-local-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(LibraryFolderWatchPolicy.watchablePaths([folder.path]) == [folder.path])
    }

    @Test("Per-root configurations migrate, deduplicate, and fail closed for remote roots")
    @MainActor
    func configurationMigrationAndModes() throws {
        let suiteName = "songbird.folder-config.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("[\"/Music/Local\",\"/Music/Local\",\"/Volumes/Remote\"]", forKey: LibraryFolderWatcher.pathsKey)
        defaults.set(false, forKey: LibraryFolderWatcher.enabledKey)

        let migrated = LibraryFolderConfigurationStore.load(defaults: defaults)
        #expect(migrated.map(\.path) == ["/Music/Local", "/Volumes/Remote"])
        #expect(migrated.allSatisfy { $0.mode == .manualScanOnly })

        let updated = LibraryFolderConfigurationStore.append(
            paths: ["/Music/Local", "/Volumes/Remote"],
            preferredMode: .watching,
            defaults: defaults,
            fileExists: { _ in true },
            volumeIsLocal: { $0.path == "/Music/Local" }
        )
        #expect(updated.count == 2)
        #expect(updated.first(where: { $0.path == "/Music/Local" })?.mode == .watching)
        #expect(updated.first(where: { $0.path == "/Volumes/Remote" })?.mode == .manualScanOnly)
    }

    @Test("Disposable runtimes cannot start automatic folder watching")
    @MainActor
    func disposableRuntimeDisablesWatching() {
        #expect(LibraryFolderWatcher.automaticWatchingIsAllowed(
            environment: [SongbirdUIRuntime.testingEnvironmentKey: "1"],
            infoDictionary: [:]
        ) == false)
        #expect(LibraryFolderWatcher.automaticWatchingIsAllowed(
            environment: [:],
            infoDictionary: [SongbirdUIRuntime.testingInfoDictionaryKey: true]
        ) == false)
        #expect(LibraryFolderWatcher.automaticWatchingIsAllowed(
            environment: [:],
            infoDictionary: [:]
        ))
    }

    @Test("Shared folder setup scans only when requested and preserves resolved modes")
    @MainActor
    func sharedFolderSetupCoordinator() {
        var scans: [[URL]] = []
        var applyCount = 0
        let coordinator = LibraryFolderSetupCoordinator(
            appendConfigurations: { paths, _ in
                paths.map {
                    LibraryFolderConfiguration(
                        path: $0,
                        mode: $0.contains("Remote") ? .manualScanOnly : .watching
                    )
                }
            },
            applyWatching: { applyCount += 1 },
            startScan: { scans.append($0) },
            fileExists: { _ in true }
        )

        let local = URL(fileURLWithPath: "/Music/Local", isDirectory: true)
        let remote = URL(fileURLWithPath: "/Volumes/Remote", isDirectory: true)
        let scanned = coordinator.add([local, remote], scanImmediately: true)
        let unscanned = coordinator.add([local], scanImmediately: false)

        #expect(applyCount == 2)
        #expect(scans == [[local, remote]])
        #expect(scanned.scannedPaths == [local.path, remote.path])
        #expect(scanned.manualOnlyPaths == [remote.path])
        #expect(unscanned.scannedPaths.isEmpty)
    }

    @Test("Disposable folder selection stays beneath its validated root")
    @MainActor
    func disposableFolderSelectionIsContained() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-folder-picker-\(UUID().uuidString)", isDirectory: true)
        let candidate = root
            .appendingPathComponent("FolderSelections", isDirectory: true)
            .appendingPathComponent("AddAndScan", isDirectory: true)
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let provider = DisposableLibraryFolderSelectionProvider(root: root)
        var selected: [URL] = []
        provider.selectFolders(
            for: .addAndScan,
            allowsMultipleSelection: true,
            initialDirectory: nil
        ) { selected = $0 }

        #expect(selected == [candidate.standardizedFileURL])
    }

    @Test("Removing the final watched folder does not restore the legacy path")
    @MainActor
    func removingFinalFolderClearsLegacyPath() {
        let defaults = UserDefaults.standard
        let previousPaths = defaults.object(forKey: LibraryFolderWatcher.pathsKey)
        let previousLegacyPath = defaults.object(forKey: LibraryFolderWatcher.pathKey)
        defer {
            if let previousPaths {
                defaults.set(previousPaths, forKey: LibraryFolderWatcher.pathsKey)
            } else {
                defaults.removeObject(forKey: LibraryFolderWatcher.pathsKey)
            }
            if let previousLegacyPath {
                defaults.set(previousLegacyPath, forKey: LibraryFolderWatcher.pathKey)
            } else {
                defaults.removeObject(forKey: LibraryFolderWatcher.pathKey)
            }
        }

        defaults.set("/Volumes/Legacy Music", forKey: LibraryFolderWatcher.pathKey)
        _ = LibraryFolderWatcher.encodePaths([])

        #expect(LibraryFolderWatcher.migrateLegacyPathIfNeeded() == false)
        #expect(LibraryFolderWatcher.folderPaths.isEmpty)
    }

    @Test("Folder-watch root notifications do not rescan the whole library")
    func watchedRootEventsAreIgnored() {
        let root = "/Music/Library"
        let newAlbum = "/Music/Library/New Album"
        let changedTrack = "/Music/Library/Existing Album/Track.flac"

        let paths = LibraryFolderEventFilter.importablePaths(
            [root, newAlbum, changedTrack],
            watchedRoots: [root]
        )

        #expect(paths == [newAlbum, changedTrack])
    }

    @Test("Events arriving during an import coalesce into one following cycle")
    func pendingEventsRunAfterCurrentImport() {
        // Given
        var cycle = LibraryFolderImportCycle()

        // When / Then
        let beganFirst = cycle.request()
        #expect(beganFirst)
        #expect(cycle.isRunning)
        let beganOverlapping = cycle.request()
        #expect(beganOverlapping == false)
        #expect(cycle.hasPendingRequest)
        let beganThird = cycle.request()
        #expect(beganThird == false)
        let beganQueued = cycle.completeAndBeginNextIfNeeded()
        #expect(beganQueued)
        #expect(cycle.isRunning)
        #expect(cycle.hasPendingRequest == false)
        let beganAfterCompletion = cycle.completeAndBeginNextIfNeeded()
        #expect(beganAfterCompletion == false)
        #expect(cycle.isRunning == false)
    }

    @Test("Cancelling a folder-watch cycle discards pending replacement work")
    func cancellationDiscardsPendingWork() {
        // Given
        var cycle = LibraryFolderImportCycle()
        let beganFirst = cycle.request()
        let beganOverlapping = cycle.request()
        #expect(beganFirst)
        #expect(beganOverlapping == false)

        // When
        cycle.cancel()

        // Then
        #expect(cycle.isRunning == false)
        #expect(cycle.hasPendingRequest == false)
        let beganAfterCancellation = cycle.completeAndBeginNextIfNeeded()
        #expect(beganAfterCancellation == false)
    }

    @Test("Concurrent imports preserve one track per discovered path")
    func concurrentImportsPreserveUniquePaths() async throws {
        // Given
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-overlapping-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/tone-44100-mono-16.wav")
        let expectedCount = 24
        for index in 0..<expectedCount {
            try FileManager.default.copyItem(
                at: fixture,
                to: folder.appendingPathComponent("track-\(index).wav")
            )
        }

        // When
        async let first = LibraryImportPipeline.run(
            roots: [folder],
            container: container,
            progress: { _, _ in }
        )
        async let second = LibraryImportPipeline.run(
            roots: [folder],
            container: container,
            progress: { _, _ in }
        )
        let results = await [first, second]

        // Then
        let context = ModelContext(container)
        let storedCount = try context.fetchCount(FetchDescriptor<Track>())
        #expect(results.allSatisfy { $0.failureMessage == nil })
        #expect(results.map(\.added).reduce(0, +) == expectedCount)
        #expect(storedCount == expectedCount)
    }
}
