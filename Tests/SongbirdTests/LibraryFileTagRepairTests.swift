import AVFoundation
import CoreGraphics
import Foundation
import FLACBridge
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import SongbirdLib

@Suite("File tag recovery and permanent Health repairs", .serialized)
struct LibraryFileTagRepairTests {
    @Test("MP4 binary track/disc pairs retain their totals")
    func binaryPairs() async {
        var metadata = MetadataReader.blank(from: URL(fileURLWithPath: "/fixture.m4a"))
        let track = AVMutableMetadataItem()
        track.key = "trkn" as NSString; track.keySpace = .iTunes
        track.value = Data([0, 0, 0, 7, 0, 12, 0, 0]) as NSData
        let disc = AVMutableMetadataItem()
        disc.key = "disk" as NSString; disc.keySpace = .iTunes
        disc.value = Data([0, 0, 0, 2, 0, 3]) as NSData
        await MetadataReader.applyAVItems([track, disc], to: &metadata)
        #expect(metadata.trackNumber == 7 && metadata.trackTotal == 12)
        #expect(metadata.discNumber == 2 && metadata.discTotal == 3)
        #expect(MetadataReader.unpackNumberPair(Data([1, 2, 3])) == nil)
    }

    @Test("Numeric copyright atom keys expose existing MP4 genre and release year")
    func numericCopyrightKeys() async {
        let genre = AVMutableMetadataItem()
        genre.key = NSNumber(value: UInt32(0xA967656E)); genre.keySpace = .iTunes
        genre.value = "Electronic" as NSString
        let year = AVMutableMetadataItem()
        year.key = NSNumber(value: UInt32(0xA9646179)); year.keySpace = .iTunes
        year.value = "2004-05-06" as NSString
        var metadata = MetadataReader.blank(from: URL(fileURLWithPath: "/fixture.m4a"))
        await MetadataReader.applyAVItems([genre, year], to: &metadata)
        #expect(metadata.genre == "Electronic" && metadata.year == 2004)
        #expect(MetadataReader.keyDescription(genre.key) == "©gen")
    }

    @Test("ID3 identifiers expose genre, year, track and disc tags")
    func id3Keys() async {
        let values = ["TIT2": "Tagged Title", "TPE1": "Tagged Artist", "TPE2": "Album Artist",
                      "TALB": "Tagged Album", "TCON": "Jazz", "TDRC": "2001-06-03",
                      "TRCK": "7/12", "TPOS": "2/3"]
        let items = values.map { key, value -> AVMetadataItem in
            let item = AVMutableMetadataItem()
            item.key = key as NSString; item.keySpace = .id3; item.value = value as NSString
            return item
        }
        var metadata = MetadataReader.blank(from: URL(fileURLWithPath: "/fixture.mp3"))
        await MetadataReader.applyAVItems(items, to: &metadata)
        #expect(metadata.title == "Tagged Title" && metadata.artist == "Tagged Artist")
        #expect(metadata.album == "Tagged Album" && metadata.albumArtist == "Album Artist")
        #expect(metadata.genre == "Jazz" && metadata.year == 2001)
        #expect(metadata.trackNumber == 7 && metadata.trackTotal == 12)
        #expect(metadata.discNumber == 2 && metadata.discTotal == 3)
    }

    @Test("Recovery fills missing values and preserves catalog choices and statistics")
    @MainActor
    func fillOnlyRecovery() {
        let track = Track(path: "/fixture.m4a", title: "Catalog Title", artist: "Unknown Artist",
                          album: "Catalog Album")
        track.rating = 5; track.playCount = 17; track.trackNumber = 4
        var metadata = readableMetadata(path: track.path)
        metadata.title = "File Title"; metadata.artist = "File Artist"; metadata.album = "File Album"
        metadata.genre = "Jazz"; metadata.year = 2001; metadata.trackNumber = 7; metadata.trackTotal = 12
        #expect(TrackImporter.recoverMissingFields(metadata, for: track))
        #expect(track.title == "Catalog Title" && track.album == "Catalog Album")
        #expect(track.artist == "File Artist" && track.genre == "Jazz" && track.year == 2001)
        #expect(track.trackNumber == 4 && track.trackTotal == 12)
        #expect(track.rating == 5 && track.playCount == 17)
        #expect(!TrackImporter.recoverMissingFields(metadata, for: track))
    }

    @Test("Bulk Health recovery publishes existing tags/artwork and preserves file bytes")
    @MainActor
    func bulkRecovery() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/tone-44100-stereo-24.flac")
        let target = directory.appendingPathComponent("fixture.flac")
        try FileManager.default.copyItem(at: source, to: target)
        let image = try png()
        try await TagWriterService.writeTags(path: target.path, fields: [
            .title: .text("File Title"), .artist: .text("File Artist"), .album: .text("File Album"),
            .genre: .text("Jazz"), .year: .number(2001), .trackNumber: .number(7)
        ], artworkData: image)
        let originalBytes = try Data(contentsOf: target)
        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let track = Track(path: target.path, title: "Catalog Title")
        track.rating = 5; track.playCount = 17
        container.mainContext.insert(track); try container.mainContext.save()
        let snapshots = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await snapshots.refresh()
        let session = PlaybackSession(backend: FileTagTestBackend())
        defer { session.engine.stop(); session.queue.clear() }
        let actions = LibraryItemActionHandler(modelContainer: container, playbackSession: session,
            librarySnapshots: snapshots, navigation: LibraryNavigationCoordinator(restoresPersistedState: false))
        let summary = await actions.recoverMissingFileTags(trackIDs: [track.id, track.id])
        #expect(summary.recovered == 1 && summary.checked == 1 && summary.failed == 0 && summary.saveError == nil)
        await snapshots.refresh()
        let restored = try #require(snapshots.snapshot.tracksByID[track.id])
        #expect(restored.genre == "Jazz" && restored.year == 2001 && restored.trackNumber == 7)
        #expect(restored.artist == "File Artist" && restored.album == "File Album")
        #expect(restored.title == "Catalog Title" && restored.rating == 5 && restored.playCount == 17)
        #expect(restored.artworkReference != nil && restored.beatsPerMinute == 0)
        #expect(try Data(contentsOf: target) == originalBytes)
    }

    @Test("A stale catalog finding cannot write an obsolete value into a missing file tag")
    @MainActor
    func staleCatalogFinding() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/tone-44100-stereo-24.flac")
        let target = directory.appendingPathComponent("fixture.flac")
        try FileManager.default.copyItem(at: source, to: target)
        let originalBytes = try Data(contentsOf: target)
        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let track = Track(path: target.path); track.genre = "User's New Choice"
        container.mainContext.insert(track); try container.mainContext.save()
        let snapshots = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await snapshots.refresh()
        let session = PlaybackSession(backend: FileTagTestBackend())
        defer { session.engine.stop(); session.queue.clear() }
        let actions = LibraryItemActionHandler(modelContainer: container, playbackSession: session,
            librarySnapshots: snapshots, navigation: LibraryNavigationCoordinator(restoresPersistedState: false))
        let evidence = [LibraryHealthEvidence(kind: .unanimousDirectorySiblings, summary: "Old evidence")]
        let issue = LibraryHealthIssue(category: .missingGenre,
            grouping: .init(stableKey: "fixture", displayName: "Fixture", trackIDs: [track.id]), currentValue: "", evidence: evidence)
        let change = LibraryRemediationChange(target: .init(trackID: track.id, field: .genre), expectedValue: "", proposedValue: "Jazz")
        let plan = LibraryRemediationPlan(category: .missingGenre, proposals: [.init(issue: issue, proposedValue: "Jazz",
            confidence: .automaticSafe, evidence: evidence, changes: [change])])
        let summary = await actions.saveHealthTagsToFiles(plan)
        #expect(summary.written == 0 && summary.failed == 1)
        #expect(try Data(contentsOf: target) == originalBytes)
        #expect(track.genre == "User's New Choice")
    }

    @Test("Generated FLAC/M4A files get a durable missing genre with other tags and artwork preserved",
          arguments: ["flac", "m4a"])
    func verifiedPermanentWrite(ext: String) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = ext == "flac" ? "tone-44100-stereo-24" : "tone-48000-stereo-24-alac"
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/\(name).\(ext)")
        let target = directory.appendingPathComponent("fixture.\(ext)")
        try FileManager.default.copyItem(at: source, to: target)
        let image = try png()
        try await TagWriterService.writeTags(path: target.path, fields: [
            .title: .text("Kept Title"), .artist: .text("Kept Artist"), .album: .text("Kept Album"),
            .comment: .text("Kept Comment"), .year: .number(2001),
            .trackNumber: .number(7), .trackTotal: .number(12), .discNumber: .number(2), .discTotal: .number(3)
        ], artworkData: image)
        let before = try #require(await MetadataReader.read(from: target, detectMissingBPM: false))
        #expect(before.title == "Kept Title" && before.artist == "Kept Artist" && before.year == 2001)
        #expect(before.trackNumber == 7 && before.trackTotal == 12)
        #expect(before.discNumber == 2 && before.discTotal == 3)
        #expect(before.artworkData == image)
        let request = request(path: target.path, value: "Jazz")
        let result = await LibraryFileTagRepairService().apply([request])
        #expect(result.written == 1 && result.failed == 0)
        let after = try #require(await MetadataReader.read(from: target, detectMissingBPM: false))
        var expected = before.tagValues; expected[.genre] = .text("Jazz")
        #expect(after.tagValues == expected && after.artworkData == before.artworkData)
        #expect(after.sampleRate == before.sampleRate && after.duration == before.duration)
        let repeated = await LibraryFileTagRepairService().apply([request])
        #expect(repeated.written == 0 && repeated.alreadyPresent == 1)
    }

    @Test("Raw iTunes genre/year tags and an existing track total survive a missing-number repair")
    func rawContainerTags() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/tone-48000-stereo-24-alac.m4a")
        let target = directory.appendingPathComponent("fixture.m4a")
        func item(_ key: UInt32, _ value: any NSCopying & NSObjectProtocol) -> AVMetadataItem {
            let item = AVMutableMetadataItem(); item.keySpace = .iTunes
            item.key = NSNumber(value: key); item.value = value
            return item
        }
        let export = try #require(AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough))
        export.outputURL = target; export.outputFileType = .m4a
        export.metadata = [item(0xA967656E, "Jazz" as NSString), item(0xA9646179, "2001-06-03" as NSString),
                           item(0x74726B6E, Data([0, 0, 0, 0, 0, 12, 0, 0]) as NSData)]
        await export.export()
        #expect(export.status == .completed)
        let before = try #require(await MetadataReader.read(from: target, detectMissingBPM: false))
        #expect(before.genre == "Jazz" && before.year == 2001 && before.trackNumber == 0 && before.trackTotal == 12)
        let id = UUID()
        let request = LibraryFileTagRepairRequest(trackID: id, path: target.path,
            change: LibraryRemediationChange(target: .init(trackID: id, field: .trackNumber), expectedValue: "0", proposedValue: "7"))
        let result = await LibraryFileTagRepairService().apply([request])
        #expect(result.written == 1 && result.failed == 0)
        let after = try #require(await MetadataReader.read(from: target, detectMissingBPM: false))
        #expect(after.genre == "Jazz" && after.year == 2001 && after.trackNumber == 7 && after.trackTotal == 12)
    }

    @Test("Filling a missing artist preserves an absent physical album-artist tag",
          arguments: ["flac", "m4a"])
    func missingArtistFallback(ext: String) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = ext == "flac" ? "tone-44100-stereo-24" : "tone-48000-stereo-24-alac"
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/\(name).\(ext)")
        let target = directory.appendingPathComponent("fixture.\(ext)")
        try FileManager.default.copyItem(at: source, to: target)
        let before = try #require(await MetadataReader.read(from: target, detectMissingBPM: false))
        #expect(before.artist == "Unknown Artist" && before.albumArtist == "Unknown Artist")
        let id = UUID()
        let request = LibraryFileTagRepairRequest(trackID: id, path: target.path,
            change: LibraryRemediationChange(target: .init(trackID: id, field: .artist), expectedValue: "Unknown Artist", proposedValue: "Recovered Artist"))
        let result = await LibraryFileTagRepairService().apply([request])
        #expect(result.written == 1 && result.failed == 0)
        let after = try #require(await MetadataReader.read(from: target, detectMissingBPM: false))
        #expect(after.artist == "Recovered Artist" && after.albumArtist == "Recovered Artist")
        if ext == "flac" {
            let decoder = try #require(target.path.withCString { SBFLACOpen($0) })
            defer { SBFLACClose(decoder) }
            #expect("ALBUMARTIST".withCString { SBFLACTag(decoder, $0) } == nil)
        } else {
            let items = await MetadataReader.allAVMetadata(in: AVURLAsset(url: target))
            #expect(!items.contains {
                MetadataReader.keyDescription($0.key).lowercased() == "aart"
                    || ($0.identifier?.rawValue.lowercased().contains("albumartist") == true)
            })
        }
    }

    @Test("Compact iTunes release dates expose their year and retain the full physical date")
    func compactReleaseDates() async throws {
        for (value, year) in [(20180129, 2018), (20151015, 2015)] {
            let numeric = AVMutableMetadataItem(); numeric.key = NSNumber(value: UInt32(0xA9646179))
            numeric.keySpace = .iTunes; numeric.value = NSNumber(value: value)
            var metadata = MetadataReader.blank(from: URL(fileURLWithPath: "/fixture.m4a"))
            await MetadataReader.applyAVItems([numeric], to: &metadata)
            #expect(metadata.year == year)
        }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/tone-48000-stereo-24-alac.m4a")
        let target = directory.appendingPathComponent("compact-date.m4a")
        let date = AVMutableMetadataItem(); date.key = NSNumber(value: UInt32(0xA9646179))
        date.keySpace = .iTunes; date.value = "20180129" as NSString
        let export = try #require(AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough))
        export.outputURL = target; export.outputFileType = .m4a; export.metadata = [date]
        await export.export()
        #expect(export.status == .completed)
        let before = try #require(await MetadataReader.read(from: target, detectMissingBPM: false))
        #expect(before.year == 2018)
        let result = await LibraryFileTagRepairService().apply([request(path: target.path, value: "Jazz")])
        #expect(result.written == 1 && result.failed == 0)
        let after = try #require(await MetadataReader.read(from: target, detectMissingBPM: false))
        #expect(after.year == 2018 && after.genre == "Jazz")
        let items = try await MetadataReader.completeAVMetadata(in: AVURLAsset(url: target))
        let physicalDate = try #require(items.first { MetadataReader.keyDescription($0.key) == "©day" })
        #expect(try await physicalDate.load(.stringValue) == "20180129")
    }

    @Test("Conflicting file tags and an unverified saved copy leave originals intact",
          arguments: [true, false])
    func preservesOriginal(conflictingTag: Bool) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("fixture.flac")
        let original = Data("original bytes".utf8)
        try original.write(to: target)
        var originalMetadata = readableMetadata(path: target.path)
        if conflictingTag { originalMetadata.genre = "Blues" }
        let before = originalMetadata
        let service = LibraryFileTagRepairService(reader: { url in
            var value = before
            if url != target { value.title = "Unexpected changed title"; value.genre = "Jazz" }
            return value
        }, writer: { path, _ in try Data("candidate bytes".utf8).write(to: URL(fileURLWithPath: path)) })
        let result = await service.apply([request(path: target.path, value: "Jazz")])
        #expect(conflictingTag ? result.conflicts == 1 : result.failed == 1)
        #expect(try Data(contentsOf: target) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["fixture.flac"])
    }

    @Test("Filename inference and consistency rewrites cannot become automatic file repairs")
    func excludesGuesses() {
        let id = UUID()
        let grouping = LibraryHealthGrouping(stableKey: "fixture", displayName: "Fixture", trackIDs: [id])
        func plan(confidence: LibraryRemediationConfidence, kind: LibraryHealthEvidenceKind, expected: String) -> LibraryRemediationPlan {
            let evidence = [LibraryHealthEvidence(kind: kind, summary: "Fixture evidence")]
            let issue = LibraryHealthIssue(category: .missingGenre, grouping: grouping, currentValue: expected, evidence: evidence)
            let change = LibraryRemediationChange(target: .init(trackID: id, field: .genre), expectedValue: expected, proposedValue: "Jazz")
            return LibraryRemediationPlan(category: .missingGenre, proposals: [.init(issue: issue, proposedValue: "Jazz",
                confidence: confidence, evidence: evidence, changes: [change])])
        }
        #expect(plan(confidence: .automaticSafe, kind: .unanimousDirectorySiblings, expected: "").safeMissingFileTagChanges.count == 1)
        #expect(plan(confidence: .reviewRequired, kind: .filenameInference, expected: "").safeMissingFileTagChanges.isEmpty)
        #expect(plan(confidence: .automaticSafe, kind: .filenameInference, expected: "").safeMissingFileTagChanges.isEmpty)
        #expect(plan(confidence: .automaticSafe, kind: .unanimousDirectorySiblings, expected: "Blues").safeMissingFileTagChanges.isEmpty)
        #expect(LibraryFileTagRepairService.metadataField(.title) == nil)
    }

    @Test("A generated original externally edited while its tag copy is saved is retained")
    func concurrentFileChange() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/tone-44100-stereo-24.flac")
        let target = directory.appendingPathComponent("fixture.flac")
        try FileManager.default.copyItem(at: source, to: target)
        let changed = try Data(contentsOf: target) + Data([0])
        let service = LibraryFileTagRepairService(reader: {
            await MetadataReader.read(from: $0, detectMissingBPM: false)
        }, writer: { path, fields in
            try await TagWriterService.writeTags(path: path, fields: fields)
            try changed.write(to: target)
        })
        let result = await service.apply([request(path: target.path, value: "Jazz")])
        #expect(result.failed == 1 && result.written == 0)
        #expect(try Data(contentsOf: target) == changed)
    }

    private func request(path: String, value: String) -> LibraryFileTagRepairRequest {
        let id = UUID()
        return LibraryFileTagRepairRequest(trackID: id, path: path,
            change: LibraryRemediationChange(target: .init(trackID: id, field: .genre), expectedValue: "", proposedValue: value))
    }
    private func readableMetadata(path: String) -> AudioMetadata {
        var metadata = MetadataReader.blank(from: URL(fileURLWithPath: path))
        metadata.duration = 1; metadata.sampleRate = 44_100
        return metadata
    }
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("songbird-tag-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
    private func png() throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

@MainActor
private final class FileTagTestBackend: PlayerBackend {
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
