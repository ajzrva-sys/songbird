import CoreGraphics
import Foundation
import ImageIO
import OSLog
import SwiftData

@ModelActor
private actor ArtworkDataModelActor {
    func artworkData(for albumID: UUID) -> Data? {
        // Never carry registered Album values across independent saves/replacements.
        let readContext = ModelContext(modelContainer)
        readContext.autosaveEnabled = false
        var descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { album in album.id == albumID }
        )
        descriptor.fetchLimit = 1
        return try? readContext.fetch(descriptor).first?.artworkData
    }
}

public actor ArtworkThumbnailService {
    public typealias AlbumDataLoader = @Sendable (UUID) async -> Data?
    public typealias RemoteArtworkLoader = @Sendable (URL) async throws -> Data
    public typealias DiscogsArtworkLoader = @Sendable (URL, DiscogsContentEvidence) async throws -> Data
    @MainActor public static let shared = ArtworkThumbnailService(
        modelContainer: MediaLibrary.shared.container
    )

    private struct Key: Hashable {
        let reference: ArtworkReference
        let pixelSize: Int
    }

    private struct CachedImage {
        let image: CGImage
        let byteCost: Int
        var access: UInt64
    }

    private struct Generation: Equatable {
        let all: UInt64
        let album: UInt64
    }

    private struct Load {
        let id: UUID
        let task: Task<CGImage?, Never>
    }

    private static let signposter = OSSignposter(
        subsystem: "com.songbird.player",
        category: "ArtworkThumbnail"
    )
    private let dataActor: ArtworkDataModelActor
    private let albumDataLoader: AlbumDataLoader?
    private let maximumImageCount: Int
    private let maximumByteCost: Int
    private let remoteArtworkLoader: RemoteArtworkLoader
    private let clock: @Sendable () -> DiscogsFetchStamp?
    private let discogsArtworkLoader: DiscogsArtworkLoader
    private let expirySleep: @Sendable (TimeInterval) async throws -> Void
    private var cache: [Key: CachedImage] = [:]
    private var inFlight: [Key: Load] = [:]
    private var allGeneration: UInt64 = 0
    private var albumGenerations: [UUID: UInt64] = [:]
    private var accessCounter: UInt64 = 0
    private var byteCost = 0
    private var decodeCount = 0
    private var joinedLoadCount = 0
    private var discogsExpiryTask: Task<Void, Never>?

    public init(
        modelContainer: ModelContainer,
        maximumImageCount: Int = 256,
        maximumByteCost: Int = 64 * 1024 * 1024,
        albumDataLoader: AlbumDataLoader? = nil,
        remoteArtworkLoader: @escaping RemoteArtworkLoader = { url in
            try await URLSession.shared.data(from: url).0
        },
        clock: @escaping @Sendable () -> DiscogsFetchStamp? = { DiscogsClock.sample() },
        discogsSession: URLSession = DiscogsHTTP.makeSession(),
        discogsArtworkLoader: DiscogsArtworkLoader? = nil,
        expirySleep: (@Sendable (TimeInterval) async throws -> Void)? = nil
    ) {
        dataActor = ArtworkDataModelActor(modelContainer: modelContainer)
        self.albumDataLoader = albumDataLoader
        self.maximumImageCount = maximumImageCount
        self.maximumByteCost = maximumByteCost
        self.remoteArtworkLoader = remoteArtworkLoader
        self.clock = clock
        self.expirySleep = expirySleep ?? { @Sendable seconds in
            try await Self.sleepUntilExpiry(seconds)
        }
        let discogs = DiscogsClient(session: discogsSession, clock: clock,
            tokenProvider: { throw DiscogsError.tokenMissing })
        self.discogsArtworkLoader = discogsArtworkLoader ?? { url, evidence in
            try await discogs.downloadImage(from: url, evidence: evidence)
        }
    }

    deinit { discogsExpiryTask?.cancel() }

    public func image(
        for reference: ArtworkReference,
        pointSize: CGSize,
        scale: CGFloat = 2
    ) async -> CGImage? {
        let now = clock()
        pruneExpiredDiscogs(at: now)
        guard isUsable(reference, at: clock()) else { return nil }
        let maxPoint = max(pointSize.width, pointSize.height)
        let pixelSize = max(1, Int(ceil(maxPoint * scale)))
        let key = Key(reference: reference, pixelSize: pixelSize)
        accessCounter &+= 1
        if var cached = cache[key] {
            cached.access = accessCounter
            cache[key] = cached
            guard isUsable(reference, at: clock()) else {
                pruneExpiredDiscogs()
                return nil
            }
            return cached.image
        }
        let generation = generation(for: reference)
        if let load = inFlight[key] {
            joinedLoadCount += 1
            let image = await load.task.value
            pruneExpiredDiscogs()
            guard isUsable(reference, at: clock()), generation == self.generation(for: reference),
                  load.task.isCancelled == false, Task.isCancelled == false else { return nil }
            return image
        }

        let task = Task<CGImage?, Never> { [dataActor, albumDataLoader, remoteArtworkLoader, discogsArtworkLoader, clock] in
            let data: Data?
            switch reference {
            case .album(let albumID, _):
                if let albumDataLoader {
                    data = await albumDataLoader(albumID)
                } else {
                    data = await dataActor.artworkData(for: albumID)
                }
            case .remote(let url):
                data = try? await remoteArtworkLoader(url)
            case .discogsRemote(let url, let evidence):
                guard evidence.isFresh(at: clock()), !Task.isCancelled else { return nil }
                data = try? await discogsArtworkLoader(url, evidence)
                guard evidence.isFresh(at: clock()) else { return nil }
            case .embedded(_, let embeddedData):
                data = embeddedData
            case .songbirdLogo:
                data = Self.songbirdLogoData()
            case .missingAlbumArtwork:
                data = Self.missingAlbumArtworkData()
            }
            guard Task.isCancelled == false, let data else { return nil }
            return Self.downsample(
                data: data,
                pixelSize: pixelSize,
                createsLogoMask: reference == .songbirdLogo
            )
        }
        decodeCount += 1
        let loadID = UUID()
        inFlight[key] = Load(id: loadID, task: task)
        scheduleDiscogsExpiry(at: now)
        let image = await task.value
        pruneExpiredDiscogs()
        guard isUsable(reference, at: clock()), generation == self.generation(for: reference),
              inFlight[key]?.id == loadID, task.isCancelled == false else { return nil }
        inFlight[key] = nil
        guard let image else { return nil }
        guard insert(image, for: key) else { return nil }
        guard isUsable(reference, at: clock()) else {
            pruneExpiredDiscogs()
            return nil
        }
        return Task.isCancelled ? nil : image
    }

    /// Expire only Discogs acquisitions. Cancellation never affects ordinary/local artwork.
    public func pruneExpiredDiscogs() {
        pruneExpiredDiscogs(at: clock())
    }

    private func pruneExpiredDiscogs(at now: DiscogsFetchStamp?) {
        let expired = Set(cache.keys).union(inFlight.keys).filter { !isUsable($0.reference, at: now) }
        for key in expired {
            if let image = cache.removeValue(forKey: key) { byteCost -= image.byteCost }
            inFlight.removeValue(forKey: key)?.task.cancel()
        }
        scheduleDiscogsExpiry(at: now)
    }

    private static func sleepUntilExpiry(_ seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    private func scheduleDiscogsExpiry(at now: DiscogsFetchStamp?) {
        discogsExpiryTask?.cancel()
        discogsExpiryTask = nil
        let fetches = Set(cache.keys).union(inFlight.keys).flatMap { key -> [DiscogsFetchStamp] in
            if case .discogsRemote(_, let evidence) = key.reference { return evidence.fetches }
            return []
        }
        guard let now, !fetches.isEmpty else { return }
        let remaining = fetches.map {
            DiscogsFreshness.maximumAge - max(now.wall.timeIntervalSince($0.wall),
                                               now.continuousSeconds - $0.continuousSeconds)
        }.min() ?? 0
        let delay = max(0.001, min(60, remaining))
        discogsExpiryTask = Task { [weak self, expirySleep] in
            do { try await expirySleep(delay) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.pruneExpiredDiscogs()
        }
    }

    private func isUsable(_ reference: ArtworkReference, at now: DiscogsFetchStamp?) -> Bool {
        if case .discogsRemote(_, let evidence) = reference { return evidence.isFresh(at: now) }
        return true
    }

    public func invalidate(albumID: UUID) {
        invalidate(albumIDs: [albumID])
    }

    public func invalidate(albumIDs: Set<UUID>) {
        for id in albumIDs { albumGenerations[id, default: 0] &+= 1 }
        let keys = Set(cache.keys).union(inFlight.keys).filter { key in
            if case .album(let id, _) = key.reference { return albumIDs.contains(id) }
            return false
        }
        for key in keys {
            if let removed = cache.removeValue(forKey: key) {
                byteCost -= removed.byteCost
            }
            inFlight[key]?.task.cancel()
            inFlight[key] = nil
        }
    }

    public func invalidateAll() {
        discogsExpiryTask?.cancel()
        discogsExpiryTask = nil
        allGeneration &+= 1
        albumGenerations.removeAll(keepingCapacity: true)
        cache.removeAll(keepingCapacity: true)
        byteCost = 0
        for load in inFlight.values { load.task.cancel() }
        inFlight.removeAll(keepingCapacity: true)
    }

    private func generation(for reference: ArtworkReference) -> Generation {
        let album: UInt64
        if case .album(let id, _) = reference {
            album = albumGenerations[id, default: 0]
        } else {
            album = 0
        }
        return Generation(all: allGeneration, album: album)
    }

    func inFlightMetrics() -> (count: Int, joinCount: Int) {
        (inFlight.count, joinedLoadCount)
    }

    public func cacheMetrics() -> (count: Int, byteCost: Int, decodeCount: Int) {
        pruneExpiredDiscogs()
        return (cache.count, byteCost, decodeCount)
    }

    private func insert(_ image: CGImage, for key: Key) -> Bool {
        let now = clock()
        guard isUsable(key.reference, at: now) else { return false }
        accessCounter &+= 1
        let cost = image.bytesPerRow * image.height
        if let old = cache.updateValue(
            CachedImage(image: image, byteCost: cost, access: accessCounter),
            forKey: key
        ) {
            byteCost -= old.byteCost
        }
        byteCost += cost
        while cache.count > maximumImageCount || byteCost > maximumByteCost {
            guard let oldest = cache.min(by: { $0.value.access < $1.value.access }) else { break }
            byteCost -= oldest.value.byteCost
            cache.removeValue(forKey: oldest.key)
        }
        scheduleDiscogsExpiry(at: now)
        return true
    }

    private static func downsample(
        data: Data,
        pixelSize: Int,
        createsLogoMask: Bool = false
    ) -> CGImage? {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("Thumbnail decode", id: signpostID)
        defer { signposter.endInterval("Thumbnail decode", state) }
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }
        return createsLogoMask ? image.creatingDarkSilhouetteMask() : image
    }

    private static let cachedSongbirdLogoData: Data? = {
        resourceData(named: ["songbird-logo", "logo", "transparent"])
    }()

    private static func songbirdLogoData() -> Data? {
        cachedSongbirdLogoData
    }

    private static let cachedMissingAlbumArtworkData: Data? = {
        resourceData(named: ["missing-album-artwork"])
    }()

    private static func resourceData(named names: [String]) -> Data? {
        firstAvailableResourceData(
            packaged: {
                resourceData(named: names, in: .main, subdirectories: [nil])
            },
            swiftPackage: {
                // Bundle.module's generated accessor traps when its SwiftPM
                // bundle and original build directory are both absent. Keep it
                // inside this lazy development/test fallback.
                resourceData(
                    named: names,
                    in: .module,
                    subdirectories: ["Resources", nil]
                )
            }
        )
    }

    static func firstAvailableResourceData(
        packaged: () -> Data?,
        swiftPackage: () -> Data?
    ) -> Data? {
        if let packagedData = packaged() { return packagedData }
        return swiftPackage()
    }

    private static func resourceData(
        named names: [String],
        in bundle: Bundle,
        subdirectories: [String?]
    ) -> Data? {
        for name in names {
            for subdirectory in subdirectories {
                guard let url = bundle.url(
                    forResource: name,
                    withExtension: "png",
                    subdirectory: subdirectory
                ) else { continue }
                if let data = try? Data(contentsOf: url) { return data }
            }
        }
        return nil
    }

    private static func missingAlbumArtworkData() -> Data? {
        cachedMissingAlbumArtworkData
    }
}

private extension CGImage {
    /// Rebuilds transparency from the clean master's dark-on-light pixels instead
    /// of trusting either legacy alpha channel. Work runs in the thumbnail task.
    func creatingDarkSilhouetteMask() -> CGImage {
        guard width > 0, height > 0 else { return self }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue

        return pixels.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ) else { return self }

            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            for index in 0..<(width * height) {
                let pixel = index * 4
                let red = Double(bytes[pixel])
                let green = Double(bytes[pixel + 1])
                let blue = Double(bytes[pixel + 2])
                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                let darkness = max(0, 255 - luminance)
                let alpha = UInt8(max(0, min(255, (darkness - 48) * 255 / 80)))
                bytes[pixel] = 0
                bytes[pixel + 1] = 0
                bytes[pixel + 2] = 0
                bytes[pixel + 3] = alpha
            }

            return context.makeImage() ?? self
        }
    }
}
