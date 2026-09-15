import XCTest
import SwiftData
@testable import SongbirdLib

@MainActor
final class DiscogsReviewFreshnessTests: XCTestCase {
    struct Item: Identifiable {
        let id: Int
        let evidence: DiscogsContentEvidence
    }
    func testFirstResultExpiresDuringLaterSearchAndNeedsExplicitRestart() async {
        let clock = TestDiscogsClock()
        let state = DiscogsReviewState<Item>(clock: { clock.sample() }, evidence: { [$0.evidence] })
        let generation = state.beginSearch()
        let early = Item(id: 1, evidence: DiscogsContentEvidence(releaseID: 1, fetches: [TestDiscogsClock.stamp()]))
        // A canned later search crosses the lifetime of the earlier acquisition.
        let later = await Task { @MainActor in
            clock.set(TestDiscogsClock.stamp(18_000))
            return Item(id: 2, evidence: DiscogsContentEvidence(releaseID: 2, fetches: [TestDiscogsClock.stamp(18_000)]))
        }.value
        XCTAssertFalse(state.publish([early, later], generation: generation))
        XCTAssertEqual(state.items.map(\.id), [2])
        XCTAssertTrue(state.requiresSearch)
        XCTAssertNil(state.selectedID)
        let freshGeneration = state.beginSearch()
        XCTAssertNotEqual(freshGeneration, generation)
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertFalse(state.requiresSearch)
        XCTAssertTrue(state.publish([later], generation: freshGeneration))
        XCTAssertFalse(state.publish([early], generation: generation))
        XCTAssertEqual(state.items.map(\.id), [2])
    }

    func testExpiryKeepsCurrentAlbumIndexAndSelectionCannotReuseExpiredContent() {
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(1)])
        let state = DiscogsReviewState<Item>(clock: { clock.sample() }, evidence: { [$0.evidence] })
        let values = [0.0, 1.0, 1.0].enumerated().map { index, offset in
            Item(id: index, evidence: DiscogsContentEvidence(releaseID: index + 1, fetches: [TestDiscogsClock.stamp(offset)]))
        }
        state.publish(values, generation: state.beginSearch())
        XCTAssertEqual(state.now, TestDiscogsClock.stamp(1))
        state.reviewIndex = 1
        clock.set(TestDiscogsClock.stamp(18_000))
        state.expire(at: clock.sample())
        XCTAssertEqual(state.reviewIndex, 0)
        XCTAssertEqual(state.items[state.reviewIndex].id, 1)
        XCTAssertEqual(state.now, TestDiscogsClock.stamp(18_000))
        state.select(id: 1)
        XCTAssertNil(state.selectedID, "An expired surface requires explicit search before any selection")
    }

    func testCompletedReviewDropsTransientCandidatesWithoutExpiringSavedWork() {
        let state = DiscogsReviewState<Item>(clock: { TestDiscogsClock.stamp() }, evidence: { [$0.evidence] })
        state.publish([Item(id: 1, evidence: DiscogsContentEvidence(releaseID: 1, fetches: [TestDiscogsClock.stamp()]))], generation: state.beginSearch())
        state.select(id: 1)
        XCTAssertTrue(state.advance())
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertNil(state.selectedID)
        XCTAssertFalse(state.expire(at: TestDiscogsClock.stamp(18_000)))
        XCTAssertFalse(state.requiresSearch)
    }

    func testTickClearsSelectionCancelsTaskAndInvalidatesLatePublication() async {
        let clock = TestDiscogsClock()
        let state = DiscogsReviewState<Item>(clock: { clock.sample() }, evidence: { [$0.evidence] })
        let album = Album(title: "Local search title", artist: "Local artist")
        let target = DiscogsArtworkAlbumTarget(album: album)
        let generation = state.beginSearch(targets: [target])
        let item = Item(id: 1, evidence: DiscogsContentEvidence(releaseID: 1, fetches: [TestDiscogsClock.stamp()]))
        XCTAssertTrue(state.publish([item], generation: generation))
        state.select(id: 1)
        let task = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
        state.task = task
        clock.set(TestDiscogsClock.stamp(18_000))
        XCTAssertTrue(state.expire(at: clock.sample()))
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertNil(state.selectedID)
        XCTAssertTrue(task.isCancelled)
        XCTAssertNotEqual(state.generation, generation)
        XCTAssertEqual(state.targets, [target])
        XCTAssertTrue(state.requiresSearch)
        XCTAssertFalse(state.publish([item], generation: generation))
    }
}
