import XCTest

@testable import SongbirdLib

@MainActor
final class DiscogsConsumerEvidenceTests: XCTestCase {
    func testYearResultRetainsOriginalEvidence() {
        let album = Album(title: "Album")
        let result = MissingYearView.SearchResult(
            album: album, year: candidate.year!, source: "cached", evidence: candidate.evidence)
        XCTAssertEqual(result.evidence, candidate.evidence)
    }

    private var candidate: DiscogsArtworkCandidate {
        DiscogsArtworkCandidate(
            id: 42, title: "Album", artist: "Artist", year: 2001,
            country: nil, formats: [], genres: ["Jazz"], styles: [], thumbnailURL: nil,
            imageURL: URL(string: "https://example.invalid/image")!,
            sourcePageURL: URL(string: "https://www.discogs.com/release/42")!,
            fetchedAt: TestDiscogsClock.stamp())
    }
    func testGenreConversionRetainsOriginalEvidence() throws {
        let converted = try XCTUnwrap(
            DiscogsGenreReviewView.genreCandidates(from: [candidate]).first)
        XCTAssertEqual(converted.evidence, candidate.evidence)
    }
}
