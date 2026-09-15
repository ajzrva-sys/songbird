import XCTest

@testable import SongbirdLib

final class DiscogsFreshnessTests: XCTestCase {
    func testMixedAgeEvidenceRetainsOldestContributingLimit() {
        let evidence = DiscogsContentEvidence(
            releaseID: 42, fetches: [stamp(), stamp(18_999, 18_099)])
        XCTAssertFalse(evidence.isFresh(at: stamp(19_000, 18_100)))
    }
    func testProductionClockSamplesSameBootContinuousTime() throws {
        let first = try XCTUnwrap(DiscogsClock.sample())
        let second = try XCTUnwrap(DiscogsClock.sample())
        XCTAssertFalse(first.bootID.isEmpty)
        XCTAssertTrue(first.continuousSeconds.isFinite)
        XCTAssertGreaterThanOrEqual(second.continuousSeconds, first.continuousSeconds)
        XCTAssertEqual(first.bootID, second.bootID)
        XCTAssertTrue(DiscogsFreshness.isFresh(first, at: second))
    }

    func testNonpositiveReleaseEvidenceFailsClosed() {
        for id in [0, -1] {
            let evidence = DiscogsContentEvidence(releaseID: id, fetches: [stamp()])
            XCTAssertFalse(evidence.isFresh(at: stamp()))
            XCTAssertNil(evidence.sourcePageURL)
        }
    }

    func testEmptyEvidenceFailsClosed() {
        XCTAssertFalse(DiscogsContentEvidence(releaseID: 42, fetches: []).isFresh(at: stamp()))
    }

    func testEvidenceCarriesCanonicalSourceAndOriginalFetches() throws {
        let evidence = DiscogsContentEvidence(releaseID: 42, fetches: [stamp(), stamp(1_001, 101)])
        XCTAssertEqual(evidence.sourcePageURL?.absoluteString, "https://www.discogs.com/release/42")
        XCTAssertTrue(evidence.isFresh(at: stamp(1_002, 102)))
        XCTAssertEqual(
            try JSONDecoder().decode(
                DiscogsContentEvidence.self,
                from: JSONEncoder().encode(evidence)), evidence)
    }

    func testBoundaryMissingClockAndNonfiniteClocksFailClosed() {
        XCTAssertFalse(DiscogsFreshness.isFresh(stamp(), at: stamp(1_060, 160), maximumAge: 60))
        XCTAssertFalse(DiscogsFreshness.isFresh(nil, at: stamp()))
        XCTAssertFalse(DiscogsFreshness.isFresh(stamp(), at: nil))
        XCTAssertFalse(DiscogsFreshness.isFresh(stamp(), at: stamp(1_001, .infinity)))
        XCTAssertFalse(DiscogsFreshness.isFresh(stamp(), at: stamp(1_001, .nan)))
        XCTAssertFalse(DiscogsFreshness.isFresh(stamp(), at: stamp(.infinity, 101)))
        XCTAssertFalse(DiscogsFreshness.isFresh(stamp(), at: stamp(), maximumAge: 0))
        XCTAssertFalse(DiscogsFreshness.isFresh(stamp(), at: stamp(), maximumAge: -1))
        XCTAssertFalse(DiscogsFreshness.isFresh(stamp(), at: stamp(), maximumAge: .nan))
    }

    func testNonfiniteLimitFailsClosed() {
        XCTAssertFalse(
            DiscogsFreshness.isFresh(stamp(), at: stamp(1_001, 101), maximumAge: .infinity))
    }
    func testConfiguredLifetimeCannotExceedFiveHours() {
        XCTAssertFalse(
            DiscogsFreshness.isFresh(
                stamp(), at: stamp(19_000, 18_100), maximumAge: 30 * 24 * 60 * 60))
    }
    func testEmptyBootFailsClosed() {
        XCTAssertFalse(
            DiscogsFreshness.isFresh(stamp(1_000, 100, boot: ""), at: stamp(1_001, 101, boot: "")))
    }
    func testChangedBootFailsClosed() {
        XCTAssertFalse(DiscogsFreshness.isFresh(stamp(), at: stamp(1_001, 101, boot: "boot-B")))
    }
    func testFutureContinuousFailsClosed() {
        XCTAssertFalse(DiscogsFreshness.isFresh(stamp(), at: stamp(1_001, 99)))
    }
    func testSleepInclusiveClockExpiry() {
        XCTAssertFalse(DiscogsFreshness.isFresh(stamp(), at: stamp(1_010, 160), maximumAge: 60))
    }
    func testFutureWallFailsClosed() {
        XCTAssertFalse(DiscogsFreshness.isFresh(stamp(), at: stamp(999, 101)))
    }
    private func stamp(
        _ wall: TimeInterval = 1_000, _ continuous: TimeInterval = 100,
        boot: String = "boot-A"
    ) -> DiscogsFetchStamp {
        DiscogsFetchStamp(
            wall: Date(timeIntervalSince1970: wall), continuousSeconds: continuous, bootID: boot)
    }
    func testFreshBeforeBoundary() {
        XCTAssertTrue(DiscogsFreshness.isFresh(stamp(), at: stamp(1_059, 159), maximumAge: 60))
    }
}
