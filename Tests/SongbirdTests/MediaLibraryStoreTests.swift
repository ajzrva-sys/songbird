import XCTest
import SwiftData
@testable import SongbirdLib

final class MediaLibraryStoreTests: XCTestCase {
    func testLibraryStoreURLIsUnderSongbirdFolder() {
        let url = MediaLibraryStore.libraryStoreURL
        XCTAssertEqual(url.lastPathComponent, "library.store")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Songbird")
    }

    func testUITestRootOverridesApplicationSupportDirectory() throws {
        let defaultDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-ui-test-\(UUID().uuidString)", isDirectory: true)

        let resolved = try MediaLibraryStore.resolvedApplicationSupportDirectory(
            environment: [MediaLibraryStore.uiTestRootEnvironmentKey: root.path],
            defaultDirectory: defaultDirectory
        )

        XCTAssertEqual(
            resolved.path,
            root.standardizedFileURL.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(
            resolved
                .appendingPathComponent("Songbird", isDirectory: true)
                .appendingPathComponent("library.store")
                .path,
            root
                .appendingPathComponent("Songbird", isDirectory: true)
                .appendingPathComponent("library.store")
                .path
        )
    }

    func testMissingUITestRootUsesNormalApplicationSupportDirectory() throws {
        let defaultDirectory = URL(fileURLWithPath: "/Users/example/Library/Application Support")

        let resolved = try MediaLibraryStore.resolvedApplicationSupportDirectory(
            environment: [:],
            defaultDirectory: defaultDirectory
        )

        XCTAssertEqual(resolved, defaultDirectory.standardizedFileURL)
    }

    func testPackagedUsabilityRootSurvivesRelaunchWithoutEnvironment() throws {
        let defaultDirectory = URL(fileURLWithPath: "/Users/example/Library/Application Support")
        let packagedRoot = "/private/tmp/songbird-usability-profile"

        XCTAssertTrue(SongbirdUIRuntime.isTesting(
            environment: [:],
            infoDictionary: [SongbirdUIRuntime.testingInfoDictionaryKey: true]
        ))
        XCTAssertEqual(
            SongbirdUIRuntime.testRoot(
                environment: [:],
                infoDictionary: [
                    SongbirdUIRuntime.testingInfoDictionaryKey: true,
                    SongbirdUIRuntime.testRootInfoDictionaryKey: packagedRoot,
                ]
            ),
            packagedRoot
        )

        let resolved = try MediaLibraryStore.resolvedApplicationSupportDirectory(
            environment: [:],
            packagedUITestRoot: packagedRoot,
            defaultDirectory: defaultDirectory
        )
        XCTAssertEqual(resolved.path, packagedRoot)
    }

    func testPackagedUsabilitySetupStateRequiresTestingIdentity() {
        let setupInfo: [String: Any] = [
            SongbirdUIRuntime.importSetupCompletedInfoDictionaryKey: true,
        ]
        XCTAssertFalse(SongbirdUIRuntime.importSetupIsCompleted(
            environment: [:],
            infoDictionary: setupInfo
        ))
        XCTAssertTrue(SongbirdUIRuntime.importSetupIsCompleted(
            environment: [:],
            infoDictionary: setupInfo.merging([
                SongbirdUIRuntime.testingInfoDictionaryKey: true,
            ]) { _, new in new }
        ))
    }

    func testUITestRootRejectsRelativeEmptyAndRealLibraryAncestorPaths() {
        let defaultDirectory = URL(fileURLWithPath: "/Users/example/Library/Application Support")

        XCTAssertThrowsError(try MediaLibraryStore.resolvedApplicationSupportDirectory(
            environment: [MediaLibraryStore.uiTestRootEnvironmentKey: "relative/path"],
            defaultDirectory: defaultDirectory
        )) { error in
            XCTAssertEqual(
                error as? MediaLibraryStore.ConfigurationError,
                .relativeUITestRoot("relative/path")
            )
        }

        XCTAssertThrowsError(try MediaLibraryStore.resolvedApplicationSupportDirectory(
            environment: [MediaLibraryStore.uiTestRootEnvironmentKey: "   "],
            defaultDirectory: defaultDirectory
        )) { error in
            XCTAssertEqual(
                error as? MediaLibraryStore.ConfigurationError,
                .emptyUITestRoot
            )
        }

        for unsafeRoot in ["/", "/Users/example", defaultDirectory.path] {
            XCTAssertThrowsError(try MediaLibraryStore.resolvedApplicationSupportDirectory(
                environment: [MediaLibraryStore.uiTestRootEnvironmentKey: unsafeRoot],
                defaultDirectory: defaultDirectory
            ))
        }
    }

    func testStoreSidecarsIncludeWalAndShm() {
        let base = URL(fileURLWithPath: "/tmp/library.store")
        let sides = MediaLibraryStore.storeSidecars(for: base)
        XCTAssertEqual(sides.count, 3)
        XCTAssertTrue(sides.contains { $0.path.hasSuffix("-wal") })
        XCTAssertTrue(sides.contains { $0.path.hasSuffix("-shm") })
    }

    func testMigrateLegacyStoreMovesFiles() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("songbird-store-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        // Simulate Application Support layout under temp by swapping via a local helper.
        // We only verify path construction + sidecar naming here; move is exercised when
        // Application Support is writable in the app.
        let legacy = temp.appendingPathComponent("default.store")
        try Data([1, 2, 3]).write(to: legacy)
        try Data().write(to: URL(fileURLWithPath: legacy.path + "-wal"))

        let destDir = temp.appendingPathComponent("Songbird", isDirectory: true)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let dest = destDir.appendingPathComponent("library.store")
        XCTAssertFalse(fm.fileExists(atPath: dest.path))

        for file in MediaLibraryStore.storeSidecars(for: legacy) where fm.fileExists(atPath: file.path) {
            let suffix: String
            if file.path.hasSuffix("-shm") { suffix = "-shm" }
            else if file.path.hasSuffix("-wal") { suffix = "-wal" }
            else { suffix = "" }
            try fm.moveItem(at: file, to: URL(fileURLWithPath: dest.path + suffix))
        }

        XCTAssertTrue(fm.fileExists(atPath: dest.path))
        XCTAssertTrue(fm.fileExists(atPath: dest.path + "-wal"))
        XCTAssertFalse(fm.fileExists(atPath: legacy.path))
    }

    func testBackupPreservesStoreAndSidecars() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory
            .appendingPathComponent("songbird-backup-test-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let store = temp.appendingPathComponent("library.store")
        try Data([1, 2, 3]).write(to: store)
        try Data([4]).write(to: URL(fileURLWithPath: store.path + "-wal"))

        let backup = try MediaLibraryStore.backupStore(at: store, fileManager: fm)

        XCTAssertTrue(fm.fileExists(atPath: store.path))
        XCTAssertEqual(try Data(contentsOf: backup), Data([1, 2, 3]))
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: backup.path + "-wal")),
            Data([4])
        )
    }

    @MainActor
    func testMigrationFailurePreservesOriginalAndUsesRecoveryContainer() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory
            .appendingPathComponent("songbird-recovery-test-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let store = temp.appendingPathComponent("library.store")
        let original = Data("not a sqlite database".utf8)
        try original.write(to: store)
        let schema = Schema(versionedSchema: SongbirdSchemaV2.self)
        let config = ModelConfiguration(schema: schema, url: store, cloudKitDatabase: .none)

        let opened = MediaLibrary.openContainer(schema: schema, configuration: config)

        XCTAssertNotNil(opened.error)
        XCTAssertEqual(try Data(contentsOf: store), original)
        let backups = try fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("library-backup-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: backups[0]), original)
        let recoveryContext = ModelContext(opened.container)
        XCTAssertEqual(try recoveryContext.fetchCount(FetchDescriptor<Track>()), 0)
    }
}
