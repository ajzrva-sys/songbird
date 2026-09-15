import AVFoundation
import Foundation
import SongbirdUsabilityFixtureSupport
import SwiftData
import XCTest
@testable import SongbirdLib

final class SongbirdUsabilityFixtureTests: XCTestCase {
    @MainActor
    func testStandardFixtureSeedsAndVerifiesDeterministicUsabilityStates() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-ui-test-fixture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let seeder = try SongbirdUsabilityFixtureSeeder(root: root)

        let manifest = try seeder.seed(profile: .standard)

        XCTAssertEqual(manifest.profile, .standard)
        XCTAssertEqual(manifest.schemaVersion, 2)
        XCTAssertEqual(manifest.generationSeed, SongbirdUsabilityFixtureSeeder.generationSeed)
        XCTAssertEqual(manifest.generatorRevision, SongbirdUsabilityFixtureSeeder.generatorRevision)
        XCTAssertEqual(manifest.trackCount, 14)
        XCTAssertEqual(manifest.albumCount, 5)
        XCTAssertEqual(manifest.playlistCount, 5)
        XCTAssertEqual(manifest.albums.filter(\.hasArtwork).count, 2)
        XCTAssertEqual(manifest.albums.filter(\.isFavorite).count, 1)
        XCTAssertEqual(manifest.tracks.filter(\.isFavorite).count, 2)
        XCTAssertEqual(manifest.tracks.filter { !$0.fileExists }.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.storePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: seeder.manifestURL.path))
        let playableTrackURL = try XCTUnwrap(
            manifest.tracks.first(where: \.fileExists).map { URL(fileURLWithPath: $0.path) }
        )
        let playableTrack = try AVAudioFile(forReading: playableTrackURL)
        let playableDuration = Double(playableTrack.length) / playableTrack.fileFormat.sampleRate
        XCTAssertEqual(
            playableDuration,
            SongbirdUsabilityFixtureSeeder.playbackFixtureDuration,
            accuracy: 0.001,
            "Usability audio must remain long enough to test play, pause, progress, and seeking."
        )
        XCTAssertEqual(try seeder.verify(), manifest)

        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let configuration = ModelConfiguration(
            schema: schema,
            url: seeder.storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: SongbirdMigrationPlan.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        let albums = try context.fetch(FetchDescriptor<Album>())
        let artists = try context.fetch(FetchDescriptor<Artist>())
        XCTAssertEqual(albums.reduce(0) { $0 + $1.tracks.count }, 14)
        XCTAssertGreaterThanOrEqual(artists.count, 6)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AlbumFavorite>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrackFavorite>()), 2)
        XCTAssertTrue(playlists.contains { $0.name == "Top-Rated Electronic" })
        XCTAssertFalse(playlists.contains { $0.name == "Electronic Favorites" })
        XCTAssertEqual(manifest.folders.count, 6)
        XCTAssertEqual(manifest.folders.filter(\.configured).count, 3)
        XCTAssertEqual(manifest.folders.filter(\.available).count, 5)
        XCTAssertEqual(
            Set(manifest.folders.flatMap(\.mediaFiles).map(\.sha256)).count,
            5,
            "Each disposable folder journey needs independently verifiable media bytes."
        )
        XCTAssertEqual(
            manifest.folders.first { $0.purpose == "configuredUnavailable" }?.intendedMode,
            .watching
        )
        XCTAssertFalse(
            manifest.folders.first { $0.purpose == "configuredUnavailable" }?.available ?? true
        )

        let defaultsSuite = "com.songbird.fixture-test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite) }
        try seeder.configureApplicationDefaults(
            bundleIdentifier: defaultsSuite,
            manifest: manifest
        )
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        let configurations = LibraryFolderConfigurationStore.load(defaults: defaults)
        XCTAssertEqual(configurations.count, 3)
        XCTAssertEqual(configurations.filter { $0.mode == .watching }.count, 2)
        XCTAssertEqual(configurations.filter { $0.mode == .manualScanOnly }.count, 1)
        XCTAssertTrue(defaults.bool(forKey: ImportSetupView.completedKey))
        let report = try seeder.stateReport(bundleIdentifier: defaultsSuite)
        XCTAssertEqual(report.tracks.count, 14)
        XCTAssertEqual(report.playlists.count, 5)
        XCTAssertEqual(report.folders.count, 3)
        XCTAssertEqual(report.media.count, 5)
        XCTAssertTrue(report.media.allSatisfy(\.fileExists))
        XCTAssertEqual(
            report.playlists.first { $0.name == "Morning Mix" }?.orderedTrackIDs.count,
            5
        )
    }

    @MainActor
    func testEmptyFixtureContainsOnlyDefaultSmartPlaylists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-ui-test-empty-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest = try SongbirdUsabilityFixtureSeeder(root: root).seed(profile: .empty)

        XCTAssertEqual(manifest.trackCount, 0)
        XCTAssertEqual(manifest.albumCount, 0)
        XCTAssertEqual(manifest.playlistCount, 3)
        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: manifest.storePath))
        let container = try ModelContainer(
            for: schema,
            migrationPlan: SongbirdMigrationPlan.self,
            configurations: configuration
        )
        let favorites = try XCTUnwrap(
            ModelContext(container).fetch(FetchDescriptor<Playlist>()).first {
                $0.systemKey == DefaultSmartPlaylists.topRatedKey
            }
        )
        let rules = try XCTUnwrap(SmartPlaylistRuleSet.decode(from: favorites.smartPlaylistRules))
        XCTAssertEqual(rules.conditions.first?.field, .favorite)
        XCTAssertEqual(rules.conditions.first?.op, .isSet)
    }

    @MainActor
    func testHealthFixtureKeepsStandardBaselineSeparateAndIncludesAlbumEvidenceCases() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-ui-test-health-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let seeder = try SongbirdUsabilityFixtureSeeder(root: root)
        let manifest = try seeder.seed(profile: .health)

        XCTAssertEqual(manifest.profile, .health)
        XCTAssertEqual(manifest.trackCount, 12)
        XCTAssertEqual(manifest.albumCount, 5)
        XCTAssertEqual(manifest.tracks.filter { $0.album == "Unknown Album" }.count, 6)
        XCTAssertTrue(manifest.tracks.contains { $0.path.contains("Box Set/CD 1") })
        XCTAssertTrue(manifest.tracks.contains { $0.path.contains("Box Set/CD 2") })
        XCTAssertTrue(manifest.tracks.contains {
            $0.title == "Relocatable Recording" && $0.fileExists == false
        })
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("HealthRelocationRoot/Unique/relocatable.wav").path
        ))
        XCTAssertEqual(try seeder.verify(), manifest)
    }

    @MainActor
    func testSeederRequiresExplicitRootAndBoundsLargeFixtures() throws {
        XCTAssertThrowsError(try SongbirdUsabilityFixtureSeeder.fromEnvironment([:])) { error in
            XCTAssertEqual(
                error as? SongbirdUsabilityFixtureError,
                .missingRootEnvironment
            )
        }
        XCTAssertThrowsError(try SongbirdUsabilityFixtureSeeder.fromEnvironment([
            MediaLibraryStore.uiTestRootEnvironmentKey: "relative/path",
        ])) { error in
            XCTAssertEqual(
                error as? MediaLibraryStore.ConfigurationError,
                .relativeUITestRoot("relative/path")
            )
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-ui-test-bounds-\(UUID().uuidString)")
        let seeder = try SongbirdUsabilityFixtureSeeder(root: root)
        XCTAssertThrowsError(try seeder.seed(profile: .large, largeTrackCount: 0)) { error in
            XCTAssertEqual(
                error as? SongbirdUsabilityFixtureError,
                .invalidLargeTrackCount(0)
            )
        }
    }

    @MainActor
    func testLargeFixtureUsesOneAlbumPerTenTracksUpToProfilingScale() throws {
        XCTAssertEqual(SongbirdUsabilityFixtureSeeder.defaultLargeTrackCount, 10_000)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-ui-test-large-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest = try SongbirdUsabilityFixtureSeeder(root: root).seed(
            profile: .large,
            largeTrackCount: 100
        )

        XCTAssertEqual(manifest.trackCount, 100)
        XCTAssertEqual(manifest.albumCount, 10)
        XCTAssertEqual(try SongbirdUsabilityFixtureSeeder(root: root).verify(), manifest)
    }
}
