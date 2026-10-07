import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import SongbirdLib

@Suite("Verified library artwork embedding", .serialized)
struct LibraryFileArtworkRepairTests {
    @Test("Fresh whole-catalog scope embeds saved JPEG/PNG and retains different existing artwork",
          arguments: ["flac", "m4a"], ["jpeg", "png"])
    @MainActor
    func actualSavedCovers(ext: String, imageType: String) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = try fixture(ext, at: directory, name: "missing")
        let covered = try fixture(ext, at: directory, name: "covered")
        let noAlbumCover = try fixture(ext, at: directory, name: "no-album-cover")
        let saved = try image(imageType)
        let existing = try image("png", red: 0.9)
        let fields: [TrackMetadataField: TrackMetadataValue] = [
            .title: .text("Kept Title"), .artist: .text("Kept Artist"), .album: .text("Kept Album"),
            .genre: .text("Jazz"), .year: .number(2001), .comment: .text("Kept Comment"),
            .trackNumber: .number(7), .trackTotal: .number(12), .discNumber: .number(2), .discTotal: .number(3)
        ]
        try await TagWriterService.writeTags(path: missing.path, fields: fields)
        try await TagWriterService.writeTags(path: covered.path, fields: fields, artworkData: existing)
        let before = try #require(await MetadataReader.read(from: missing, detectMissingBPM: false))
        let coveredBytes = try Data(contentsOf: covered)
        let untouchedBytes = try Data(contentsOf: noAlbumCover)
        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let album = Album(title: "Saved Cover"); album.artworkData = saved
        container.mainContext.insert(album)
        for url in [missing, covered] {
            let track = Track(path: url.path); track.albumRelation = album
            container.mainContext.insert(track)
        }
        container.mainContext.insert(Track(path: noAlbumCover.path))
        try container.mainContext.save()
        // Intentionally never publish a snapshot: the action must fetch current saved albums.
        let snapshots = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        let session = PlaybackSession(backend: ArtworkTestBackend())
        defer { session.engine.stop(); session.queue.clear() }
        let actions = LibraryItemActionHandler(modelContainer: container, playbackSession: session,
            librarySnapshots: snapshots, navigation: LibraryNavigationCoordinator(restoresPersistedState: false))
        let result = await actions.saveLibraryArtworkToFiles()
        #expect(result.written == 1 && result.preserved == 1 && result.failed == 0 && result.scopeError == nil)
        let after = try #require(await MetadataReader.read(from: missing, detectMissingBPM: false))
        #expect(after.artworkData == saved && after.tagValues == before.tagValues)
        #expect(after.sampleRate == before.sampleRate && after.duration == before.duration)
        #expect(try Data(contentsOf: covered) == coveredBytes)
        #expect(try Data(contentsOf: noAlbumCover) == untouchedBytes)
        #expect(album.artworkData == saved)
        let repeated = await actions.saveLibraryArtworkToFiles()
        #expect(repeated.written == 0 && repeated.preserved == 2)
    }

    @Test("Failed verification, stale catalog, concurrent file edits and cancellation retain original",
          arguments: ["verification", "unreadable", "stale-before", "stale-after", "file-change", "cancel-after-catalog"])
    func retainedOriginal(reason: String) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try fixture("flac", at: directory, name: "original")
        let original = try Data(contentsOf: target)
        let saved = try image("png")
        let state = ArtworkTestState()
        let service = LibraryFileTagRepairService(reader: {
            reason == "unreadable" ? nil : await MetadataReader.read(from: $0, detectMissingBPM: false)
        }, writer: { _, _ in }, artworkWriter: { path, artwork in
            await state.wrote()
            try await TagWriterService.writeTags(path: path,
                fields: reason == "verification" ? [.title: .text("Wrong title")] : [:], artworkData: artwork)
            if reason == "file-change" { try (original + Data([0])).write(to: target) }
        })
        let result = await service.applyArtwork([request(target, saved)], isCanceled: { await state.canceled },
            catalogIsCurrent: { _ in
                let count = await state.checkedCatalog()
                if reason == "cancel-after-catalog" && count == 2 { await state.cancel() }
                return reason != "stale-before" && !(reason == "stale-after" && count == 2)
            })
        if reason.hasPrefix("stale") { #expect(result.conflicts == 1) }
        else if reason == "cancel-after-catalog" { #expect(result.canceled && result.results.isEmpty) }
        else { #expect(result.failed == 1) }
        #expect(try Data(contentsOf: target) == (reason == "file-change" ? original + Data([0]) : original))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["original.flac"])
        if reason == "stale-before" || reason == "unreadable" { #expect(await state.writes == 0) }
    }

    @Test("A changed catalog cover, path or album while writing cannot reach the original file",
          arguments: ["cover", "path", "album"])
    @MainActor
    func freshCatalogGuard(change: String) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try fixture("flac", at: directory, name: "original")
        let original = try Data(contentsOf: target)
        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let album = Album(title: "Album"); album.artworkData = try image("png")
        let track = Track(path: target.path); track.albumRelation = album
        container.mainContext.insert(album); container.mainContext.insert(track); try container.mainContext.save()
        let albumID = album.id
        let trackID = track.id
        let changedCover = try image("png", red: 0.9)
        let service = LibraryFileTagRepairService(reader: {
            await MetadataReader.read(from: $0, detectMissingBPM: false)
        }, writer: { _, _ in }, artworkWriter: { path, artwork in
            try await TagWriterService.writeTags(path: path, fields: [:], artworkData: artwork)
            try await MainActor.run {
                let context = ModelContext(container)
                let albums = try context.fetch(FetchDescriptor<Album>())
                let current = try #require(albums.first(where: { $0.id == albumID }))
                switch change {
                case "cover": current.artworkData = changedCover
                case "path":
                    let tracks = try context.fetch(FetchDescriptor<Track>())
                    let liveTrack = try #require(tracks.first(where: { $0.id == trackID }))
                    liveTrack.path = target.path + ".relocated"
                default:
                    let replacement = Album(title: "New Album"); replacement.artworkData = artwork
                    context.insert(replacement)
                    let tracks = try context.fetch(FetchDescriptor<Track>())
                    let liveTrack = try #require(tracks.first(where: { $0.id == trackID }))
                    liveTrack.albumRelation = replacement
                }
                try context.save()
            }
        })
        let snapshots = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        let session = PlaybackSession(backend: ArtworkTestBackend())
        defer { session.engine.stop(); session.queue.clear() }
        let actions = LibraryItemActionHandler(modelContainer: container, playbackSession: session,
            librarySnapshots: snapshots, navigation: LibraryNavigationCoordinator(restoresPersistedState: false), fileTagRepairs: service)
        let result = await actions.saveLibraryArtworkToFiles()
        #expect(result.conflicts == 1 && result.written == 0 && result.failed == 0)
        #expect(try Data(contentsOf: target) == original)
    }

    @Test("Unique paths have one write/progress result; conflicting covers never write")
    func deduplicatedPaths() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try fixture("flac", at: directory, name: "deduplicated")
        let saved = try image("png")
        let first = request(target, saved)
        let state = ArtworkTestState()
        let result = await LibraryFileTagRepairService().applyArtwork([first, first]) { completed, total in
            await state.progress(completed, total)
        }
        #expect(result.written == 1 && result.results.count == 1)
        let progress = (await state.completed, await state.total)
        #expect(progress.0 == [1] && progress.1 == 1)
        let bytes = try Data(contentsOf: target)
        let conflict = await LibraryFileTagRepairService().applyArtwork([first, request(target, try image("png", red: 0.9))])
        #expect(conflict.conflicts == 1 && conflict.written == 0)
        #expect(try Data(contentsOf: target) == bytes)
        let canceled = await LibraryFileTagRepairService().applyArtwork([first], isCanceled: { true })
        #expect(canceled.canceled && canceled.results.isEmpty)
    }

    @Test("Undecodable AV picture tags are present and must be preserved")
    func undecodablePicturePresence() async throws {
        let item = AVMutableMetadataItem(); item.key = "covr" as NSString; item.keySpace = .iTunes
        item.value = Data([1, 2, 3]) as NSData
        var metadata = MetadataReader.blank(from: URL(fileURLWithPath: "/fixture.m4a"))
        await MetadataReader.applyAVItems([item], to: &metadata)
        #expect(metadata.embeddedArtworkPresent && metadata.artworkData == nil)
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try fixture("m4a", at: directory, name: "existing-picture")
        let bytes = try Data(contentsOf: target)
        metadata.duration = 1; metadata.sampleRate = 48_000
        let before = metadata
        let state = ArtworkTestState()
        let service = LibraryFileTagRepairService(reader: { _ in before }, writer: { _, _ in },
            artworkWriter: { _, _ in await state.wrote() })
        let result = await service.applyArtwork([request(target, try image("png"))])
        #expect(result.preserved == 1 && result.written == 0)
        #expect(await state.writes == 0)
        #expect(try Data(contentsOf: target) == bytes)
    }

    @Test("An existing empty FLAC picture block is preserved even without usable image bytes")
    func emptyFLACPicture() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try fixture("flac", at: directory, name: "empty-picture")
        let original = try Data(contentsOf: target)
        var offset = 4, lastHeader = 4
        repeat {
            lastHeader = offset
            let length = Int(original[offset + 1]) << 16 | Int(original[offset + 2]) << 8 | Int(original[offset + 3])
            offset += 4 + length
        } while original[lastHeader] & 0x80 == 0
        // Valid PICTURE fields with an empty image-data payload.
        let payload = Data([0, 0, 0, 3, 0, 0, 0, 9]) + Data("image/png".utf8) + Data(repeating: 0, count: 24)
        var bytes = original.prefix(offset)
        bytes[lastHeader] &= 0x7F
        bytes.append(contentsOf: [0x86, 0, 0, UInt8(payload.count)])
        bytes.append(payload); bytes.append(original.suffix(from: offset))
        try bytes.write(to: target)
        let before = try #require(await MetadataReader.read(from: target, detectMissingBPM: false))
        #expect(before.artworkData == nil)
        let result = await LibraryFileTagRepairService().applyArtwork([request(target, try image("png"))])
        #expect(result.preserved == 1 && result.written == 0 && result.failed == 0)
        #expect(try Data(contentsOf: target) == bytes)
    }

    @Test("Unsupported MP3 passthrough leaves generated MP3 bytes untouched")
    func mp3Support() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("fixture.mp3")
        let source = fixtures.appendingPathComponent("priming-44k-mono.mp3")
        try FileManager.default.copyItem(at: source, to: target)
        let bytes = try Data(contentsOf: target)
        let result = await LibraryFileTagRepairService().applyArtwork([request(target, try image("png"))])
        #expect(result.written == 0 && result.failed == 1)
        let status = try #require(result.results.first?.status)
        if case .failed(let reason) = status { #expect(reason.contains("not supported for MP3")) }
        #expect(try Data(contentsOf: target) == bytes)
    }

    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated")
    }
    private func fixture(_ ext: String, at directory: URL, name: String) throws -> URL {
        let basename = ext == "flac" ? "tone-44100-stereo-24" : "tone-48000-stereo-24-alac"
        let target = directory.appendingPathComponent(name).appendingPathExtension(ext)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent(basename).appendingPathExtension(ext), to: target)
        return target
    }
    private func request(_ url: URL, _ artwork: Data) -> LibraryFileArtworkRequest {
        LibraryFileArtworkRequest(trackID: UUID(), albumID: UUID(), path: url.path, artworkData: artwork)
    }
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("songbird-artwork-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
    private func image(_ type: String, red: CGFloat = 0.2) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.4, blue: 0.6, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data,
            (type == "jpeg" ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private actor ArtworkTestState {
    var writes = 0, catalogChecks = 0, total = 0
    var canceled = false
    var completed: [Int] = []
    func wrote() { writes += 1 }
    func checkedCatalog() -> Int { catalogChecks += 1; return catalogChecks }
    func cancel() { canceled = true }
    func progress(_ count: Int, _ total: Int) { completed.append(count); self.total = total }
}

@MainActor
private final class ArtworkTestBackend: PlayerBackend {
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
