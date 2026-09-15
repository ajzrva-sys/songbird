import Foundation
@testable import SongbirdLib

actor GatedDiscogsCDClient: DiscogsCDSearching {
    let client: DiscogsClient
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    var hasPendingRelease: Bool { continuation != nil }
    init(client: DiscogsClient) { self.client = client }
    func search(_ query: DiscogsArtworkSearchQuery, page: Int) async throws -> DiscogsSearchPage {
        try await client.search(query, page: page)
    }
    func releaseMetadata(id: Int) async throws -> DiscogsReleaseMetadata {
        let value = try await client.releaseMetadata(id: id)
        if !released { await withCheckedContinuation { continuation = $0 } }
        return value
    }
    func resume() { released = true; continuation?.resume(); continuation = nil }
}
