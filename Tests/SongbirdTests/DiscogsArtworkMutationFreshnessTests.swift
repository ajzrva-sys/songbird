import XCTest
import SwiftData
@testable import SongbirdLib

@MainActor
final class DiscogsArtworkMutationFreshnessTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Album.self, Track.self, Artist.self, Playlist.self,
            AlbumFavorite.self, TrackFavorite.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    private var image: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    }
    func testExpiryDuringNormalizationPreventsAssignments() async throws {
        let store = try container()
        let album = Album(title: "A", artist: "Artist")
        store.mainContext.insert(album)
        try store.mainContext.save()
        let clock = TestDiscogsClock()
        let change = LibraryArtworkChange(albumID: album.id, expectedArtworkDigest: nil,
            imageData: image, discogsEvidence: DiscogsContentEvidence(releaseID: 1,
                fetches: [TestDiscogsClock.stamp()]))
        do {
            _ = try await LibraryHealthMutationService(modelContainer: store).applyArtwork(
                [change], clock: { clock.sample() }, normalize: { data in
                    clock.set(TestDiscogsClock.stamp(18_000))
                    return ArtworkStorage.normalized(data)
                })
            XCTFail("Normalization crossed expiry; no assignment is permitted")
        } catch {
            XCTAssertEqual(error as? LibraryHealthMutationError, .remoteEvidenceExpired)
        }
        XCTAssertNil(try ModelContext(store).fetch(FetchDescriptor<Album>()).first?.artworkData)
    }

    func testExpiryAtSaveRollsBackAndKeepsTypedError() async throws {
        let store = try container()
        let album = Album(title: "A", artist: "Artist")
        store.mainContext.insert(album)
        try store.mainContext.save()
        let clock = TestDiscogsClock([
            TestDiscogsClock.stamp(), TestDiscogsClock.stamp(),
            TestDiscogsClock.stamp(), TestDiscogsClock.stamp(18_000)])
        let change = LibraryArtworkChange(albumID: album.id, expectedArtworkDigest: nil,
            imageData: image, discogsEvidence: DiscogsContentEvidence(releaseID: 1,
                fetches: [TestDiscogsClock.stamp()]))
        let service = LibraryHealthMutationService(modelContainer: store)
        do {
            _ = try await service.applyArtwork([change], clock: { clock.sample() })
            XCTFail("Expiry immediately before save must roll back assignments")
        } catch {
            XCTAssertEqual(error as? LibraryHealthMutationError, .remoteEvidenceExpired)
        }
        XCTAssertNil(try ModelContext(store).fetch(FetchDescriptor<Album>()).first?.artworkData)
        // A second local operation proves the actor's own context was rolled back too.
        let local = LibraryArtworkChange(albumID: album.id, expectedArtworkDigest: nil, imageData: image)
        let (_, receipt) = try await service.applyArtwork([local], clock: { nil })
        _ = try await service.undo(receipt)
        XCTAssertNil(try ModelContext(store).fetch(FetchDescriptor<Album>()).first?.artworkData)
    }

    func testExpiredItemRejectsWholeArtworkBatch() async throws {
        let store = try container()
        let albums = [Album(title: "A", artist: "Artist"), Album(title: "B", artist: "Artist")]
        for album in albums { store.mainContext.insert(album) }
        try store.mainContext.save()
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(18_000)])
        let changes = albums.enumerated().map { index, album in
            LibraryArtworkChange(albumID: album.id, expectedArtworkDigest: nil, imageData: image,
                discogsEvidence: DiscogsContentEvidence(releaseID: index + 1,
                    fetches: [TestDiscogsClock.stamp(index == 0 ? 1 : 0)]))
        }
        do {
            _ = try await LibraryHealthMutationService(modelContainer: store)
                .applyArtwork(changes, clock: { clock.sample() })
            XCTFail("Expired Discogs artwork must reject the entire batch")
        } catch {
            XCTAssertEqual(error as? LibraryHealthMutationError, .remoteEvidenceExpired)
        }
        XCTAssertTrue(try ModelContext(store).fetch(FetchDescriptor<Album>()).allSatisfy { $0.artworkData == nil })
    }
}
