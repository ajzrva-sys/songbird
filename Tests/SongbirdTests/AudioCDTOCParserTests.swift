import XCTest
@testable import SongbirdLib

final class AudioCDTOCParserTests: XCTestCase {
    func testParsesAudioTracksAtSeventyFiveSectorsPerSecond() {
        let tracks = AudioCDTOCParser.parse(
            entries: [
                .init(number: 1, startSector: 150),
                .init(number: 2, startSector: 4_650),
            ],
            leadOutSector: 9_150
        )

        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks[0].duration, 60, accuracy: 0.001)
        XCTAssertEqual(tracks[1].duration, 60, accuracy: 0.001)
    }

    func testMixedModeDiscExcludesDataTracksButUsesTheirBoundary() {
        let tracks = AudioCDTOCParser.parse(
            entries: [
                .init(number: 1, startSector: 150),
                .init(number: 2, startSector: 4_650, isData: true),
                .init(number: 3, startSector: 9_150),
            ],
            leadOutSector: 13_650
        )

        XCTAssertEqual(tracks.map(\.number), [1, 3])
        XCTAssertEqual(tracks[0].endSector, 4_650)
        XCTAssertEqual(tracks[1].endSector, 13_650)
    }

    func testRejectsMalformedAndMissingLeadOut() {
        XCTAssertTrue(AudioCDTOCParser.parse(
            entries: [.init(number: 1, startSector: 150)],
            leadOutSector: 0
        ).isEmpty)

        XCTAssertTrue(AudioCDTOCParser.parse(
            entries: [.init(number: 1, startSector: 500)],
            leadOutSector: 400
        ).isEmpty)
    }

    func testSortsSessionEntriesAndIgnoresLeadOutDescriptors() {
        let tracks = AudioCDTOCParser.parse(
            entries: [
                .init(number: 2, startSector: 4_650),
                .init(number: 0xAA, startSector: 9_150),
                .init(number: 1, startSector: 150),
            ],
            leadOutSector: 9_150
        )

        XCTAssertEqual(tracks.map(\.number), [1, 2])
    }
}
