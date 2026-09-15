import XCTest
@testable import SongbirdLib

final class LegalResourcesTests: XCTestCase {
    func testRealSwiftPMResourcesEqualCanonicalDocuments() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let originals: [LegalDocument: String] = [
            .license: "LICENSE", .notice: "NOTICE.txt",
            .thirdParty: "THIRD_PARTY_NOTICES.txt", .source: "SOURCE_CODE.md"
        ]
        for document in LegalDocument.allCases {
            let text = try? LegalResources.read(document)
            XCTAssertNotNil(text, "Missing real SwiftPM legal resource: " + document.rawValue)
            if let text {
                let original = try String(contentsOf: root.appendingPathComponent(originals[document]!), encoding: .utf8)
                XCTAssertEqual(text, original, document.rawValue)
                XCTAssertFalse(text.isEmpty)
            }
        }
    }

    func testPackagedTextWinsWithoutDevelopmentLookup() throws {
        let value = try LegalResources.resolve(
            packagedApplication: true,
            packaged: { "packaged" },
            development: {
                XCTFail("Development resource accessor must remain lazy")
                return "development"
            }
        )
        XCTAssertEqual(value, "packaged")
    }

    func testIncompleteAppNeverUsesDevelopmentFallback() {
        XCTAssertThrowsError(try LegalResources.resolve(
            packagedApplication: true,
            packaged: { nil },
            development: {
                XCTFail("Incomplete app must not consult .build")
                return "development"
            }
        ))
    }

    func testDevelopmentFallbackRejectsMissingOrEmptyText() throws {
        XCTAssertEqual(try LegalResources.resolve(
            packagedApplication: false,
            packaged: { nil },
            development: { "development" }
        ), "development")
        for text: String? in [nil, "", " \n\t"] {
            XCTAssertThrowsError(try LegalResources.resolve(
                packagedApplication: false,
                packaged: { nil },
                development: { text }
            ))
        }
    }

    func testEmptyPackagedTextDoesNotUseDevelopmentFallback() {
        for packagedApplication in [true, false] {
            XCTAssertThrowsError(try LegalResources.resolve(
                packagedApplication: packagedApplication,
                packaged: { " \n" },
                development: {
                    XCTFail("Empty packaged text must not be hidden by development resources")
                    return "development"
                }
            ))
        }
    }

    func testUnreadablePackagedTextDoesNotUseDevelopmentFallback() {
        struct Unreadable: Error {}
        for packagedApplication in [true, false] {
            XCTAssertThrowsError(try LegalResources.resolve(
                packagedApplication: packagedApplication,
                packaged: { throw Unreadable() },
                development: {
                    XCTFail("Unreadable packaged text must not consult development resources")
                    return "development"
                }
            )) { error in
                XCTAssertTrue(error is Unreadable)
            }
        }
    }

    func testUnreadableDevelopmentTextIsAnError() {
        struct Unreadable: Error {}
        XCTAssertThrowsError(try LegalResources.resolve(
            packagedApplication: false,
            packaged: { nil },
            development: { throw Unreadable() }
        )) { error in
            XCTAssertTrue(error is Unreadable)
        }
    }
}
