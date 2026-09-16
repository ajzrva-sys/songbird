import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import SongbirdLib

private actor ReuseArtworkLoader {
    private(set) var count = 0
    let data: Data
    private var blocked: Bool
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(data: Data, blocked: Bool = false) { self.data = data; self.blocked = blocked }
    func load() async -> Data {
        count += 1
        if blocked { await withCheckedContinuation { waiters.append($0) } }
        return data
    }
    func release() {
        blocked = false
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

@Suite("Album artwork reuse", .serialized)
struct ArtworkReuseTests {
    @Test("Opening a larger album cover reuses source bytes and exposes the existing preview")
    @MainActor
    func coverReuse() async throws {
        let (container, reference) = try fixture()
        let loader = ReuseArtworkLoader(data: try fixtureImage())
        let service = ArtworkThumbnailService(modelContainer: container, albumDataLoader: { _ in await loader.load() })
        let small = try #require(await service.image(for: reference, pointSize: CGSize(width: 32, height: 32)))
        let preview = await service.cachedImage(for: reference, pointSize: CGSize(width: 160, height: 160))
        #expect(preview === small)
        let large = try #require(await service.image(for: reference, pointSize: CGSize(width: 160, height: 160)))
        #expect(large.width > small.width)
        #expect(await loader.count == 1)
        #expect(await service.sourceCacheMetrics().count == 1)
        #expect(await service.cachedImage(for: reference, pointSize: CGSize(width: 160, height: 160)) === large)
    }

    @Test("Different thumbnail sizes join one database load")
    @MainActor
    func concurrentSizes() async throws {
        let (container, reference) = try fixture()
        let loader = ReuseArtworkLoader(data: try fixtureImage(), blocked: true)
        let service = ArtworkThumbnailService(modelContainer: container, albumDataLoader: { _ in await loader.load() })
        let small = Task { await service.image(for: reference, pointSize: CGSize(width: 32, height: 32)) }
        let large = Task { await service.image(for: reference, pointSize: CGSize(width: 160, height: 160)) }
        for _ in 0..<200 {
            if await service.inFlightMetrics().count == 2, await loader.count > 0 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(await service.inFlightMetrics().count == 2)
        await loader.release()
        #expect(await small.value != nil)
        #expect(await large.value != nil)
        #expect(await loader.count == 1)
    }

    @Test("Replacement clears source bytes and previews at every size")
    @MainActor
    func invalidateSizes() async throws {
        let (container, reference) = try fixture()
        let loader = ReuseArtworkLoader(data: try fixtureImage())
        let service = ArtworkThumbnailService(modelContainer: container, albumDataLoader: { _ in await loader.load() })
        _ = await service.image(for: reference, pointSize: CGSize(width: 32, height: 32))
        _ = await service.image(for: reference, pointSize: CGSize(width: 160, height: 160))
        guard case .album(let id, _) = reference else { return }
        await service.invalidate(albumID: id)
        #expect(await service.sourceCacheMetrics().count == 0)
        #expect(await service.cachedImage(for: reference, pointSize: CGSize(width: 160, height: 160)) == nil)
        _ = await service.image(for: reference, pointSize: CGSize(width: 80, height: 80))
        #expect(await loader.count == 2)
        await service.invalidateAll()
        #expect(await service.sourceCacheMetrics().byteCost == 0)
    }

    @Test("Encoded source caching remains within its memory budget")
    @MainActor
    func boundedSourceCache() async throws {
        let (container, reference) = try fixture()
        let loader = ReuseArtworkLoader(data: try fixtureImage())
        let service = ArtworkThumbnailService(modelContainer: container, maximumByteCost: 1,
            albumDataLoader: { _ in await loader.load() })
        _ = await service.image(for: reference, pointSize: CGSize(width: 32, height: 32))
        #expect(await service.sourceCacheMetrics().count == 0)
        #expect(await service.sourceCacheMetrics().byteCost == 0)
    }

    @Test("UI-owned snapshot stores construct their database worker off the main thread")
    @MainActor
    func workerConstruction() async throws {
        let worker = BackgroundLibrarySnapshotBuilder(makeWorker: {
            #expect(!Thread.isMainThread)
            return EmptySnapshotReader()
        })
        #expect(try await worker.buildSnapshot(revision: 1).tracks.isEmpty)
    }

    @MainActor
    private func fixture() throws -> (ModelContainer, ArtworkReference) {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let album = Album(title: "Cover reuse", artist: "Synthetic")
        container.mainContext.insert(album)
        try container.mainContext.save()
        return (container, .album(id: album.id, persistentIdentifier: album.persistentModelID))
    }

    private func fixtureImage() throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Sources/Resources/missing-album-artwork.png"))
    }
}

private struct EmptySnapshotReader: LibrarySnapshotBuilding {
    func buildSnapshot(revision: Int) async throws -> LibrarySnapshot { .empty }
}
