import AppKit
import Foundation

public enum SongbirdDockIconArtwork {
    public static let activeResourceStorageKey = "songbird.dockIcon.activeResource"

    public static func changeNotificationName(
        bundleIdentifier: String
    ) -> Notification.Name {
        Notification.Name("\(bundleIdentifier).dockIconDidChange")
    }

    public static func validatedResourceName(_ resourceName: String?) -> String? {
        guard let resourceName, sourceCrops[resourceName] != nil else { return nil }
        return resourceName
    }

    public static func dockReadyImage(
        from sourceImage: NSImage,
        resourceName: String
    ) -> NSImage {
        let pixelDimension = Int(canvasDimension)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelDimension,
            pixelsHigh: pixelDimension,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return sourceImage
        }

        bitmap.size = NSSize(width: canvasDimension, height: canvasDimension)
        let tileOrigin = (canvasDimension - opticalTileDimension) / 2
        let destinationRect = NSRect(
            x: tileOrigin,
            y: tileOrigin,
            width: opticalTileDimension,
            height: opticalTileDimension
        )
        let sourceRect = sourceRect(
            resourceName: resourceName,
            imageSize: sourceImage.size
        )

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            context.shouldAntialias = true
            context.cgContext.clear(
                CGRect(
                    x: 0,
                    y: 0,
                    width: canvasDimension,
                    height: canvasDimension
                )
            )

            let clippedTileRect = destinationRect.insetBy(
                dx: edgeCleanupInset,
                dy: edgeCleanupInset
            )
            NSBezierPath(
                roundedRect: clippedTileRect,
                xRadius: clippedTileRect.width * 0.22,
                yRadius: clippedTileRect.height * 0.22
            ).addClip()
            sourceImage.draw(
                in: destinationRect,
                from: sourceRect,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(
            size: NSSize(width: canvasDimension, height: canvasDimension)
        )
        result.addRepresentation(bitmap)
        return result
    }

    private static let canvasDimension: CGFloat = 1024
    private static let opticalTileDimension: CGFloat = 824
    private static let edgeCleanupInset: CGFloat = 6

    private struct SourceCrop {
        let left: CGFloat
        let top: CGFloat
        let right: CGFloat
        let bottom: CGFloat
    }

    private static func sourceRect(
        resourceName: String,
        imageSize: NSSize
    ) -> NSRect {
        let crop = sourceCrops[resourceName]
            ?? SourceCrop(left: 0, top: 0, right: 1024, bottom: 1024)
        let horizontalScale = imageSize.width / canvasDimension
        let verticalScale = imageSize.height / canvasDimension
        return NSRect(
            x: crop.left * horizontalScale,
            y: (canvasDimension - crop.bottom) * verticalScale,
            width: (crop.right - crop.left) * horizontalScale,
            height: (crop.bottom - crop.top) * verticalScale
        )
    }

    private static let sourceCrops: [String: SourceCrop] = [
        "dock-icon-blackbird-amber": SourceCrop(left: 58, top: 42, right: 965, bottom: 973),
        "dock-icon-blackbird-graphite": SourceCrop(left: 75, top: 51, right: 948, bottom: 934),
        "dock-icon-blue-outline": SourceCrop(left: 56, top: 46, right: 967, bottom: 960),
        "dock-icon-blue-vinyl": SourceCrop(left: 51, top: 43, right: 969, bottom: 968),
        "dock-icon-bowie-prism": SourceCrop(left: 0, top: 0, right: 1024, bottom: 1024),
        "dock-icon-bowie-silver-blue": SourceCrop(left: 57, top: 44, right: 968, bottom: 960),
        "dock-icon-dove-marble": SourceCrop(left: 56, top: 59, right: 983, bottom: 1024),
        "dock-icon-dove-pearl": SourceCrop(left: 65, top: 62, right: 985, bottom: 1024),
        "dock-icon-gonzo-dark": SourceCrop(left: 74, top: 51, right: 950, bottom: 951),
        "dock-icon-gonzo-light": SourceCrop(left: 57, top: 46, right: 967, bottom: 962),
        "dock-icon-music-dark-red": SourceCrop(left: 16, top: 21, right: 1008, bottom: 1014),
        "dock-icon-music-light-lacquer": SourceCrop(left: 65, top: 43, right: 962, bottom: 1008),
        "dock-icon-nightingale-glass": SourceCrop(left: 0, top: 0, right: 1024, bottom: 1024),
        "dock-icon-nightingale-glow": SourceCrop(left: 56, top: 46, right: 966, bottom: 959),
        "dock-icon-pink-burgundy": SourceCrop(left: 67, top: 47, right: 957, bottom: 965),
        "dock-icon-pink-lacquer": SourceCrop(left: 76, top: 66, right: 949, bottom: 946),
        "dock-icon-pink-terrazzo": SourceCrop(left: 55, top: 42, right: 967, bottom: 963),
        "dock-icon-purple-neon": SourceCrop(left: 65, top: 62, right: 958, bottom: 956),
        "dock-icon-purple-rim": SourceCrop(left: 86, top: 67, right: 943, bottom: 926),
        "dock-icon-silverwing-frame": SourceCrop(left: 0, top: 42, right: 891, bottom: 1006),
        "dock-icon-silverwing-graphite": SourceCrop(left: 62, top: 34, right: 950, bottom: 990),
    ]
}
