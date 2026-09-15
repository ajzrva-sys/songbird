import XCTest
@testable import SongbirdLib

final class DiscogsTypesTests: XCTestCase {
    func testUnstampedLegacyCandidateCannotDecode() {
        let payload = Data(#"{"id":42,"title":"Album","artist":"Artist","formats":[],"genres":[],"styles":[],"imageURL":"https://example.invalid/image","sourcePageURL":"https://www.discogs.com/release/42"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(DiscogsArtworkCandidate.self, from: payload))
    }

    func testSearchResponseDecodesStringYear() throws {
        let payload = """
        {
          "pagination": { "page": 1, "pages": 3 },
          "results": [{
            "id": 123,
            "title": "Artist - Album",
            "year": "1974",
            "country": "US",
            "format": ["LP"],
            "thumb": "https://example.com/thumb.jpg",
            "cover_image": "https://example.com/cover.jpg",
            "resource_url": "/releases/123"
          }]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DiscogsSearchResponse.self, from: payload)

        XCTAssertEqual(response.results?.first?.year, 1974)
        XCTAssertEqual(response.pagination?.pages, 3)
    }

    func testSearchResponseStillDecodesNumericYear() throws {
        let payload = """
        {
          "results": [{ "id": 456, "year": 1982 }]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DiscogsSearchResponse.self, from: payload)

        XCTAssertEqual(response.results?.first?.year, 1982)
    }
}
