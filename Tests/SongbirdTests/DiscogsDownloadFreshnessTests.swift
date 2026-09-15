import XCTest

@testable import SongbirdLib

final class DiscogsDownloadFreshnessTests: XCTestCase {
    func testClockLostWhileAwaitingImageDoesNotRetry() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(), nil])
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() },
            sleep: { _ in XCTFail("No freshness retry") }, tokenProvider: { "synthetic" })
        do {
            _ = try await client.downloadImage(from: imageURL, evidence: evidence)
            XCTFail("Clock lost")
        } catch DiscogsError.freshnessUnavailable {}
        XCTAssertEqual(try fixture.requests().count, 1)
    }
    func testMixedAgeEvidenceDoesNotChooseNewestStamp() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(18_000)])
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() }, tokenProvider: { "synthetic" })
        let mixed = DiscogsContentEvidence(
            releaseID: 42, fetches: [TestDiscogsClock.stamp(), TestDiscogsClock.stamp(17_999)])
        do {
            _ = try await client.downloadImage(from: imageURL, evidence: mixed)
            XCTFail("Oldest contributor expired")
        } catch DiscogsError.resultsExpired {}
        XCTAssertEqual(try fixture.requests().count, 0)
    }

    func testUnavailableClockAndEmptyEvidenceFailClosed() async throws {
        for fetches in [evidence.fetches, []] {
            let fixture = try DiscogsHTTPFixture()
            let clock = TestDiscogsClock(fetches.isEmpty ? [TestDiscogsClock.stamp()] : [nil])
            let client = DiscogsClient(
                session: fixture.session, clock: { clock.sample() }, tokenProvider: { "synthetic" })
            do {
                _ = try await client.downloadImage(
                    from: imageURL, evidence: .init(releaseID: 42, fetches: fetches))
                XCTFail("Missing freshness")
            } catch DiscogsError.freshnessUnavailable {
                XCTAssertFalse(fetches.isEmpty)
            } catch DiscogsError.resultsExpired { XCTAssertTrue(fetches.isEmpty) }
            XCTAssertEqual(try fixture.requests().count, 0)
        }
        XCTAssertEqual(
            DiscogsError.resultsExpired.localizedDescription,
            "Discogs results expired. Search again.")
        XCTAssertEqual(
            DiscogsError.freshnessUnavailable.localizedDescription,
            "Discogs freshness could not be verified. Try again.")
    }
    func testFreshImagesKeepOriginalEvidenceAndTransportRetryCount() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(30)])
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() }, sleep: { _ in },
            tokenProvider: { "synthetic" })
        let bytes = try await client.downloadImage(from: imageURL, evidence: evidence)
        XCTAssertEqual(bytes, Data([1, 2, 3]))
        XCTAssertEqual(evidence.fetches, [TestDiscogsClock.stamp()])
        do {
            _ = try await client.downloadImage(
                from: URL(string: "https://example.invalid/rate")!, evidence: evidence)
            XCTFail("Expected rate limiting")
        } catch DiscogsError.rateLimited(let retry) { XCTAssertEqual(retry, 7) }
        XCTAssertEqual(try fixture.requests().count, 4)
    }

    func testExpiryImmediatelyBeforeReturningBytesFailsClosed() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock([
            TestDiscogsClock.stamp(), TestDiscogsClock.stamp(), TestDiscogsClock.stamp(18_000),
        ])
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() }, tokenProvider: { "synthetic" })
        do {
            _ = try await client.downloadImage(from: imageURL, evidence: evidence)
            XCTFail("Final byte publication expired")
        } catch DiscogsError.resultsExpired {}
        XCTAssertEqual(try fixture.requests().count, 1)
    }

    func testFailedTransportCrossingExpiryDoesNotEnterBackoff() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(), TestDiscogsClock.stamp(18_000)])
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() },
            sleep: { _ in
                XCTFail("Expired content must not back off")
            }, tokenProvider: { "synthetic" })
        do {
            _ = try await client.downloadImage(
                from: URL(string: "https://example.invalid/transport-failure")!, evidence: evidence)
            XCTFail("Expired transport")
        } catch DiscogsError.resultsExpired {}
        XCTAssertEqual(try fixture.requests().count, 1)
    }

    func testNonpositiveReleaseEvidenceStartsZeroRequests() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock()
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() }, tokenProvider: { "synthetic" })
        do {
            _ = try await client.downloadImage(
                from: imageURL, evidence: .init(releaseID: 0, fetches: evidence.fetches))
            XCTFail("Invalid release evidence")
        } catch DiscogsError.resultsExpired {}
        XCTAssertEqual(try fixture.requests().count, 0)
    }

    func testExpiryDuringRetryBackoffStartsNoSecondRequest() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock()
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() },
            sleep: { _ in
                clock.set(TestDiscogsClock.stamp(18_000))
            }, tokenProvider: { "synthetic" })
        do {
            _ = try await client.downloadImage(
                from: URL(string: "https://example.invalid/retry")!, evidence: evidence)
            XCTFail("Backoff expired")
        } catch DiscogsError.resultsExpired {}
        XCTAssertEqual(try fixture.requests().count, 1)
    }
    func testCancellationDuringBackoffIsNotSwallowed() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock()
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() },
            sleep: { _ in
                throw CancellationError()
            }, tokenProvider: { "synthetic" })
        do {
            _ = try await client.downloadImage(
                from: URL(string: "https://example.invalid/retry")!, evidence: evidence)
            XCTFail("Cancellation swallowed")
        } catch is CancellationError {} catch {
            XCTFail("Wrong error: " + error.localizedDescription)
        }
        XCTAssertEqual(try fixture.requests().count, 1)
    }

    func testDelayedImageResponseCrossingExpiryReturnsNoBytesOrRetry() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(), TestDiscogsClock.stamp(18_000)])
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() }, tokenProvider: { "synthetic" })
        do {
            _ = try await client.downloadImage(
                from: URL(string: "https://example.invalid/delayed")!, evidence: evidence)
            XCTFail("Delayed bytes expired")
        } catch DiscogsError.resultsExpired {}
        XCTAssertEqual(try fixture.requests().count, 1)
    }

    private let imageURL = URL(string: "https://example.invalid/image")!
    private var evidence: DiscogsContentEvidence {
        DiscogsContentEvidence(releaseID: 42, fetches: [TestDiscogsClock.stamp()])
    }
    func testAlreadyExpiredEvidenceStartsZeroRequests() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(18_000)])
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() }, tokenProvider: { "synthetic" })
        do {
            _ = try await client.downloadImage(from: imageURL, evidence: evidence)
            XCTFail("Expired input")
        } catch DiscogsError.resultsExpired {}
        XCTAssertEqual(try fixture.requests().count, 0)
    }
}
