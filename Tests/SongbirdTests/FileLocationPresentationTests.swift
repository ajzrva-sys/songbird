import XCTest
@testable import SongbirdLib

final class FileLocationPresentationTests: XCTestCase {
    func testFilePathColumnIsSupportedAndLabeled() {
        XCTAssertTrue(TrackSortColumn.filePath.isSupported)
        XCTAssertEqual(TrackSortColumn.filePath.label, "Location")
        XCTAssertTrue(TrackSortColumn.supportedCases.contains(.filePath))
        XCTAssertEqual(TrackTableColumnPrefs.defaultWidth(for: .filePath), 220)
        XCTAssertLessThanOrEqual(
            TrackTableColumnPrefs.minimumWidth(for: .filePath),
            TrackTableColumnPrefs.defaultWidth(for: .filePath)
        )
        XCTAssertTrue(
            TrackTableColumnPrefs.defaults.contains { $0.id == TrackSortColumn.filePath.rawValue }
        )
    }

    func testDisplayValuesIncludeFullPath() {
        let track = LibraryTrackSnapshot(
            persistentIdentifier: Track(path: "/Music/Album/01 Song.flac").persistentModelID,
            title: "Song",
            path: "/Music/Album/01 Song.flac"
        )
        let values = TrackTableDisplayValues(track: track, columns: [.filePath, .title])
        XCTAssertEqual(values.text(for: .filePath), "/Music/Album/01 Song.flac")
    }

    func testFileNotFoundErrorNamesLocation() {
        let path = "/Volumes/Music/missing.m4a"
        XCTAssertEqual(
            PlaybackStartError.fileNotFound(path).userFacingMessage,
            "File not found: \(path)"
        )
    }

    @MainActor
    func testTrackInfoTargetCarriesPath() {
        let track = Track(path: "/Music/Album/01 Song.flac", title: "Song")
        let target = TrackInfoTarget(track: track)
        XCTAssertEqual(target.path, track.path)
    }
}
