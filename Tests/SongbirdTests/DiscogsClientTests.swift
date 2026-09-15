import Foundation
import XCTest

@testable import SongbirdLib

private final class DiscogsCanonicalFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: nil)!
        let results: [[String: Any]] = [
            ["id": 42, "resource_url": "https://api.discogs.com/releases/42"],
            ["id": 42, "resource_url": "/releases/42"],
            ["id": 42],
            ["id": 42, "resource_url": "https://unrelated.invalid/not-a-release"],
            ["id": 0], ["id": -1],
        ].map {
            $0.merging([
                "title": "Artist - Album", "cover_image": "https://example.invalid/cover.png",
            ]) { a, _ in a }
        }
        let payload = try! JSONSerialization.data(withJSONObject: ["results": results])
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class DiscogsClientTests: XCTestCase {
    func testSearchStatusAndTokenErrorsRemainTyped() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock()
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() }, tokenProvider: { "synthetic" })
        for status in [401, 403, 404, 429, 503] {
            do {
                _ = try await client.search(
                    .init(albumTitle: "status-" + String(status), albumArtist: ""), page: 1)
                XCTFail("Expected status failure")
            } catch DiscogsError.tokenInvalid {
                XCTAssertTrue([401, 403].contains(status))
            } catch DiscogsError.noResults {
                XCTAssertEqual(status, 404)
            } catch DiscogsError.rateLimited(let retry) {
                XCTAssertEqual(status, 429)
                XCTAssertEqual(retry, 7)
            } catch DiscogsError.serverUnavailable { XCTAssertEqual(status, 503) }
        }
        let failing = DiscogsClient(
            session: fixture.session, clock: { clock.sample() },
            tokenProvider: { throw DiscogsError.tokenMissing })
        do {
            _ = try await failing.search(.init(albumTitle: "Album", albumArtist: ""), page: 1)
            XCTFail("Token failure")
        } catch DiscogsError.tokenMissing {}
        XCTAssertEqual(try fixture.requests().count, 5)
    }
    func testMissingAcquisitionClockDoesNotStartRequests() async throws {
        let fixture = try DiscogsHTTPFixture()
        let client = DiscogsClient(
            session: fixture.session, clock: { nil }, tokenProvider: { "synthetic" })
        do {
            _ = try await client.search(.init(albumTitle: "empty", albumArtist: ""), page: 1)
            XCTFail("Clock required")
        } catch DiscogsError.freshnessUnavailable {}
        do {
            _ = try await client.releaseMetadata(id: 42)
            XCTFail("Clock required")
        } catch DiscogsError.freshnessUnavailable {}
        XCTAssertEqual(try fixture.requests().count, 0)
    }

    func testReleaseResponseCrossingExpiryIsNotPublished() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(), TestDiscogsClock.stamp(18_000)])
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() }, tokenProvider: { "synthetic" })
        do {
            _ = try await client.releaseMetadata(id: 42)
            XCTFail("Release response expired")
        } catch DiscogsError.resultsExpired {}
        XCTAssertEqual(try fixture.requests().count, 1)
    }

    func testSearchResponseCrossingExpiryIsNotPublished() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(), TestDiscogsClock.stamp(18_000)])
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() }, tokenProvider: { "synthetic" })
        do {
            _ = try await client.search(.init(albumTitle: "empty", albumArtist: ""), page: 1)
            XCTFail("An empty response must expire too")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Discogs results expired. Search again.")
        }
        XCTAssertEqual(try fixture.requests().count, 1)
    }

    func testDefaultSessionIsEphemeralAndHasNoURLCache() throws {
        let client = DiscogsClient(tokenProvider: { "synthetic" })
        let session = try XCTUnwrap(
            Mirror(reflecting: client).children.first { $0.label == "session" }?.value
                as? URLSession)
        XCTAssertFalse(session === URLSession.shared)
        XCTAssertNil(session.configuration.urlCache)
        XCTAssertEqual(session.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertFalse(session.configuration.httpCookieStorage === HTTPCookieStorage.shared)
        XCTAssertFalse(session.configuration.urlCredentialStorage === URLCredentialStorage.shared)
    }

    func testAllActualRequestsBypassURLCache() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock()
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() }, tokenProvider: { "synthetic" })
        _ = try await client.search(.init(albumTitle: "Album", albumArtist: "Artist"), page: 1)
        _ = try await client.releaseMetadata(id: 42)
        _ = try await client.downloadImage(
            from: URL(string: "https://example.invalid/image")!,
            evidence: .init(releaseID: 42, fetches: [TestDiscogsClock.stamp()]))
        let requests = try fixture.requests()
        XCTAssertEqual(requests.count, 3)
        for request in requests {
            XCTAssertEqual(request["cacheControl"], "no-cache")
            XCTAssertEqual(
                request["cachePolicy"],
                String(URLRequest.CachePolicy.reloadIgnoringLocalCacheData.rawValue))
        }
    }

    func testReleaseAcquisitionStampAndCanonicalSource() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock()
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() },
            tokenProvider: {
                clock.set(TestDiscogsClock.stamp(10))
                return "synthetic"
            })
        let release = try await client.releaseMetadata(id: 42)
        XCTAssertEqual(release.fetchedAt, TestDiscogsClock.stamp(10))
        XCTAssertEqual(release.evidence.fetches, [TestDiscogsClock.stamp(10)])
        XCTAssertEqual(release.sourcePageURL?.absoluteString, "https://www.discogs.com/release/42")
    }

    func testSearchAcquisitionStampSurvivesEmptyAndSlicedResponses() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock()
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() },
            tokenProvider: {
                clock.set(TestDiscogsClock.stamp(10))
                return "synthetic"
            })
        for title in ["Album", "empty"] {
            let page = try await client.search(
                .init(albumTitle: title, albumArtist: "Artist"), page: 1)
            XCTAssertEqual(page.fetchedAt, TestDiscogsClock.stamp(10))
            for candidate in page.candidates.prefix(5) {
                XCTAssertEqual(candidate.fetchedAt, page.fetchedAt)
                XCTAssertEqual(candidate.evidence.fetches, [page.fetchedAt])
            }
            XCTAssertEqual(page.candidates.count, title == "empty" ? 0 : 8)
        }
    }

    func testActualSearchBuildsHumanReleaseURLFromID() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscogsCanonicalFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let clock = TestDiscogsClock()
        let client = DiscogsClient(
            session: session, clock: { clock.sample() }, tokenProvider: { "synthetic-test-token" })
        let page = try await client.search(
            DiscogsArtworkSearchQuery(albumTitle: "Album", albumArtist: "Artist"), page: 1)
        XCTAssertEqual(page.candidates.count, 4)
        XCTAssertEqual(page.candidates.map(\.id), [42, 42, 42, 42])
        XCTAssertEqual(
            page.candidates.map { $0.sourcePageURL.absoluteString },
            Array(repeating: "https://www.discogs.com/release/42", count: 4))
    }
}
