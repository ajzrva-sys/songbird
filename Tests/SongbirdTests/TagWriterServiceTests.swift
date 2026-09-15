import Foundation
import Testing
import FLACBridge

@testable import SongbirdLib

@Suite(.serialized)
struct TagWriterServiceTests {

    // MARK: - FLAC Tag Writing

    @Test("FLAC tags are written and readable")
    func flacTagsWritten() async throws {
        let temp = try copyFixture("tone-44100-stereo-24", extension: "flac")
        defer { try? FileManager.default.removeItem(at: temp) }

        try await TagWriterService.writeTags(
            path: temp.path,
            fields: [
                .title: .text("Test Title"),
                .artist: .text("Test Artist"),
                .album: .text("Test Album"),
                .albumArtist: .text("Test Album Artist"),
                .genre: .text("Rock"),
                .composer: .text("Test Composer"),
                .comment: .text("A comment"),
                .year: .number(2025),
                .trackNumber: .number(3),
                .trackTotal: .number(12),
                .discNumber: .number(1),
                .discTotal: .number(2),
                .beatsPerMinute: .number(120),
            ]
        )

        // Re-read and verify
        guard let decoder = temp.path.withCString({ SBFLACOpen($0) }) else {
            Issue.record("Failed to re-open FLAC file after writing tags")
            return
        }
        defer { SBFLACClose(decoder) }

        func readTag(_ key: String) -> String? {
            key.withCString { SBFLACTag(decoder, $0).map(String.init(cString:)) }
        }

        #expect(readTag("TITLE") == "Test Title")
        #expect(readTag("ARTIST") == "Test Artist")
        #expect(readTag("ALBUM") == "Test Album")
        #expect(readTag("ALBUMARTIST") == "Test Album Artist")
        #expect(readTag("GENRE") == "Rock")
        #expect(readTag("COMPOSER") == "Test Composer")
        #expect(readTag("COMMENT") == "A comment")
        #expect(readTag("DATE") == "2025")
        #expect(readTag("TRACKNUMBER") == "3")
        #expect(readTag("TRACKTOTAL") == "12")
        #expect(readTag("DISCNUMBER") == "1")
        #expect(readTag("DISCTOTAL") == "2")
        #expect(readTag("BPM") == "120")
    }

    @Test("FLAC artwork is written and readable")
    func flacArtworkWritten() async throws {
        let temp = try copyFixture("tone-44100-stereo-24", extension: "flac")
        defer { try? FileManager.default.removeItem(at: temp) }

        let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
                             0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01,
                             0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9])

        try await TagWriterService.writeTags(
            path: temp.path,
            fields: [.title: .text("With Art")],
            artworkData: jpegData
        )

        guard let decoder = temp.path.withCString({ SBFLACOpen($0) }) else {
            Issue.record("Failed to re-open FLAC file after writing artwork")
            return
        }
        defer { SBFLACClose(decoder) }

        var size: size_t = 0
        let artworkPtr = SBFLACArtwork(decoder, &size)
        #expect(artworkPtr != nil)
        #expect(size == jpegData.count)
    }

    @Test("Number pair packing produces correct 16-byte format")
    func numberPairPacking() {
        // Track 3 of 12
        let data = TagWriterService.packNumberPair(number: 3, total: 12)
        #expect(data.count == 16)
        let bytes = [UInt8](data)
        #expect(bytes[0] == 0 && bytes[1] == 0)     // reserved
        #expect(bytes[2] == 0 && bytes[3] == 3)     // number = 3
        #expect(bytes[4] == 0 && bytes[5] == 12)    // total = 12
        // Remaining bytes are zero
        for i in 6..<16 { #expect(bytes[i] == 0) }
    }

    @Test("Rating and favorite fields are skipped for FLAC")
    func ratingAndFavoriteSkipped() async throws {
        let temp = try copyFixture("tone-44100-stereo-24", extension: "flac")
        defer { try? FileManager.default.removeItem(at: temp) }

        // Write only rating + favorite — no text tags should change
        try await TagWriterService.writeTags(
            path: temp.path,
            fields: [
                .rating: .number(5),
                .favorite: .flag(true),
            ]
        )

        // File should still be valid and readable
        guard let decoder = temp.path.withCString({ SBFLACOpen($0) }) else {
            Issue.record("FLAC file corrupted after writing only rating/favorite")
            return
        }
        SBFLACClose(decoder)
    }

    @Test("Missing file throws error")
    func missingFileThrows() async {
        await #expect(throws: (any Error).self) {
            try await TagWriterService.writeTags(
                path: "/nonexistent/path/file.flac",
                fields: [.title: .text("test")]
            )
        }
    }

    // MARK: - Helpers

    private func copyFixture(_ name: String, extension ext: String) throws -> URL {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/\(name).\(ext)")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw NSError(domain: "TagWriterServiceTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Fixture \(name).\(ext) not found at \(source.path)"])
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dest = tempDir.appendingPathComponent("\(name).\(ext)")
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }
}
