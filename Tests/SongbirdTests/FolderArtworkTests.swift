import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import SongbirdLib

func folderArtworkFixture(red: CGFloat = 0.15) throws -> Data {
    let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(red: red, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    let data = NSMutableData()
    let output = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(output, try XCTUnwrap(context.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(output))
    return data as Data
}

@MainActor
final class FolderArtworkTests: XCTestCase {
    private var directory: URL!
    private var container: ModelContainer!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("folder-artwork-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testCommonNamesAndCaseAreRecognized() throws {
        let art = try folderArtworkFixture()
        for name in ["folder.jpg", "FoLdEr.JpEg", "front.png", "album.png", "artwork.png"] {
            let url = directory.appendingPathComponent(name)
            try art.write(to: url)
            XCTAssertEqual(TrackImporter.folderArtworkData(for: directory.appendingPathComponent("音楽.flac")), art, name)
            try FileManager.default.removeItem(at: url)
        }
    }

    func testCoverPriorityAndInvalidCandidateFallback() throws {
        let cover = try folderArtworkFixture(red: 0.9)
        let folder = try folderArtworkFixture()
        let audio = directory.appendingPathComponent("track.flac")
        let coverURL = directory.appendingPathComponent("cover.jpg")
        try folder.write(to: directory.appendingPathComponent("folder.jpg"))
        try cover.write(to: coverURL)
        XCTAssertEqual(TrackImporter.folderArtworkData(for: audio), cover)
        try Data("corrupt image".utf8).write(to: coverURL)
        XCTAssertEqual(TrackImporter.folderArtworkData(for: audio), folder)
        try FileManager.default.removeItem(at: coverURL)
        try FileManager.default.createDirectory(at: coverURL, withIntermediateDirectories: false)
        XCTAssertEqual(TrackImporter.folderArtworkData(for: audio), folder)
    }

    func testUnchangedRescanFindsFolderArtWithoutOverwritingMetadataOrSavedArt() async throws {
        let track = try makeTrack()
        let art = try folderArtworkFixture()
        try art.write(to: directory.appendingPathComponent("folder.jpg"))
        let initialChecksum = track.checksum
        let result = await LibraryImportPipeline.run(roots: [directory], container: container, progress: { _, _ in })
        XCTAssertNil(result.failureMessage)
        XCTAssertEqual(result.added, 0)
        let read = ModelContext(container)
        let saved = try XCTUnwrap(read.fetch(FetchDescriptor<Track>()).first)
        XCTAssertEqual(saved.resolvedArtworkData, art)
        XCTAssertEqual(saved.title, "User title")
        XCTAssertEqual(saved.year, 1997)
        XCTAssertEqual(saved.playCount, 17)
        XCTAssertEqual(saved.checksum, initialChecksum)
        try folderArtworkFixture(red: 0.9).write(to: directory.appendingPathComponent("cover.jpg"))
        let again = await LibraryImportPipeline.run(roots: [directory], container: container, progress: { _, _ in })
        XCTAssertNil(again.failureMessage)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Album>()).first?.artworkData, art)
    }

    func testSameContentWithChangedTimestampAlsoFindsArtwork() async throws {
        let track = try makeTrack()
        track.dateModified = .distantPast
        try container.mainContext.save()
        let art = try folderArtworkFixture()
        try art.write(to: directory.appendingPathComponent("folder.jpg"))
        let result = await LibraryImportPipeline.run(roots: [directory], container: container, progress: { _, _ in })
        XCTAssertNil(result.failureMessage)
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Track>()).first)
        XCTAssertEqual(saved.resolvedArtworkData, art)
        XCTAssertEqual(saved.title, "User title")
        XCTAssertEqual(saved.year, 1997)
    }

    func testArtworkOnlyRescanPreservesIncompleteMetadata() async throws {
        let track = try makeTrack()
        track.title = "track"
        track.artist = "Unknown Artist"
        try container.mainContext.save()
        let art = try folderArtworkFixture()
        try art.write(to: directory.appendingPathComponent("folder.jpg"))
        let result = await LibraryImportPipeline.run(roots: [directory], container: container, progress: { _, _ in })
        XCTAssertNil(result.failureMessage)
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Track>()).first)
        XCTAssertEqual(saved.resolvedArtworkData, art)
        XCTAssertEqual(saved.title, "track")
        XCTAssertEqual(saved.artist, "Unknown Artist")
        XCTAssertEqual(saved.year, 1997)
    }

    func testOpeningExistingAlbumDiscoversAndRetainsCoverAfterFileIsRemoved() async throws {
        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("library.store"))
        container = try ModelContainer(for: schema, configurations: [configuration])
        let track = try makeTrack()
        let id = try XCTUnwrap(track.albumRelation?.id)
        let art = try folderArtworkFixture()
        let url = directory.appendingPathComponent("folder.jpg")
        try art.write(to: url)
        let (actions, snapshots) = try await makeActions()
        XCTAssertNil(snapshots.snapshot.albumsByID[id]?.artworkReference)
        await actions.discoverFolderArtwork(albumIDs: [id])
        XCTAssertNotNil(snapshots.snapshot.albumsByID[id]?.artworkReference)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Album>()).first?.artworkData, art)
        XCTAssertFalse(actions.healthUndoAvailable)
        try FileManager.default.removeItem(at: url)
        await actions.discoverFolderArtwork(albumIDs: [id])
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Album>()).first?.artworkData, art)
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<Album>()).first?.artworkData, art)
        let service = ArtworkThumbnailService(modelContainer: reopened)
        let reference = try XCTUnwrap(snapshots.snapshot.albumsByID[id]?.artworkReference)
        let image = await service.image(for: reference, pointSize: CGSize(width: 160, height: 160))
        XCTAssertNotNil(image)
    }

    func testDiscoveryPreservesExistingArtworkUndo() async throws {
        let edited = try makeTrack(suffix: "edited")
        let discovered = try makeTrack(suffix: "discovered")
        let editedID = try XCTUnwrap(edited.albumRelation?.id)
        let discoveredID = try XCTUnwrap(discovered.albumRelation?.id)
        let art = try folderArtworkFixture()
        try art.write(to: directory.appendingPathComponent("folder.jpg"))
        let (actions, _) = try await makeActions()
        guard case .success = await actions.applyArtwork([
            LibraryArtworkChange(albumID: editedID, expectedArtworkDigest: nil,
                                 imageData: try folderArtworkFixture(red: 0.9))
        ]) else { return XCTFail("Initial artwork edit failed") }
        await actions.discoverFolderArtwork(albumIDs: [discoveredID])
        guard case .success = await actions.undoLatestHealthMutation() else {
            return XCTFail("Existing artwork Undo was lost")
        }
        let albums = try ModelContext(container).fetch(FetchDescriptor<Album>())
        XCTAssertNil(albums.first { $0.id == editedID }?.artworkData)
        XCTAssertEqual(albums.first { $0.id == discoveredID }?.artworkData, art)
    }

    func testNewImportUsesSiblingFolderArtwork() async throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Generated/tone-48000-stereo-24-alac.m4a")
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent("song.m4a"))
        let art = try folderArtworkFixture()
        try art.write(to: directory.appendingPathComponent("folder.jpg"))
        let result = await LibraryImportPipeline.run(roots: [directory], container: container, progress: { _, _ in })
        XCTAssertNil(result.failureMessage)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Album>()).first?.artworkData, art)
    }

    func testLateDiscoveryDoesNotOverwriteNewCoverOrChangedAlbumMembership() async throws {
        for changeCover in [true, false] {
            let track = try makeTrack(suffix: changeCover ? "cover" : "path")
            let id = try XCTUnwrap(track.albumRelation?.id)
            let art = try folderArtworkFixture()
            let chosen = try folderArtworkFixture(red: 0.9)
            let started = expectation(description: "Background folder read")
            let resume = DispatchSemaphore(value: 0)
            let (actions, _) = try await makeActions(loader: { _ in
                XCTAssertFalse(Thread.isMainThread)
                started.fulfill()
                guard resume.wait(timeout: .now() + 5) == .success else { return nil }
                return art
            })
            let task = Task { await actions.discoverFolderArtwork(albumIDs: [id]) }
            await fulfillment(of: [started], timeout: 3)
            if changeCover { track.albumRelation?.artworkData = chosen }
            else { track.path = directory.appendingPathComponent("moved.wav").path }
            try container.mainContext.save()
            resume.signal()
            await task.value
            let albums = try ModelContext(container).fetch(FetchDescriptor<Album>())
            XCTAssertEqual(albums.first { $0.id == id }?.artworkData, changeCover ? chosen : nil)
        }
    }

    func testCancellationDoesNotSaveLateArtwork() async throws {
        let track = try makeTrack()
        let id = try XCTUnwrap(track.albumRelation?.id)
        let art = try folderArtworkFixture()
        let started = expectation(description: "Background folder read")
        let resume = DispatchSemaphore(value: 0)
        let (actions, _) = try await makeActions(loader: { _ in
            started.fulfill()
            guard resume.wait(timeout: .now() + 5) == .success else { return nil }
            return art
        })
        let task = Task { await actions.discoverFolderArtwork(albumIDs: [id]) }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        resume.signal()
        await task.value
        XCTAssertNil(try ModelContext(container).fetch(FetchDescriptor<Album>()).first?.artworkData)
    }

    private func makeTrack(suffix: String = "track") throws -> Track {
        let url = directory.appendingPathComponent("\(suffix).wav")
        try Data("RIFF-invalid-audio-with-user-tags".utf8).write(to: url)
        let track = Track(path: url.path, title: "User title", artist: "User artist", album: "Album \(suffix)")
        track.year = 1997
        track.playCount = 17
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        track.fileSize = (attrs[.size] as? Int64) ?? 0
        track.dateModified = try XCTUnwrap(attrs[.modificationDate] as? Date)
        track.checksum = Track.contentChecksum(at: url.path)
        container.mainContext.insert(track)
        try TrackImporter.linkRelations(for: track, in: container.mainContext)
        try container.mainContext.save()
        return track
    }

    private func makeActions(loader: (@Sendable (URL) -> Data?)? = nil) async throws -> (LibraryItemActionHandler, LibrarySnapshotStore) {
        let snapshots = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await snapshots.refresh()
        let actions = LibraryItemActionHandler(modelContainer: container,
            playbackSession: PlaybackSession(backend: FolderArtworkTestBackend()), librarySnapshots: snapshots,
            navigation: LibraryNavigationCoordinator(restoresPersistedState: false), folderArtworkLoader: loader)
        return (actions, snapshots)
    }
}

@MainActor
private final class FolderArtworkTestBackend: PlayerBackend {
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var isPaused = false
    var volume: Double = 1
    var onTrackBegan: ((AudioSource?) -> Void)?
    var onTrackFinished: (() -> Void)?
    var onError: ((String) -> Void)?
    func prepare() throws {}
    func shutdown() {}
    func play(_ source: AudioSource, durationHint: TimeInterval) throws {}
    func pause() {}
    func resume() {}
    func stop() {}
    func seek(to time: TimeInterval) {}
    func setNextSource(_ source: AudioSource?, crossfadeDuration: TimeInterval) {}
}
