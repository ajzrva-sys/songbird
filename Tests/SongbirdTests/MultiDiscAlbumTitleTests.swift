import XCTest
@testable import SongbirdLib

final class MultiDiscAlbumTitleTests: XCTestCase {
    func testParsesCommonDiscSuffixes() {
        XCTAssertEqual(
            MultiDiscAlbumTitle.parse("Cesar Franck Edition - CD11"),
            MultiDiscAlbumTitle(baseTitle: "Cesar Franck Edition", discNumber: 11)
        )
        XCTAssertEqual(
            MultiDiscAlbumTitle.parse("Box Set Disc 02"),
            MultiDiscAlbumTitle(baseTitle: "Box Set", discNumber: 2)
        )
        XCTAssertEqual(
            MultiDiscAlbumTitle.parse("Collection — Disk 3"),
            MultiDiscAlbumTitle(baseTitle: "Collection", discNumber: 3)
        )
    }

    func testDoesNotAlterOrdinaryAlbumTitles() {
        XCTAssertNil(MultiDiscAlbumTitle.parse("Compact Disc"))
        XCTAssertNil(MultiDiscAlbumTitle.parse("CD1"))
        XCTAssertNil(MultiDiscAlbumTitle.parse("Volume 2"))
    }

    func testParsesNumberedVolumeWithDescriptiveSuffix() {
        XCTAssertEqual(
            MultiDiscAlbumTitle.parse(
                "Coleção Folha: Raízes da Música Popular Brasileira, Volume 10: Luiz Gonzaga"
            ),
            MultiDiscAlbumTitle(
                baseTitle: "Coleção Folha: Raízes da Música Popular Brasileira",
                discNumber: 10
            )
        )
    }

    func testInfersDiscFromPathAndRemovesMatchingEditionYear() {
        XCTAssertEqual(
            MultiDiscAlbumTitle.infer(
                title: "Cesar Franck Edition - 2019",
                year: 2019,
                trackPaths: ["/Music/Cesar Franck/CD09 - Fantaisies/01.flac"]
            ),
            MultiDiscAlbumTitle(baseTitle: "Cesar Franck Edition", discNumber: 9)
        )
    }

    func testDoesNotRemoveNonmatchingNumericTitleSuffix() {
        XCTAssertEqual(
            MultiDiscAlbumTitle.infer(
                title: "Collection - 1967",
                year: 2019,
                trackPaths: ["/Music/Collection/CD02/01.flac"]
            ),
            MultiDiscAlbumTitle(baseTitle: "Collection - 1967", discNumber: 2)
        )
    }

    func testInfersRomanNumeralVolumeFromAlbumTitle() {
        XCTAssertEqual(
            MultiDiscAlbumTitle.infer(
                title: "Couperin: Complete Works for Harpsichord,IX. 21e-24e Ordres",
                year: 2018,
                trackPaths: []
            ),
            MultiDiscAlbumTitle(
                baseTitle: "Couperin: Complete Works for Harpsichord",
                discNumber: 9
            )
        )
    }

    func testInfersDiscFromNumberedFolder() {
        XCTAssertEqual(
            MultiDiscAlbumTitle.discNumber(
                inPath: "/Music/Couperin/10 - X. 25e-27e Ordres/01.flac"
            ),
            10
        )
    }

    func testFindsSharedCollectionFolderFromDiscFolder() {
        let location = MultiDiscAlbumTitle.collectionFolder(
            inPath: "/Music/Composer/Complete Edition/Disc 02 - Concertos/FLAC/01.flac"
        )

        XCTAssertEqual(location?.path, "/Music/Composer/Complete Edition")
        XCTAssertEqual(location?.name, "Complete Edition")
        XCTAssertEqual(location?.discNumber, 2)
    }

    func testFindsDotSeparatedInternationalDiscFolder() {
        let location = MultiDiscAlbumTitle.collectionFolder(
            inPath: "/Music/Chinese Collection/CD17.汉宫秋月/FLAC/01.flac"
        )

        XCTAssertEqual(location?.path, "/Music/Chinese Collection")
        XCTAssertEqual(location?.name, "Chinese Collection")
        XCTAssertEqual(location?.discNumber, 17)
    }

    func testOrdinaryAlbumFolderIsNotTreatedAsCollection() {
        XCTAssertNil(
            MultiDiscAlbumTitle.collectionFolder(
                inPath: "/Music/Artist/Ordinary Album/01.flac"
            )
        )
    }
}
