import XCTest
import SwiftData
@testable import SongbirdLib

@MainActor
final class TrackImporterSignatureTests: XCTestCase {
    private var container: ModelContainer!
    private var tempDir: URL!

    override func setUp() async throws {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRefreshIfChangedSkipsUnchangedFile() async throws {
        let file = tempDir.appendingPathComponent("sample.wav")
        // Minimal RIFF/WAVE header-ish bytes (not a real decodeable file — metadata may be empty).
        var data = Data("RIFF".utf8)
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(contentsOf: "WAVE".utf8)
        try data.write(to: file)

        let context = ModelContext(container)
        let track = Track(path: file.path, title: "Sample")
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        track.fileSize = (attrs[.size] as? Int64) ?? 0
        track.dateModified = (attrs[.modificationDate] as? Date) ?? Date()
        track.checksum = Track.contentChecksum(at: file.path)
        context.insert(track)
        try context.save()

        let changed = try await TrackImporter.refreshIfChanged(track, at: file.path, in: context)
        XCTAssertFalse(changed)
    }

    func testFileSignatureChangesWithContent() throws {
        let file = tempDir.appendingPathComponent("sig.txt")
        try Data("one".utf8).write(to: file)
        let sig1 = Track.fileSignature(at: file.path)
        // Ensure mtime can change
        Thread.sleep(forTimeInterval: 1.05)
        try Data("two-longer".utf8).write(to: file)
        let sig2 = Track.fileSignature(at: file.path)
        XCTAssertNotEqual(sig1, sig2)
    }

    func testDiscoversCaseInsensitiveCoverJPGBesideAudioFile() throws {
        let audioFile = tempDir.appendingPathComponent("track.flac")
        let expectedArtwork = try folderArtworkFixture()
        try Data().write(to: audioFile)
        try expectedArtwork.write(to: tempDir.appendingPathComponent("COVER.JPG"))

        XCTAssertEqual(
            TrackImporter.folderArtworkData(for: audioFile),
            expectedArtwork
        )
    }

    func testDoesNotUseCoverFromParentFolder() throws {
        let albumFolder = tempDir.appendingPathComponent("Album", isDirectory: true)
        try FileManager.default.createDirectory(at: albumFolder, withIntermediateDirectories: true)
        let audioFile = albumFolder.appendingPathComponent("track.flac")
        try Data().write(to: audioFile)
        try Data([0xFF, 0xD8]).write(to: tempDir.appendingPathComponent("cover.jpg"))

        XCTAssertNil(TrackImporter.folderArtworkData(for: audioFile))
    }

    func testLinkRelationsMovesArtworkToAlbumAndClearsTrackCopy() throws {
        let context = ModelContext(container)
        let artwork = Data([1, 2, 3, 4])
        let track = Track(
            path: tempDir.appendingPathComponent("song.flac").path,
            title: "Song",
            artist: "Artist",
            album: "Album"
        )
        context.insert(track)

        try TrackImporter.linkRelations(for: track, artworkData: artwork, in: context)

        XCTAssertNil(track.artworkData)
        XCTAssertEqual(track.albumRelation?.artworkData, artwork)
        XCTAssertEqual(track.resolvedArtworkData, artwork)
    }

    func testLinkRelationsUsesAlbumArtistForAlbumIdentity() throws {
        let context = ModelContext(container)
        let first = Track(path: "/tmp/one.flac", title: "One", artist: "Singer One", album: "Compilation")
        first.albumArtist = "Curator"
        let second = Track(path: "/tmp/two.flac", title: "Two", artist: "Singer Two", album: "Compilation")
        second.albumArtist = "Curator"
        context.insert(first)
        context.insert(second)

        try TrackImporter.linkRelations(for: first, in: context)
        try TrackImporter.linkRelations(for: second, in: context)

        XCTAssertTrue(first.albumRelation === second.albumRelation)
        XCTAssertEqual(first.albumRelation?.artist, "Curator")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Album>()), 1)
    }

    func testAlbumRelationshipMaintenanceRepairsPerformerSplitAlbums() async throws {
        let context = ModelContext(container)
        let firstAlbum = Album(title: "Touch", artist: "Singer One")
        let secondAlbum = Album(title: "Touch", artist: "Singer Two")
        let first = Track(path: "/tmp/repair-one.flac", title: "One", artist: "Singer One", album: "Touch")
        let second = Track(path: "/tmp/repair-two.flac", title: "Two", artist: "Singer Two", album: "Touch")
        first.albumArtist = "Yuji Ohno"
        second.albumArtist = "Yuji Ohno"
        first.albumRelation = firstAlbum
        second.albumRelation = secondAlbum
        context.insert(firstAlbum)
        context.insert(secondAlbum)
        context.insert(first)
        context.insert(second)
        try context.save()

        let repaired = await AlbumRelationshipMaintenance.repairLibrary(in: container)
        XCTAssertTrue(repaired)

        let repairedContext = ModelContext(container)
        let repairedTracks = try repairedContext.fetch(FetchDescriptor<Track>())
        let repairedAlbums = try repairedContext.fetch(FetchDescriptor<Album>())
        XCTAssertEqual(repairedAlbums.count, 1)
        XCTAssertEqual(repairedAlbums.first?.artist, "Yuji Ohno")
        XCTAssertEqual(Set(repairedTracks.compactMap(\.albumRelation?.id)).count, 1)
    }
}
