import XCTest
@testable import SongbirdLib

final class DiscogsReviewDependenciesTests: XCTestCase {
    func testInjectedSearchRejectsAReplyThatExpiresAcrossAwait() async throws {
        let clock = TestDiscogsClock()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let dependencies = DiscogsReviewDependencies(client: Canned(clock: clock),
            cacheURL: root.appendingPathComponent("cache.json"), clock: { clock.sample() })
        do {
            _ = try await dependencies.search(.init(albumTitle: "Synthetic", albumArtist: "Artist"), page: 1)
            XCTFail("A canned late reply must obey the same acquisition boundary")
        } catch { XCTAssertEqual(error as? LibraryHealthMutationError, .remoteEvidenceExpired) }
    }
    func testCacheHitExpiresAcrossActorReturn() async throws {
        let clock = TestDiscogsClock()
        let dependencies = DiscogsReviewDependencies(client: Canned(clock: clock), cache: DelayedCache(clock: clock), clock: { clock.sample() })
        do {
            _ = try await dependencies.cachedCandidates(for: .init(albumTitle: "Synthetic", albumArtist: "Artist"))
            XCTFail("Cache-return evidence must be checked on the consuming actor")
        } catch { XCTAssertEqual(error as? LibraryHealthMutationError, .remoteEvidenceExpired) }
    }
    func testStoreCompletionCannotRenewAcquisition() async throws {
        let clock = TestDiscogsClock()
        let cache = DelayedCache(clock: clock)
        let dependencies = DiscogsReviewDependencies(client: Canned(clock: clock), cache: cache, clock: { clock.sample() })
        do {
            try await dependencies.storeCandidates([], for: .init(albumTitle: "Synthetic", albumArtist: "Artist"), fetches: [TestDiscogsClock.stamp()])
            XCTFail("A store completing after expiry must refuse publication")
        } catch { XCTAssertEqual(error as? LibraryHealthMutationError, .remoteEvidenceExpired) }
        let fetches = await cache.storedFetches
        XCTAssertEqual(fetches, [TestDiscogsClock.stamp()])
    }
    private actor DelayedCache: DiscogsReviewCaching {
        let clock: TestDiscogsClock
        var storedFetches: [DiscogsFetchStamp] = []
        init(clock: TestDiscogsClock) { self.clock = clock }
        func candidates(for query: DiscogsArtworkSearchQuery) async -> DiscogsArtworkSearchCache.Hit? {
            await Task.yield()
            clock.set(TestDiscogsClock.stamp(18_000))
            return DiscogsArtworkSearchCache.Hit(value: [], fetches: [TestDiscogsClock.stamp()])
        }
        func store(_ candidates: [DiscogsArtworkCandidate], for query: DiscogsArtworkSearchQuery,
            fetches: [DiscogsFetchStamp]) async -> Bool {
                storedFetches = fetches
                await Task.yield()
                clock.set(TestDiscogsClock.stamp(18_000))
                return true
            }
    }
    func testClientFreshnessFailuresUseTypedReviewExpiry() async throws {
        struct Rejected: DiscogsReviewClient {
            let error: DiscogsError
            func search(_ query: DiscogsArtworkSearchQuery, page: Int) async throws -> DiscogsSearchPage { throw error }
            func downloadImage(from url: URL, evidence: DiscogsContentEvidence) async throws -> Data { throw error }
        }
        for error in [DiscogsError.resultsExpired, DiscogsError.freshnessUnavailable] {
            let clock = TestDiscogsClock()
            let dependencies = DiscogsReviewDependencies(client: Rejected(error: error), cache: DelayedCache(clock: clock), clock: { clock.sample() })
            do {
                _ = try await dependencies.search(.init(albumTitle: "Synthetic", albumArtist: "Artist"), page: 1)
                XCTFail("Expected rejection")
            } catch { XCTAssertEqual(error as? LibraryHealthMutationError, .remoteEvidenceExpired) }
        }
    }
    private struct Canned: DiscogsReviewClient {
        let clock: TestDiscogsClock
        func search(_ query: DiscogsArtworkSearchQuery, page: Int) async throws -> DiscogsSearchPage {
            await Task.yield()
            clock.set(TestDiscogsClock.stamp(18_000))
            return DiscogsSearchPage(candidates: [], page: page, totalPages: 1, fetchedAt: TestDiscogsClock.stamp())
        }
        func downloadImage(from url: URL, evidence: DiscogsContentEvidence) async throws -> Data {
            throw DiscogsError.imageDownloadFailed
        }
    }
}
