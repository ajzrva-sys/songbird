import XCTest
import SwiftData
@testable import SongbirdLib

@MainActor
final class DiscogsArtworkApplicationTests: XCTestCase {
    private let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    private func suggestion(_ id: Int, at time: Double = 0) -> DiscogsArtworkAlbumSuggestion {
        let candidate = DiscogsArtworkCandidate(id: id, title: "Remote", artist: "Artist", year: 1999,
            country: nil, formats: [], genres: [], styles: [], thumbnailURL: nil,
            imageURL: URL(string: "https://example.invalid/image")!,
            sourcePageURL: URL(string: "https://www.discogs.com/release/" + String(id))!,
            fetchedAt: TestDiscogsClock.stamp(time))
        return DiscogsArtworkAlbumSuggestion(album: DiscogsArtworkAlbumTarget(album: Album(title: "Local", artist: "Artist")), candidate: candidate)
    }
    func testExpiredContentNeverDownloadsOrNormalizes() async throws {
        for expireDuringDownload in [false, true] {
            let clock = TestDiscogsClock([TestDiscogsClock.stamp(expireDuringDownload ? 0 : 18_000)])
            var downloads = 0
            var normalizations = 0
            var submissions = 0
            do {
                _ = try await DiscogsArtworkApplication.apply([suggestion(1)], clock: { clock.sample() },
                    download: { _ in
                        downloads += 1
                        clock.set(TestDiscogsClock.stamp(18_000))
                        return self.image
                    }, normalize: { bytes in normalizations += 1; return bytes },
                    submit: { _ in submissions += 1; return .success(.init(affectedTrackCount: 0)) })
                XCTFail("Expired content must be refused")
            } catch {
                XCTAssertEqual(error as? LibraryHealthMutationError, .remoteEvidenceExpired)
            }
            XCTAssertEqual(downloads, expireDuringDownload ? 1 : 0)
            XCTAssertEqual(normalizations, 0)
            XCTAssertEqual(submissions, 0)
        }
    }

    func testInvalidatedSelectionCannotSubmitAfterAwait() async throws {
        let value = suggestion(1)
        let state = DiscogsReviewState<DiscogsArtworkCandidate>(clock: { TestDiscogsClock.stamp() }, evidence: { [$0.evidence] })
        let generation = state.beginSearch(targets: [value.album])
        state.publish([value.candidate], generation: generation)
        state.select(id: 1)
        var submissions = 0
        do {
            _ = try await DiscogsArtworkApplication.apply([value], clock: { TestDiscogsClock.stamp() },
                download: { _ in
                    await Task.yield()
                    state.invalidate()
                    return self.image
                }, isCurrent: { state.generation == generation },
                submit: { _ in submissions += 1; return .success(.init(affectedTrackCount: 0)) })
            XCTFail("Cancelled selection must never submit")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(submissions, 0)
        XCTAssertNil(state.selectedID)
    }

    func testInvalidImageNeverSubmits() async throws {
        var submissions = 0
        do {
            _ = try await DiscogsArtworkApplication.apply([suggestion(1)], clock: { TestDiscogsClock.stamp() },
                download: { _ in Data("not an image".utf8) },
                submit: { _ in submissions += 1; return .success(.init(affectedTrackCount: 0)) })
            XCTFail("Invalid image must be rejected")
        } catch { XCTAssertEqual(error as? LibraryHealthMutationError, .invalidArtwork) }
        XCTAssertEqual(submissions, 0)
    }

    func testFailedDownloadStillChecksAcquisitionExpiry() async throws {
        let clock = TestDiscogsClock()
        do {
            _ = try await DiscogsArtworkApplication.apply([suggestion(1)], clock: { clock.sample() },
                download: { _ in
                    clock.set(TestDiscogsClock.stamp(18_000))
                    throw DiscogsError.networkUnavailable
                }, submit: { _ in XCTFail("No submission after error"); return .failure(.invalidArtwork) })
            XCTFail("Expected expiry")
        } catch { XCTAssertEqual(error as? LibraryHealthMutationError, .remoteEvidenceExpired) }
    }

    func testFreshNormalizedBatchCarriesOriginalEvidenceToSubmission() async throws {
        let value = suggestion(1)
        let clock = TestDiscogsClock()
        var submissions = 0
        _ = try await DiscogsArtworkApplication.apply([value], clock: { clock.sample() },
            download: { _ in self.image },
            normalize: { data in clock.set(TestDiscogsClock.stamp(1)); return ArtworkStorage.normalized(data) },
            submit: { changes in
                submissions += 1
                XCTAssertEqual(changes.first?.discogsEvidence, value.candidate.evidence)
                XCTAssertEqual(changes.first?.albumID, value.album.id)
                XCTAssertEqual(changes.first?.imageData, self.image)
                return .success(.init(affectedTrackCount: 0, affectedAlbumCount: changes.count))
            })
        XCTAssertEqual(submissions, 1)
    }

    func testOneSelectedReleaseDownloadsOnceForRelatedAlbums() async throws {
        let selected = suggestion(1)
        let related = DiscogsArtworkAlbumSuggestion(album: DiscogsArtworkAlbumTarget(album: Album(title: "Disc 2", artist: "Artist")), candidate: selected.candidate)
        var downloads = 0
        _ = try await DiscogsArtworkApplication.apply([selected, related], clock: { TestDiscogsClock.stamp() },
            download: { _ in downloads += 1; return self.image },
            submit: { changes in
                XCTAssertEqual(Set(changes.map(\.albumID)), Set([selected.album.id, related.album.id]))
                XCTAssertTrue(changes.allSatisfy { $0.discogsEvidence == selected.candidate.evidence })
                return .success(.init(affectedTrackCount: 0, affectedAlbumCount: changes.count))
            })
        XCTAssertEqual(downloads, 1)
    }

    func testFirstImageExpiresDuringLastDownloadWithoutSubmission() async throws {
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(1)])
        let suggestions = [suggestion(1), suggestion(2, at: 1)]
        var submissions = 0
        do {
            _ = try await DiscogsArtworkApplication.apply(suggestions, clock: { clock.sample() },
                download: { candidate in
                    if candidate.id == 2 { clock.set(TestDiscogsClock.stamp(18_000)) }
                    return self.image
                }, submit: { changes in
                    submissions += 1
                    return .success(LibraryHealthMutationOutcome(affectedTrackCount: 0, affectedAlbumCount: changes.count))
                })
            XCTFail("First image expired while last download remained fresh")
        } catch {
            XCTAssertEqual(error as? LibraryHealthMutationError, .remoteEvidenceExpired)
        }
        XCTAssertEqual(submissions, 0)
    }
}
