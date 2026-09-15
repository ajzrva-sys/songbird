import Foundation
import Testing
@testable import SongbirdLib

struct DiscogsArtworkSuggestionPolicyTests {
    @Test("The first Discogs result supplies the artwork suggestion")
    func firstResultWins() {
        let first = candidate(id: 1)
        let second = candidate(id: 2)

        #expect(
            DiscogsArtworkSuggestionPolicy.suggestedCandidate(from: [first, second], at: TestDiscogsClock.stamp()) == first
        )
        #expect(DiscogsArtworkSuggestionPolicy.suggestedCandidate(from: [], at: TestDiscogsClock.stamp()) == nil)
    }

    @Test("An expired first release is not silently replaced by another suggestion")
    func expiredFirstIsNotPromoted() {
        let first = candidate(id: 1)
        let later = candidate(id: 2, at: 1)
        #expect(DiscogsArtworkSuggestionPolicy.suggestedCandidate(
            from: [first, later], at: TestDiscogsClock.stamp(18_000)) == nil)
    }

    private func candidate(id: Int, at time: Double = 0) -> DiscogsArtworkCandidate {
        DiscogsArtworkCandidate(
            id: id,
            title: "Artist - Album \(id)",
            artist: "Artist",
            year: 2026,
            country: nil,
            formats: ["Album"],
            genres: ["Electronic"],
            styles: [],
            thumbnailURL: nil,
            imageURL: URL(string: "https://example.com/cover-\(id).jpg")!,
            sourcePageURL: URL(string: "https://example.com/release-\(id)")!,
            fetchedAt: TestDiscogsClock.stamp(time)
        )
    }

}
