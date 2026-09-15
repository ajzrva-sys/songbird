import AudioToolbox
import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import SongbirdLib

@Suite("Audio CD lossless import")
struct AudioCDRipperTests {
    @Test("ALAC writer preserves every CDDA frame")
    func alacEncoding() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-alac-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("track.m4a")
        let writer = try ALACAudioCDFileWriterFactory().makeWriter(at: url)
        try writer.append(cddaData: constantSector(left: 12_345, right: -12_345))
        try writer.finish()

        let file = try AVAudioFile(forReading: url)
        #expect(file.length == 588)
        let formatID = (file.fileFormat.settings[AVFormatIDKey] as? NSNumber)?.uint32Value
        #expect(formatID == kAudioFormatAppleLossless)
        #expect(file.fileFormat.sampleRate == 44_100)
        #expect(file.fileFormat.channelCount == 2)
    }

    @Test("Ripper retries reads, reports whole-disc progress, and keeps stable names")
    func retryProgressAndNaming() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-ripper-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = RipCapture()
        let reader = RetryingSectorReader(capture: capture, failuresBeforeSuccess: 2)
        let ripper = AudioCDRipper(
            sectorReader: reader,
            writerFactory: CapturingWriterFactory(capture: capture),
            sectorsPerRead: 2
        )
        let progress = ProgressCapture()

        let results = try await ripper.rip(
            disc: makeDisc(),
            destinationRoot: directory
        ) { value in
            await progress.append(value)
        }

        #expect(results.count == 2)
        #expect(results.map { $0.fileURL.lastPathComponent } == [
            "01 First - Song.m4a",
            "02 Second Song.m4a",
        ])
        #expect(results.allSatisfy { FileManager.default.fileExists(atPath: $0.fileURL.path) })
        #expect(capture.readCount == 5)
        #expect(capture.appendedByteCount == 5 * 2_352)
        let finalProgress = await progress.last
        #expect(finalProgress?.fractionCompleted == 1)
        #expect(finalProgress?.trackIndex == 2)
    }

    @Test("A repeated import reuses completed files without reading the disc again")
    func resumeUsesCompletedFiles() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-ripper-resume-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = RipCapture()
        let ripper = AudioCDRipper(
            sectorReader: RetryingSectorReader(capture: capture, failuresBeforeSuccess: 0),
            writerFactory: ALACAudioCDFileWriterFactory()
        )
        let disc = makeDisc()

        _ = try await ripper.rip(disc: disc, destinationRoot: directory) { _ in }
        let readsAfterFirstImport = capture.readCount
        let second = try await ripper.rip(disc: disc, destinationRoot: directory) { _ in }

        #expect(second.allSatisfy { $0.reusedExistingFile })
        #expect(capture.readCount == readsAfterFirstImport)
    }

    @Test("Cancellation stops between bounded reads and removes the partial track")
    func cancellationCleanup() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-ripper-cancel-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = RipCapture()
        let ripper = AudioCDRipper(
            sectorReader: RetryingSectorReader(capture: capture, failuresBeforeSuccess: 0),
            writerFactory: CapturingWriterFactory(capture: capture),
            sectorsPerRead: 1
        )

        let task = Task {
            try await ripper.rip(disc: makeDisc(), destinationRoot: directory) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        let partials = (try? FileManager.default.subpathsOfDirectory(atPath: directory.path)) ?? []
        #expect(partials.allSatisfy { !$0.contains(".partial.m4a") })
    }

    @Test("Unsafe metadata is converted to valid artist, album, and track paths")
    func safePaths() {
        let disc = makeDisc(title: " Album/Name: ", artist: " Artist/Name ")
        let root = URL(fileURLWithPath: "/tmp/Songbird")
        let directory = AudioCDRipPaths.albumDirectory(for: disc, root: root)

        #expect(directory.path == "/tmp/Songbird/Artist-Name/Album-Name")
        #expect(AudioCDRipPaths.filename(for: disc.tracks[0]) == "01 First - Song.m4a")
    }

    @MainActor
    @Test("Completed ALAC tracks enter the library with resolved CD metadata and artwork")
    func libraryImport() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-ripper-library-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("01 First Song.m4a")
        let writer = try ALACAudioCDFileWriterFactory().makeWriter(at: fileURL)
        try writer.append(cddaData: constantSector(left: 1_000, right: -1_000))
        try writer.finish()

        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let disc = makeDisc()
        let artwork = Data([1, 2, 3, 4])
        let coordinator = AudioCDRipCoordinator(destinationRoot: directory)

        let added = try await coordinator.importResult(
            AudioCDRipResult(
                track: disc.tracks[0],
                fileURL: fileURL,
                reusedExistingFile: false
            ),
            disc: disc,
            artworkData: artwork,
            modelContext: context
        )
        try context.save()
        let track = try #require(context.fetch(FetchDescriptor<Track>()).first)

        #expect(added)
        #expect(track.title == "First / Song")
        #expect(track.artist == "Artist")
        #expect(track.album == "Album")
        #expect(track.albumArtist == "Artist")
        #expect(track.year == 2026)
        #expect(track.trackNumber == 1)
        #expect(track.sampleRate == 44_100)
        #expect(track.albumRelation?.artworkData == artwork)
    }

    @MainActor
    @Test("A CD is marked imported only while every track is present in the library")
    func completeImportStatus() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-ripper-status-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let disc = makeDisc()
        let coordinator = AudioCDRipCoordinator(destinationRoot: directory)

        for discTrack in disc.tracks {
            let fileURL = directory.appendingPathComponent(AudioCDRipPaths.filename(for: discTrack))
            let writer = try ALACAudioCDFileWriterFactory().makeWriter(at: fileURL)
            try writer.append(cddaData: constantSector(left: 1_000, right: -1_000))
            try writer.finish()
            _ = try await coordinator.importResult(
                AudioCDRipResult(
                    track: discTrack,
                    fileURL: fileURL,
                    reusedExistingFile: false
                ),
                disc: disc,
                artworkData: nil,
                modelContext: context
            )
        }
        try context.save()

        coordinator.refreshImportStatus(for: disc, modelContext: context)
        #expect(coordinator.isImported)

        let importedTracks = try context.fetch(FetchDescriptor<Track>())
        context.delete(try #require(importedTracks.first(where: { $0.trackNumber == 2 })))
        try context.save()
        coordinator.refreshImportStatus(for: disc, modelContext: context)
        #expect(!coordinator.isImported)
    }

    @Test("Expiry during encoding preserves audio and resumes with explicit CD-Text fallback")
    func expiredRipRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = makeDisc()
        let clock = TestDiscogsClock()
        let disc = AudioDisc(id: original.id, title: "Remote Album", albumArtist: "Remote Artist",
            volumeURL: original.volumeURL, tracks: original.tracks,
            discogsEvidence: .init(releaseID: 42, fetches: [TestDiscogsClock.stamp()]),
            originalMetadata: original.originalMetadata)
        let capture = RipCapture()
        let ripper = AudioCDRipper(sectorReader: RetryingSectorReader(capture: capture, failuresBeforeSuccess: 0),
            clock: { clock.sample() })
        var recovered: [AudioCDRipResult] = []
        do {
            _ = try await ripper.rip(disc: disc, destinationRoot: directory) { _ in
                clock.set(TestDiscogsClock.stamp(18_001))
            }
            Issue.record("Expected expired metadata recovery")
        } catch AudioCDRipError.metadataExpired(let completed) {
            recovered = completed
        }
        #expect(recovered.count == 1)
        let file = try #require(recovered.first?.fileURL)
        #expect(try AVAudioFile(forReading: file).length == 3 * 588)
        let readsBeforeResume = capture.readCount
        let results = try await ripper.rip(disc: disc.restoringOriginalMetadata(),
            destinationRoot: directory, completed: recovered) { _ in }
        #expect(results.count == 2)
        #expect(results.first?.fileURL == file)
        #expect(results.first?.reusedExistingFile == true)
        #expect(capture.readCount == readsBeforeResume + 1)
    }

    @MainActor
    @Test("Expired CD metadata cannot mutate a library import")
    func expiredImportPreservesLibrary() async throws {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let original = makeDisc()
        let disc = AudioDisc(id: original.id, title: "Remote", volumeURL: original.volumeURL,
            tracks: original.tracks, discogsEvidence: .init(releaseID: 42, fetches: [TestDiscogsClock.stamp()]))
        let coordinator = AudioCDRipCoordinator(clock: { TestDiscogsClock.stamp(18_001) })
        await #expect(throws: AudioCDRipError.self) {
            _ = try await coordinator.importResult(.init(track: disc.tracks[0],
                fileURL: URL(fileURLWithPath: "/fixture/not-read.m4a"), reusedExistingFile: false),
                disc: disc, artworkData: nil, modelContext: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<Track>()) == 0)
        #expect(!context.hasChanges)
    }

    private func makeDisc(
        title: String = "Album",
        artist: String = "Artist"
    ) -> AudioDisc {
        let discID = DiscIdentifier("rip-test")
        let firstSource = AudioCDSource(
            discID: discID,
            deviceID: "mock-drive",
            trackNumber: 1,
            startSector: 0,
            endSector: 3
        )
        let secondSource = AudioCDSource(
            discID: discID,
            deviceID: "mock-drive",
            trackNumber: 2,
            startSector: 3,
            endSector: 5
        )
        return AudioDisc(
            id: discID,
            title: title,
            albumArtist: artist,
            year: 2026,
            volumeURL: URL(fileURLWithPath: "/Volumes/mock-drive"),
            tracks: [
                AudioDiscTrack(
                    discID: discID,
                    number: 1,
                    title: "First / Song",
                    artist: artist,
                    duration: 3.0 / 75,
                    startSector: 0,
                    endSector: 3,
                    source: firstSource
                ),
                AudioDiscTrack(
                    discID: discID,
                    number: 2,
                    title: "Second Song",
                    artist: artist,
                    duration: 2.0 / 75,
                    startSector: 3,
                    endSector: 5,
                    source: secondSource
                ),
            ]
        )
    }

    private func constantSector(left: Int16, right: Int16) -> Data {
        var data = Data(capacity: 2_352)
        for _ in 0..<588 {
            for sample in [left, right] {
                let bits = UInt16(bitPattern: sample)
                data.append(UInt8(truncatingIfNeeded: bits))
                data.append(UInt8(truncatingIfNeeded: bits >> 8))
            }
        }
        return data
    }
}

private final class RipCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _readCount = 0
    private var _appendedByteCount = 0

    var readCount: Int { lock.withLock { _readCount } }
    var appendedByteCount: Int { lock.withLock { _appendedByteCount } }

    func recordRead() -> Int {
        lock.withLock {
            _readCount += 1
            return _readCount
        }
    }

    func recordAppend(bytes: Int) {
        lock.withLock { _appendedByteCount += bytes }
    }
}

private struct RetryingSectorReader: AudioCDSectorReading {
    let capture: RipCapture
    let failuresBeforeSuccess: Int

    func readSectors(deviceID: String, firstSector: Int64, count: Int) throws -> Data {
        let request = capture.recordRead()
        if request <= failuresBeforeSuccess { throw AudioCDReaderError.deviceRead(-1) }
        var data = Data(capacity: count * 2_352)
        for _ in 0..<(count * 588) {
            data.append(contentsOf: [0, 0, 0, 0])
        }
        return data
    }
}

private struct CapturingWriterFactory: AudioCDFileWriterCreating {
    let capture: RipCapture

    func makeWriter(at url: URL) throws -> any AudioCDFileWriting {
        FileManager.default.createFile(atPath: url.path, contents: Data([1]))
        return CapturingWriter(capture: capture)
    }
}

private final class CapturingWriter: AudioCDFileWriting {
    let capture: RipCapture

    init(capture: RipCapture) { self.capture = capture }
    func append(cddaData: Data) throws { capture.recordAppend(bytes: cddaData.count) }
    func finish() throws {}
}

private actor ProgressCapture {
    private var values: [AudioCDRipProgress] = []
    func append(_ value: AudioCDRipProgress) { values.append(value) }
    var last: AudioCDRipProgress? { values.last }
}
