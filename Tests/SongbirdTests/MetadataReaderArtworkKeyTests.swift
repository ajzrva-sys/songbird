import XCTest
@testable import SongbirdLib

final class MetadataReaderArtworkKeyTests: XCTestCase {
    func testRecognizesCommonEmbeddedArtworkKeys() {
        XCTAssertTrue(MetadataReader.isArtworkKey(
            raw: "itsk/com.apple.itunes.artwork",
            common: "artwork",
            keyDescription: "",
            joined: "itsk/com.apple.itunes.artwork  "
        ))
        XCTAssertTrue(MetadataReader.isArtworkKey(
            raw: "mdta/com.apple.quicktime.artwork",
            common: "",
            keyDescription: "artwork",
            joined: "mdta/com.apple.quicktime.artwork  artwork"
        ))
        XCTAssertTrue(MetadataReader.isArtworkKey(
            raw: "",
            common: "",
            keyDescription: "covr",
            joined: "  covr"
        ))
        XCTAssertTrue(MetadataReader.isArtworkKey(
            raw: "",
            common: "",
            keyDescription: "Cover",
            joined: "  cover"
        ))
        XCTAssertTrue(MetadataReader.isArtworkKey(
            raw: "id3/%00PIC",
            common: "",
            keyDescription: "",
            joined: "id3/%00pic"
        ))
        XCTAssertTrue(MetadataReader.isArtworkKey(
            raw: "org.id3.APIC",
            common: "",
            keyDescription: "APIC",
            joined: "org.id3.apic  apic"
        ))
    }

    func testDoesNotMatchOrdinaryTitleKeys() {
        XCTAssertFalse(MetadataReader.isArtworkKey(
            raw: "itsk/com.apple.itunes.title",
            common: "title",
            keyDescription: "©nam",
            joined: "itsk/com.apple.itunes.title title ©nam"
        ))
        XCTAssertFalse(MetadataReader.isArtworkKey(
            raw: "",
            common: "",
            keyDescription: "Cover Me Softly",
            joined: "  cover me softly"
        ))
    }
}
