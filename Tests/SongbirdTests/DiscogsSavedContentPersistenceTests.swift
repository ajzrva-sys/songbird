import XCTest
import SwiftData
@testable import SongbirdLib

@MainActor
final class DiscogsSavedContentPersistenceTests: XCTestCase {
    func testImportedCoverAndYearSurviveCacheExpiryAndStoreReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = Schema([Album.self, Track.self, Artist.self, Playlist.self,
                             AlbumFavorite.self, TrackFavorite.self])
        let configuration = ModelConfiguration(schema: schema,
            url: root.appendingPathComponent("library.store"), cloudKitDatabase: .none)
        let clock = TestDiscogsClock()
        let evidence = DiscogsContentEvidence(releaseID: 42, fetches: [TestDiscogsClock.stamp()])
        let cache = DiscogsResponseCache<String>(fileURL: root.appendingPathComponent("lookup.json"),
            clock: { clock.sample() })
        let cached = await cache.store("temporary result", fetches: evidence.fetches, for: "album")
        XCTAssertTrue(cached)
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let path = root.appendingPathComponent("1997 - Saved title.m4a").path
        let receipt: LibraryHealthMutationReceipt
        do {
            let store = try ModelContainer(for: schema, configurations: configuration)
            let album = Album(title: "Saved album", artist: "Artist")
            let track = Track(path: path, title: "Saved title")
            store.mainContext.insert(album); store.mainContext.insert(track)
            album.tracks = [track]
            try store.mainContext.save()
            _ = try DiscogsYearApplier.apply([
                .init(album: DiscogsArtworkAlbumTarget(album: album), year: 1997, evidence: evidence)
            ], in: store.mainContext, clock: { clock.sample() })
            (_, receipt) = try await LibraryHealthMutationService(modelContainer: store).applyArtwork([
                .init(albumID: album.id, expectedArtworkDigest: nil, imageData: image, discogsEvidence: evidence)
            ], clock: { clock.sample() })
        }
        clock.set(TestDiscogsClock.stamp(21_600))
        let expired = await cache.value(for: "album")
        XCTAssertNil(expired)
        let reopened = try ModelContainer(for: schema, configurations: configuration)
        let album = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Album>()).first)
        let track = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Track>()).first)
        XCTAssertEqual(album.year, 1997)
        XCTAssertEqual(track.year, 1997)
        XCTAssertEqual(track.path, path)
        XCTAssertEqual(album.artworkData, ArtworkStorage.normalized(image))
        // Saved Undo remains usable independently of the expired acquisition evidence.
        _ = try await LibraryHealthMutationService(modelContainer: reopened).undo(receipt)
        let refreshed = try XCTUnwrap(ModelContext(reopened).fetch(FetchDescriptor<Album>()).first)
        XCTAssertNil(refreshed.artworkData)
        XCTAssertEqual(refreshed.year, 1997)
    }
}
