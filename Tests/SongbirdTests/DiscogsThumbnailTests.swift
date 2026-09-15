import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import SongbirdLib

@Suite("Discogs thumbnail cache")
@MainActor
struct DiscogsThumbnailTests {
    @Test("Cache expiry task cancels an expired pending provider load without another image request")
    func cacheOwnsInflightExpiry() async throws {
        let clock = TestDiscogsClock()
        let loader = ControlledThumbnailLoader()
        let service = ArtworkThumbnailService(modelContainer: try thumbnailContainer(),
            clock: { clock.sample() }, discogsArtworkLoader: { _, _ in await loader.load() },
            expirySleep: { _ in
                for _ in 0..<200 {
                    if await loader.count == 1 { break }
                    try await Task.sleep(for: .milliseconds(5))
                }
                clock.set(TestDiscogsClock.stamp(18_000))
            })
        let reference = ArtworkReference.discogsRemote(URL(string: "https://fixture.test/pending.png")!,
            evidence: .init(releaseID: 42, fetches: [TestDiscogsClock.stamp()]))
        let image = Task { await service.image(for: reference, pointSize: thumbnailSize) }
        for _ in 0..<200 {
            if clock.sample() == TestDiscogsClock.stamp(18_000), await service.inFlightMetrics().count == 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(clock.sample() == TestDiscogsClock.stamp(18_000))
        #expect(await service.inFlightMetrics().count == 0)
        await loader.complete(try thumbnailPNG())
        #expect(await image.value == nil)
        #expect(await loader.cancelledCount == 1)
    }

    @Test("Real URLSession image response crossing expiry cannot populate the cache")
    func actualDelayedHTTPExpiry() async throws {
        let fixture = try ThumbnailHTTPFixture(data: thumbnailPNG(), delayed: true)
        let clock = TestDiscogsClock()
        let service = ArtworkThumbnailService(modelContainer: try thumbnailContainer(),
            clock: { clock.sample() }, discogsSession: fixture.session)
        let reference = ArtworkReference.discogsRemote(URL(string: "https://fixture.test/delayed.png")!,
            evidence: .init(releaseID: 42, fetches: [TestDiscogsClock.stamp()]))
        let image = Task { await service.image(for: reference, pointSize: thumbnailSize) }
        for _ in 0..<200 {
            if try !fixture.requests().isEmpty { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(try fixture.requests().count == 1)
        clock.set(TestDiscogsClock.stamp(18_000))
        try fixture.release()
        #expect(await image.value == nil)
        #expect(await service.cacheMetrics().count == 0)
    }

    @Test("Pruning cancels only expired Discogs loads and ignores their eventual bytes")
    func pruneCancelsOnlyDiscogsLoads() async throws {
        let clock = TestDiscogsClock()
        let provider = ControlledThumbnailLoader()
        let ordinary = ControlledThumbnailLoader()
        let service = ArtworkThumbnailService(modelContainer: try thumbnailContainer(),
            remoteArtworkLoader: { _ in await ordinary.load() }, clock: { clock.sample() },
            discogsArtworkLoader: { _, _ in await provider.load() })
        let url = URL(string: "https://fixture.test/shared.png")!
        let reference = ArtworkReference.discogsRemote(url,
            evidence: .init(releaseID: 42, fetches: [TestDiscogsClock.stamp()]))
        let remote = Task { await service.image(for: reference, pointSize: thumbnailSize) }
        let generic = Task { await service.image(for: .remote(url), pointSize: thumbnailSize) }
        for _ in 0..<200 {
            if await provider.count == 1, await ordinary.count == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await provider.count == 1)
        #expect(await ordinary.count == 1)
        clock.set(nil)
        await service.pruneExpiredDiscogs()
        #expect(await service.inFlightMetrics().count == 1)
        let data = try thumbnailPNG()
        await provider.complete(data)
        await ordinary.complete(data)
        #expect(await remote.value == nil)
        #expect(await generic.value != nil)
        #expect(await provider.cancelledCount == 1)
        #expect(await ordinary.cancelledCount == 0)
    }

    @Test("New acquisitions have distinct cache keys; pruning old evidence retains fresh and embedded bytes")
    func evidenceHashedKeys() async throws {
        let data = try thumbnailPNG()
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(10)])
        let service = ArtworkThumbnailService(modelContainer: try thumbnailContainer(), clock: { clock.sample() },
            discogsArtworkLoader: { _, _ in data })
        let url = URL(string: "https://fixture.test/unchanged.png")!
        let old = ArtworkReference.discogsRemote(url, evidence: .init(releaseID: 42, fetches: [TestDiscogsClock.stamp()]))
        let new = ArtworkReference.discogsRemote(url, evidence: .init(releaseID: 42, fetches: [TestDiscogsClock.stamp(10)]))
        #expect(Set([old, new]).count == 2)
        #expect(await service.image(for: old, pointSize: thumbnailSize) != nil)
        let fresh = try #require(await service.image(for: new, pointSize: thumbnailSize))
        let embedded = ArtworkReference.embedded(id: UUID(), data: data)
        let local = try #require(await service.image(for: embedded, pointSize: thumbnailSize))
        #expect(await service.cacheMetrics().decodeCount == 3)
        clock.set(TestDiscogsClock.stamp(18_000))
        #expect(await service.image(for: old, pointSize: thumbnailSize) == nil)
        #expect(await service.image(for: new, pointSize: thumbnailSize) === fresh)
        #expect(await service.image(for: embedded, pointSize: thumbnailSize) === local)
        #expect(await service.cacheMetrics().count == 2)
    }

    @Test("Malformed or missing acquisitions never start a Discogs thumbnail request")
    func missingEvidenceRejectsWithoutNetwork() async throws {
        let fixture = try ThumbnailHTTPFixture(data: thumbnailPNG())
        let service = ArtworkThumbnailService(modelContainer: try thumbnailContainer(),
            clock: { TestDiscogsClock.stamp() }, discogsSession: fixture.session)
        let url = URL(string: "https://fixture.test/image.png")!
        for evidence in [DiscogsContentEvidence(releaseID: 42, fetches: []),
                         .init(releaseID: 0, fetches: [TestDiscogsClock.stamp()]),
                         .init(releaseID: 42, fetches: [TestDiscogsClock.stamp(1)])] {
            #expect(await service.image(for: .discogsRemote(url, evidence: evidence), pointSize: thumbnailSize) == nil)
        }
        #expect(try fixture.requests().isEmpty)
        #expect(await service.cacheMetrics().decodeCount == 0)
    }

    @Test("Insertion refusal cannot be followed by successful publication when the clock recovers")
    func insertionRefusalIsTerminal() async throws {
        // Admission/pruning/task and completion samples are fresh; insertion alone is unavailable.
        let fresh = TestDiscogsClock.stamp()
        let clock = TestDiscogsClock(Array(repeating: fresh, count: 6) + [nil, fresh])
        let data = try thumbnailPNG()
        let service = ArtworkThumbnailService(modelContainer: try thumbnailContainer(),
            remoteArtworkLoader: { _ in Data() }, clock: { clock.sample() },
            discogsArtworkLoader: { _, _ in data })
        let reference = ArtworkReference.discogsRemote(URL(string: "https://fixture.test/image.png")!,
            evidence: .init(releaseID: 42, fetches: [fresh]))
        #expect(await service.image(for: reference, pointSize: thumbnailSize) == nil)
        #expect(await service.cacheMetrics().count == 0)
    }

    @Test("Discogs references use the uncached provider image pipeline, not the ordinary loader")
    func providerSpecificUncachedLoader() async throws {
        let fixture = try ThumbnailHTTPFixture(data: thumbnailPNG())
        let service = ArtworkThumbnailService(modelContainer: try thumbnailContainer(),
            remoteArtworkLoader: { _ in
                Issue.record("Discogs image was sent through the generic remote loader")
                return Data()
            }, clock: { TestDiscogsClock.stamp() }, discogsSession: fixture.session)
        let reference = ArtworkReference.discogsRemote(URL(string: "https://fixture.test/image.png")!,
            evidence: .init(releaseID: 42, fetches: [TestDiscogsClock.stamp()]))
        #expect(await service.image(for: reference, pointSize: thumbnailSize) != nil)
        let requests = try fixture.requests()
        #expect(requests.count == 1)
        #expect(requests.first?["cacheControl"] == "no-cache")
        #expect(requests.first?["cachePolicy"] == String(URLRequest.CachePolicy.reloadIgnoringLocalCacheData.rawValue))
    }

    @Test("Joined and owning loads cannot publish bytes completing after expiry")
    func joinedInflightPublicationChecksFreshness() async throws {
        let clock = TestDiscogsClock()
        let loader = ControlledThumbnailLoader()
        let service = ArtworkThumbnailService(modelContainer: try thumbnailContainer(),
            remoteArtworkLoader: { _ in Data() }, clock: { clock.sample() },
            discogsArtworkLoader: { _, _ in await loader.load() })
        let reference = ArtworkReference.discogsRemote(URL(string: "https://fixture.test/delayed.png")!,
            evidence: .init(releaseID: 42, fetches: [TestDiscogsClock.stamp()]))
        let owner = Task { await service.image(for: reference, pointSize: thumbnailSize) }
        let joined = Task { await service.image(for: reference, pointSize: thumbnailSize) }
        for _ in 0..<200 {
            if await service.inFlightMetrics().joinCount == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await loader.count == 1)
        #expect(await service.inFlightMetrics().joinCount == 1)
        clock.set(TestDiscogsClock.stamp(18_000))
        await loader.complete(try thumbnailPNG())
        #expect(await owner.value == nil)
        #expect(await joined.value == nil)
        #expect(await service.cacheMetrics().count == 0)
    }

    @Test("Cached Discogs image is rejected at the strict boundary without touching ordinary remote images")
    func cachedReturnChecksFreshness() async throws {
        let clock = TestDiscogsClock()
        let data = try thumbnailPNG()
        let service = ArtworkThumbnailService(modelContainer: try thumbnailContainer(),
            remoteArtworkLoader: { _ in data }, clock: { clock.sample() },
            discogsArtworkLoader: { _, _ in data })
        let url = URL(string: "https://unrelated-host.test/cover.png")!
        let reference = ArtworkReference.discogsRemote(url, evidence: .init(releaseID: 42, fetches: [TestDiscogsClock.stamp()]))
        let fresh = try #require(await service.image(for: reference, pointSize: thumbnailSize))
        let ordinary = try #require(await service.image(for: .remote(url), pointSize: thumbnailSize))
        #expect(await service.image(for: reference, pointSize: thumbnailSize) === fresh)
        clock.set(TestDiscogsClock.stamp(18_000))
        #expect(await service.image(for: reference, pointSize: thumbnailSize) == nil)
        #expect(await service.image(for: .remote(url), pointSize: thumbnailSize) === ordinary)
        #expect(await service.cacheMetrics().count == 1)
    }
}

private let thumbnailSize = CGSize(width: 16, height: 16)

@MainActor
private func thumbnailContainer() throws -> ModelContainer {
    let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self, AlbumFavorite.self, TrackFavorite.self])
    return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
}

private func thumbnailPNG() throws -> Data {
    let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    let data = NSMutableData()
    let output = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(output, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(output))
    return data as Data
}
