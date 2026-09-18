import Foundation
import SwiftData
import XCTest
@testable import SongbirdLib

private actor ResetImportProgressGate {
    private var didStart = false
    private var continuation: CheckedContinuation<Void, Never>?

    var hasStarted: Bool { didStart }

    func pauseOnce() async {
        guard didStart == false else { return }
        didStart = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor ResetCompletionFlag {
    private(set) var value = false

    func markComplete() {
        value = true
    }
}

@MainActor
final class LibraryResetServiceTests: XCTestCase {
    func testResetClearsCatalogAndExclusionsWithoutDeletingFilesOrPreferences() async throws {
        let suiteName = "songbird.library-reset-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let exclusions = LibraryImportExclusionStore(suiteName: suiteName)
        let container = try makeContainer()
        let audio = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-reset-audio-\(UUID().uuidString).wav")
        let originalData = Data("audio remains outside the library store".utf8)
        try originalData.write(to: audio)
        defer { try? FileManager.default.removeItem(at: audio) }

        let context = container.mainContext
        let track = Track(path: audio.path, title: "Keep the File", artist: "Artist", album: "Album")
        let album = Album(title: "Album", artist: "Artist")
        let artist = Artist(name: "Artist")
        let personalPlaylist = Playlist(name: "Personal Mix")
        let legacyPersonalPlaylist = Playlist(name: "Legacy Personal Mix", systemKey: "")
        let systemPlaylist = Playlist(
            name: "Recently Played",
            smart: true,
            systemKey: DefaultSmartPlaylists.recentlyPlayedKey
        )
        track.albumRelation = album
        track.artistRelation = artist
        personalPlaylist.tracks = [track]
        systemPlaylist.tracks = [track]
        context.insert(track)
        context.insert(album)
        context.insert(artist)
        context.insert(personalPlaylist)
        context.insert(legacyPersonalPlaylist)
        context.insert(systemPlaylist)
        context.insert(AlbumFavorite(albumID: album.id))
        try context.save()

        exclusions.exclude(paths: [audio.path])
        defaults.set("preserved folders", forKey: "test.libraryFolders")
        defaults.set(true, forKey: "test.watchEnabled")

        let result = try await LibraryResetService(
            modelContainer: container,
            importExclusions: exclusions
        ).reset()

        XCTAssertEqual(result, LibraryResetResult(
            tracks: 1,
            albums: 1,
            artists: 1,
            albumFavorites: 1,
            personalPlaylists: 2
        ))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Track>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Album>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Artist>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AlbumFavorite>()), 0)
        let remainingPlaylists = try context.fetch(FetchDescriptor<Playlist>())
        XCTAssertEqual(remainingPlaylists.map(\.systemKey), [DefaultSmartPlaylists.recentlyPlayedKey])
        XCTAssertTrue(remainingPlaylists[0].tracks.isEmpty)
        XCTAssertFalse(exclusions.contains(audio.path))
        XCTAssertEqual(try Data(contentsOf: audio), originalData)
        XCTAssertEqual(defaults.string(forKey: "test.libraryFolders"), "preserved folders")
        XCTAssertTrue(defaults.bool(forKey: "test.watchEnabled"))
    }

    func testResetIsIdempotentAndAllowsDeliberateReimport() async throws {
        let suiteName = "songbird.library-reset-reimport-tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let exclusions = LibraryImportExclusionStore(suiteName: suiteName)
        let container = try makeContainer()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-reset-reimport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let audio = folder.appendingPathComponent("restored.wav")
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/tone-44100-mono-16.wav")
        try FileManager.default.copyItem(at: fixture, to: audio)

        let initialImport = await LibraryImportPipeline.runDeliberate(
            roots: [folder],
            container: container,
            exclusionStore: exclusions
        ) { _, _ in }
        XCTAssertEqual(initialImport.added, 1)
        exclusions.exclude(paths: [audio.path])

        let service = LibraryResetService(
            modelContainer: container,
            importExclusions: exclusions
        )
        let firstReset = try await service.reset()
        let secondReset = try await service.reset()

        XCTAssertEqual(firstReset.tracks, 1)
        XCTAssertEqual(secondReset.tracks, 0)
        XCTAssertFalse(exclusions.contains(audio.path))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Track>()), 0)

        let reimport = await LibraryImportPipeline.runDeliberate(
            roots: [folder],
            container: container,
            exclusionStore: exclusions
        ) { _, _ in }
        XCTAssertEqual(reimport.added, 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Track>()), 1)
        XCTAssertFalse(exclusions.contains(audio.path))
    }

    func testResetWaitsForAnAdmittedImportThenRemovesItsCommittedTracks() async throws {
        let suiteName = "songbird.library-reset-serialization-tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let exclusions = LibraryImportExclusionStore(suiteName: suiteName)
        let container = try makeContainer()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-reset-serialization-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let audio = folder.appendingPathComponent("serialized.wav")
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/tone-44100-mono-16.wav")
        try FileManager.default.copyItem(at: fixture, to: audio)

        let progressGate = ResetImportProgressGate()
        let importTask = Task {
            await LibraryImportPipeline.runDeliberate(
                roots: [folder],
                container: container,
                exclusionStore: exclusions
            ) { processed, _ in
                if processed == 0 { await progressGate.pauseOnce() }
            }
        }
        for _ in 0..<100 where await progressGate.hasStarted == false {
            try await Task.sleep(for: .milliseconds(10))
        }
        let importDidStart = await progressGate.hasStarted
        XCTAssertTrue(importDidStart)

        let completion = ResetCompletionFlag()
        let resetTask = Task {
            let result = try await LibraryResetService(
                modelContainer: container,
                importExclusions: exclusions
            ).reset()
            await completion.markComplete()
            return result
        }
        try await Task.sleep(for: .milliseconds(20))
        let resetCompletedWhileImportWasPaused = await completion.value
        XCTAssertFalse(resetCompletedWhileImportWasPaused)

        await progressGate.release()
        let importResult = await importTask.value
        let resetResult = try await resetTask.value

        XCTAssertEqual(importResult.added, 1)
        XCTAssertEqual(resetResult.tracks, 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Track>()), 0)
    }

    func testResetPreparationStopsPlaybackAndClearsQueueSelectionAndDetailNavigation() throws {
        let container = try makeContainer()
        let track = Track(path: "/Music/Queued.wav", title: "Queued")
        container.mainContext.insert(track)
        try container.mainContext.save()
        let queue = PlaybackQueue()
        _ = queue.replace(with: [track])
        queue.enqueue([track])
        let navigation = LibraryNavigationCoordinator(selectedRoot: .albums, restoresPersistedState: false)
        navigation.showAlbum(albumID: UUID())
        let selection = LibrarySelectionState()
        selection.updateLibrarySelection(trackID: track.id, track: track)
        var didStopPlayback = false

        LibraryResetPresentation.prepare(
            queue: queue,
            navigation: navigation,
            selection: selection,
            stopPlayback: { didStopPlayback = true }
        )

        XCTAssertTrue(didStopPlayback)
        XCTAssertNil(queue.currentEntry)
        XCTAssertTrue(queue.upcomingEntries.isEmpty)
        XCTAssertTrue(queue.historyEntries.isEmpty)
        XCTAssertNil(selection.selectedTrack)
        XCTAssertNil(selection.selectedLibraryTrackID)
        XCTAssertEqual(navigation.selectedRoot, .allTracks)
        XCTAssertTrue(navigation.path.isEmpty)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self, AlbumFavorite.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
