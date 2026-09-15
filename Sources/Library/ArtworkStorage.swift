import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

public enum ArtworkStorage {
    public static let maximumPixelSize = 768
    public static let inlineByteThreshold = 384 * 1024

    /// Keeps enough resolution for Retina album tiles while preventing embedded
    /// multi-megapixel covers from dominating the library store and process RAM.
    public static func normalized(_ data: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return data
        }

        guard data.count > inlineByteThreshold
                || max(width, height) > maximumPixelSize else {
            return data
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return data
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return data
        }
        CGImageDestinationAddImage(
            destination,
            thumbnail,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination), !output.isEmpty else {
            return data
        }
        return output as Data
    }

    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
    }
}

public enum ArtworkMaintenance {
    private static let completionKey = "songbird.artworkStorage.compacted.v1"
    @MainActor private static var task: Task<Void, Never>?

    @MainActor
    public static func startIfNeeded(in container: ModelContainer) {
        guard task == nil,
              !UserDefaults.standard.bool(forKey: completionKey) else {
            return
        }

        task = Task {
            let completed = await compactLibrary(in: container)
            if completed {
                UserDefaults.standard.set(true, forKey: completionKey)
            }
            task = nil
        }
    }

    private static func compactLibrary(in container: ModelContainer) async -> Bool {
        await Task.detached(priority: .utility) {
            let batchSize = 24
            var offset = 0

            do {
                while true {
                    let context = ModelContext(container)
                    var descriptor = FetchDescriptor<Album>(
                        sortBy: [
                            SortDescriptor(\Album.dateAdded),
                            SortDescriptor(\Album.title),
                        ]
                    )
                    descriptor.fetchLimit = batchSize
                    descriptor.fetchOffset = offset
                    let albums = try context.fetch(descriptor)
                    guard !albums.isEmpty else { break }

                    var changed = false
                    for album in albums {
                        guard let artwork = album.artworkData else { continue }
                        let normalized = ArtworkStorage.normalized(artwork)
                        if normalized.count < artwork.count {
                            album.artworkData = normalized
                            changed = true
                        }
                    }
                    if changed {
                        try context.save()
                    }
                    offset += albums.count
                }
                return true
            } catch {
                NSLog("Songbird: artwork compaction failed: %@", "\(error)")
                return false
            }
        }.value
    }
}
