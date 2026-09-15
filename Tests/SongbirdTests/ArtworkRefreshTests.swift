import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import SongbirdLib

private actor ControlledArtworkLoader {
    private(set) var count = 0
    private var pending: [Int: CheckedContinuation<Data?, Never>] = [:]
    private var cancelled: Set<Int> = []
    private var finalData: Data?

    func load(_ albumID: UUID) async -> Data? {
        let index = count
        count += 1
        let data: Data?
        if let finalData {
            data = finalData
        } else {
            data = await withCheckedContinuation { pending[index] = $0 }
        }
        if Task.isCancelled { cancelled.insert(index) }
        return data
    }

    func complete(_ index: Int, data: Data) {
        pending.removeValue(forKey: index)?.resume(returning: data)
    }

    func completeAll(data: Data) {
        finalData = data
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations { continuation.resume(returning: data) }
    }

    func wasCancelled(_ index: Int) -> Bool { cancelled.contains(index) }
}

@Suite("Artwork replacement refresh", .serialized)
struct ArtworkRefreshTests {
    @Test("The default album loader reads replaced bytes and retains unrelated cached images",
          arguments: [false, true])
    @MainActor
    func replacementReadsFreshData(externalContainer: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = externalContainer ? directory.appendingPathComponent("library.store") : nil
        let container = try makeContainer(url: url)
        let album = Album(title: "Changed", artist: "Fixture")
        let unrelated = Album(title: "Unchanged", artist: "Fixture")
        album.artworkData = try png(red: 1, blue: 0)
        unrelated.artworkData = try png(red: 0, blue: 1)
        container.mainContext.insert(album)
        container.mainContext.insert(unrelated)
        try container.mainContext.save()
        let reference = reference(for: album)
        let otherReference = self.reference(for: unrelated)
        let service = await Task.detached {
            ArtworkThumbnailService(modelContainer: container)
        }.value
        let before = try #require(await service.image(for: reference, pointSize: size))
        let other = try #require(await service.image(for: otherReference, pointSize: size))
        #expect(try pixel(before)[0] > 240)

        let writerContainer = try url.map { try makeContainer(url: $0) } ?? container
        let writer = ModelContext(writerContainer)
        let id = album.id
        let current = try #require(writer.fetch(FetchDescriptor<Album>(
            predicate: #Predicate { $0.id == id }
        )).first)
        current.artworkData = try png(red: 0, blue: 1)
        try writer.save()
        await service.invalidate(albumID: id)

        let updated = try #require(await service.image(for: reference, pointSize: size))
        #expect(try pixel(updated)[2] > 240)
        #expect(try pixel(updated)[0] < 10)
        let retained = try #require(await service.image(for: otherReference, pointSize: size))
        #expect(retained === other)
        #expect(await service.cacheMetrics().decodeCount == 3)

        current.artworkData = nil
        try writer.save()
        await service.invalidate(albumID: id)
        #expect(await service.image(for: reference, pointSize: size) == nil)
    }

    @Test("Invalidation cancels in-flight-only loads without clearing their replacements",
          arguments: [false, true])
    @MainActor
    func inFlightInvalidation(invalidateAll: Bool) async throws {
        let container = try makeContainer()
        let album = Album(title: "In flight", artist: "Fixture")
        container.mainContext.insert(album)
        try container.mainContext.save()
        let reference = reference(for: album)
        let loader = ControlledArtworkLoader()
        let service = ArtworkThumbnailService(
            modelContainer: container,
            albumDataLoader: { await loader.load($0) }
        )
        let size = size
        let old = Task { await service.image(for: reference, pointSize: size) }
        #expect(await waitForLoads(1, loader: loader))
        if invalidateAll {
            await service.invalidateAll()
        } else {
            await service.invalidate(albumID: album.id)
        }
        let replacement = Task { await service.image(for: reference, pointSize: size) }
        let replacementStarted = await waitForLoads(2, loader: loader)
        #expect(replacementStarted)
        await loader.complete(0, data: try png(red: 1, blue: 0))
        #expect(await old.value == nil)
        #expect(await loader.wasCancelled(0))
        // The obsolete completion must not clear the newer in-flight entry.
        let joined = Task { await service.image(for: reference, pointSize: size) }
        for _ in 0..<20 { await Task.yield() }
        #expect(await service.cacheMetrics().decodeCount == 2)
        await loader.completeAll(data: try png(red: 0, blue: 1))
        let current = try #require(await replacement.value)
        let coalesced = try #require(await joined.value)
        #expect(try pixel(current)[2] > 240)
        #expect(current === coalesced)
        let cached = try #require(await service.image(for: reference, pointSize: size))
        #expect(cached === current)
        #expect(await service.cacheMetrics().decodeCount == 2)
    }

    @Test("Late obsolete bytes cannot replace an already-published new thumbnail")
    @MainActor
    func lateObsoleteCompletion() async throws {
        let container = try makeContainer()
        let album = Album(title: "Late completion", artist: "Fixture")
        container.mainContext.insert(album)
        try container.mainContext.save()
        let reference = reference(for: album)
        let loader = ControlledArtworkLoader()
        let service = ArtworkThumbnailService(
            modelContainer: container, albumDataLoader: { await loader.load($0) }
        )
        let size = size
        let old = Task { await service.image(for: reference, pointSize: size) }
        #expect(await waitForLoads(1, loader: loader))
        await service.invalidate(albumID: album.id)
        let replacement = Task { await service.image(for: reference, pointSize: size) }
        let replacementStarted = await waitForLoads(2, loader: loader)
        if replacementStarted == false {
            await loader.completeAll(data: try png(red: 1, blue: 0))
        }
        try #require(replacementStarted)
        await loader.complete(1, data: try png(red: 0, blue: 1))
        let current = try #require(await replacement.value)
        await loader.completeAll(data: try png(red: 1, blue: 0))
        #expect(await old.value == nil)
        let cached = try #require(await service.image(for: reference, pointSize: size))
        #expect(cached === current)
        #expect(try pixel(cached)[2] > 240)
        #expect(await service.cacheMetrics().decodeCount == 2)
    }

    @Test("The default loader follows a same-UUID record replacement after warming its cache")
    @MainActor
    func defaultLoaderFollowsRecordReplacement() async throws {
        let container = try makeContainer()
        let original = Album(title: "Original", artist: "Fixture")
        original.artworkData = try png(red: 1, blue: 0)
        container.mainContext.insert(original)
        try container.mainContext.save()
        let reference = reference(for: original)
        let id = original.id
        let service = ArtworkThumbnailService(modelContainer: container)
        let red = try #require(await service.image(for: reference, pointSize: size))
        #expect(try pixel(red)[0] > 240)
        container.mainContext.delete(original)
        try container.mainContext.save()
        await service.invalidate(albumID: id)
        #expect(await service.image(for: reference, pointSize: size) == nil)
        let replacement = Album(title: "Replacement", artist: "Fixture")
        replacement.id = id
        replacement.artworkData = try png(red: 0, blue: 1)
        container.mainContext.insert(replacement)
        try container.mainContext.save()
        await service.invalidate(albumID: id)
        let blue = try #require(await service.image(for: reference, pointSize: size))
        #expect(try pixel(blue)[2] > 240)
    }

    @Test("Visible load generations change only for affected albums and reject late images")
    @MainActor
    func visibleGenerationSuppressesStaleLoad() throws {
        let container = try makeContainer()
        let album = Album(title: "Visible", artist: "Fixture")
        container.mainContext.insert(album)
        try container.mainContext.save()
        let reference = reference(for: album)
        let redData = try png(red: 1, blue: 0)
        let blueData = try png(red: 0, blue: 1)
        let redSource = try #require(CGImageSourceCreateWithData(redData as CFData, nil))
        let blueSource = try #require(CGImageSourceCreateWithData(blueData as CFData, nil))
        let red = try #require(CGImageSourceCreateImageAtIndex(redSource, 0, nil))
        let blue = try #require(CGImageSourceCreateImageAtIndex(blueSource, 0, nil))
        var state = ArtworkThumbnailLoadState()
        state.publish(red, generation: state.generation)
        let originalGeneration = state.generation
        state.invalidate(ArtworkInvalidation(albumIDs: [UUID()]), reference: reference)
        #expect(state.generation == originalGeneration)
        #expect(state.image === red)
        state.invalidate(ArtworkInvalidation(albumIDs: [album.id]), reference: reference)
        #expect(state.generation != originalGeneration)
        #expect(state.image == nil)
        state.publish(blue, generation: state.generation)
        state.publish(red, generation: originalGeneration)
        #expect(state.image === blue)
        let currentGeneration = state.generation
        state.invalidate(ArtworkInvalidation(albumIDs: nil), reference: .songbirdLogo)
        #expect(state.generation == currentGeneration)
    }

    @Test("Saved artwork invalidates the injected service before notifying visible consumers")
    @MainActor
    func savedArtworkRefreshEvent() async throws {
        let container = try makeContainer()
        let album = Album(title: "Saved", artist: "Fixture")
        let other = Album(title: "Unrelated", artist: "Fixture")
        album.artworkData = try png(red: 1, blue: 0)
        other.artworkData = try png(red: 1, blue: 0)
        container.mainContext.insert(album)
        container.mainContext.insert(other)
        try container.mainContext.save()
        let service = ArtworkThumbnailService(modelContainer: container)
        let store = LibrarySnapshotStore(
            modelContainer: container, startsImmediately: false, artworkService: service
        )
        await store.refresh()
        let reference = reference(for: album)
        let otherReference = self.reference(for: other)
        _ = await service.image(for: reference, pointSize: size)
        let otherImage = try #require(await service.image(for: otherReference, pointSize: size))
        var events: [ArtworkInvalidation] = []
        let observer = NotificationCenter.default.addObserver(
            forName: ArtworkInvalidation.notificationName, object: nil, queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                if let event = ArtworkInvalidation(notification: notification) { events.append(event) }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        album.artworkData = try png(red: 0, blue: 1)
        try container.mainContext.save()
        await store.refreshAfterMutation()
        #expect(events.map(\.albumIDs) == [Set([album.id])])
        #expect(await service.cacheMetrics().count == 1)
        let current = try #require(await service.image(for: reference, pointSize: size))
        #expect(try pixel(current)[2] > 240)
        #expect(await service.image(for: otherReference, pointSize: size) === otherImage)
        #expect(store.fullRebuildCount == 1)
        #expect(store.patchPublicationCount == 1)
    }

    @Test("Missing save evidence refreshes unchanged artwork references after an external save")
    @MainActor
    func missingSaveEvidenceRefreshesArtwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.store")
        let container = try makeContainer(url: url)
        let album = Album(title: "External", artist: "Fixture")
        album.artworkData = try png(red: 1, blue: 0)
        container.mainContext.insert(album)
        try container.mainContext.save()
        let service = ArtworkThumbnailService(modelContainer: container)
        let store = LibrarySnapshotStore(
            modelContainer: container, startsImmediately: false, artworkService: service
        )
        await store.refresh()
        let reference = reference(for: album)
        _ = await service.image(for: reference, pointSize: size)
        let writerContainer = try makeContainer(url: url)
        let writer = ModelContext(writerContainer)
        let current = try #require(writer.fetch(FetchDescriptor<Album>()).first)
        current.artworkData = try png(red: 0, blue: 1)
        let requests = store.refreshRequestCount
        var receivedInvalidation = false
        let observer = NotificationCenter.default.addObserver(
            forName: ArtworkInvalidation.notificationName, object: nil, queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                if let event = ArtworkInvalidation(notification: notification) {
                    receivedInvalidation = event.albumIDs == nil && event.affects(reference)
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        try writer.save()
        #expect(store.refreshRequestCount == requests)
        await store.refreshAfterMutation()
        #expect(receivedInvalidation)
        #expect(store.fullRebuildCount == 2)
        let refreshed = try #require(await service.image(for: reference, pointSize: size))
        #expect(try pixel(refreshed)[2] > 240)
        #expect(await service.cacheMetrics().decodeCount == 2)
    }

    private func waitForLoads(_ count: Int, loader: ControlledArtworkLoader) async -> Bool {
        for _ in 0..<200 {
            if await loader.count >= count { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    private var size: CGSize { CGSize(width: 16, height: 16) }

    @MainActor
    private func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self,
                             AlbumFavorite.self, TrackFavorite.self])
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func reference(for album: Album) -> ArtworkReference {
        .album(id: album.id, persistentIdentifier: album.persistentModelID)
    }

    private func png(red: CGFloat, blue: CGFloat) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: 0, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func pixel(_ image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: bytes, count: 4))
    }
}
