import XCTest
@testable import SongbirdLib

/// Structural integration guards supplement operation tests; not rendered/AX acceptance.
final class DiscogsReviewWiringTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private func source(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
    func testAttributionUsesExactLinkedWording() {
        let text = (try? source("Sources/Discogs/DiscogsAttributionView.swift")) ?? ""
        XCTAssertTrue(text.contains("Link(\"Data provided by Discogs.\", destination: sourcePageURL)"))
    }
    func testManualSurfaceUsesTestedOwnerAndApplication() throws {
        let text = try source("Sources/Discogs/DiscogsSearchView.swift")
        XCTAssertTrue(text.contains("DiscogsReviewState<DiscogsArtworkCandidate>"))
        XCTAssertEqual(text.components(separatedBy: "DiscogsFreshnessView(").count - 1, 1)
        XCTAssertTrue(text.contains("review.publish(page.candidates, generation:"))
        XCTAssertTrue(text.contains("review.expire(at: now)"))
        XCTAssertTrue(text.contains("DiscogsArtworkApplication.apply("))
        let clock = (try? source("Sources/Discogs/DiscogsFreshnessView.swift")) ?? ""
        XCTAssertTrue(clock.contains("NSApplication.didBecomeActiveNotification"))
        XCTAssertTrue(clock.contains("NSWorkspace.didWakeNotification"))
        XCTAssertTrue(clock.contains("Task.sleep"))
    }
    func testBulkSurfaceUsesOwnerAndAtomicApplication() throws {
        let text = try source("Sources/Discogs/DiscogsBulkReviewView.swift")
        XCTAssertTrue(text.contains("DiscogsReviewState<ReviewItem>"))
        XCTAssertEqual(text.components(separatedBy: "DiscogsFreshnessView(").count - 1, 1)
        XCTAssertTrue(text.contains("review.publish(items, generation:"))
        XCTAssertTrue(text.contains("review.expire(at: now)"))
        XCTAssertEqual(text.components(separatedBy: "DiscogsArtworkApplication.apply(").count - 1, 2)
        XCTAssertTrue(text.contains("DiscogsAttributionView(sourcePageURL: candidate.evidence.sourcePageURL)"))
    }
    func testGenreReviewUsesSharedActionsAndLoadedOwner() throws {
        let text = try source("Sources/Discogs/DiscogsGenreReviewView.swift")
        XCTAssertFalse(text.contains("modelContext.save()"))
        XCTAssertFalse(text.contains("DiscogsGenreBulkApplier.apply("))
        XCTAssertEqual(text.components(separatedBy: "actions.applyDiscogsGenres(").count - 1, 2)
        XCTAssertTrue(text.contains("DiscogsReviewState<ReviewItem>"))
        XCTAssertTrue(text.contains("review.publish(items, generation:"))
        XCTAssertEqual(text.components(separatedBy: "DiscogsFreshnessView(").count - 1, 1)
        XCTAssertTrue(text.contains("DiscogsAttributionView(sourcePageURL: candidate.evidence.sourcePageURL)"))
    }
    func testGenrePresenterMissing() throws {
        let text = try source("Sources/Views/MissingGenreView.swift")
        XCTAssertTrue(text.contains("DiscogsGenreReviewWindowPresenter.show(modelContext: modelContext, actions: libraryActions)"))
    }
    func testGenrePresenterSettings() throws {
        let text = try source("Sources/Views/SettingsView.swift")
        XCTAssertTrue(text.contains("DiscogsGenreReviewWindowPresenter.show(modelContext: modelContext, actions: libraryActions)"))
    }
    func testYearReviewUsesStableResultsAndSharedAction() throws {
        let text = try source("Sources/Views/MissingYearView.swift")
        XCTAssertFalse(text.contains("modelContext.save()"))
        XCTAssertTrue(text.contains("typealias SearchResult = DiscogsYearSuggestion"))
        XCTAssertTrue(text.contains("libraryActions.applyDiscogsYears("))
        XCTAssertTrue(text.contains("review.publish(results, generation:"))
        XCTAssertEqual(text.components(separatedBy: "DiscogsFreshnessView(").count - 1, 1)
        XCTAssertTrue(text.contains("DiscogsAttributionView(sourcePageURL: result.sourcePageURL)"))
    }
    func testAllReviewSurfacesInjectClientsBeforeAnyCredentialLoad() throws {
        for path in ["Sources/Discogs/DiscogsSearchView.swift", "Sources/Discogs/DiscogsBulkReviewView.swift",
                     "Sources/Discogs/DiscogsGenreReviewView.swift", "Sources/Views/MissingYearView.swift"] {
            let text = try source(path)
            XCTAssertFalse(text.contains("DiscogsKeychain.load()"), path)
            XCTAssertFalse(text.contains("DiscogsClient(tokenProvider:"), path)
            XCTAssertTrue(text.contains("dependencies: DiscogsReviewDependencies = .live"), path)
            XCTAssertTrue(text.contains("dependencies.search(query"), path)
            XCTAssertTrue(text.contains("DiscogsFreshnessView(clock: dependencies.clock"), path)
        }
    }
    func testBatchSurfacesUsePostAwaitCacheGuards() throws {
        for path in ["Sources/Discogs/DiscogsBulkReviewView.swift", "Sources/Discogs/DiscogsGenreReviewView.swift", "Sources/Views/MissingYearView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("try await dependencies.cachedCandidates(for: query)"), path)
            XCTAssertTrue(text.contains("try await dependencies.storeCandidates(top, for: query, fetches: [page.fetchedAt])"), path)
            XCTAssertTrue(text.contains("catch LibraryHealthMutationError.remoteEvidenceExpired"), path)
        }
    }
    func testManualAttributionIsASiblingOfSelection() throws {
        let text = try source("Sources/Discogs/DiscogsSearchView.swift")
        XCTAssertTrue(text.contains("DiscogsAttributionView(sourcePageURL: candidate.evidence.sourcePageURL)"))
        let start = try XCTUnwrap(text.range(of: "private func candidateRow"))
        let end = try XCTUnwrap(text.range(of: "private func formatsAndYear", range: start.upperBound..<text.endIndex))
        let row = String(text[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(row.contains("return VStack"))
        XCTAssertFalse(row.contains("Link("))
        // Attribution follows the complete Button and its accessibility modifier.
        if let label = row.range(of: ".accessibilityLabel"), let attribution = row.range(of: "DiscogsAttributionView") {
            XCTAssertLessThan(label.lowerBound, attribution.lowerBound)
        }
    }
}
