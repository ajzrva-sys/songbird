// Optional record-style artwork generator; the bundled bird images are retained assets.
// Generate into a separate output directory; see publication/artwork-decision.json.
import AppKit
import CryptoKit
import Foundation

@main
struct GenerateOriginalArtwork {
    private struct Entry: Codable { let name: String; let sha256: String }
    private struct Manifest: Codable {
        let schema: Int
        let method: String
        let license: String
        let generator: String
        let catalog: String
        let files: [Entry]
    }

    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "ArtworkGenerator", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Usage: generate-original-artwork OUTPUT_DIRECTORY"
            ])
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var assets: [String: Data] = [:]
        for variant in SongbirdArtworkCatalog.dockVariants {
            assets[variant.name + ".png"] = try render(
                background: color(variant.background), accent: color(variant.accent), logo: false
            )
        }
        assets["dock-icon.png"] = assets["dock-icon-blue-outline.png"]!
        let logo = try render(background: .clear, accent: .black, logo: true)
        for name in ["songbird-logo.png", "logo.png", "transparent.png"] { assets[name] = logo }
        assets["missing-album-artwork.png"] = try render(
            background: color(0xD8DADD), accent: color(0x939BA3), logo: false
        )
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
          <g fill="none" stroke="currentColor" stroke-width="1.5">
            <circle cx="16" cy="16" r="13"/>
            <circle cx="16" cy="16" r="4"/>
            <circle cx="16" cy="16" r="1"/>
          </g>
        </svg>
        """
        assets["audio-cd-mark.svg"] = Data((svg + "\n").utf8)
        var entries: [Entry] = []
        for name in assets.keys.sorted() {
            let data = assets[name]!
            let destination = output.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw NSError(domain: "ArtworkGenerator", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Refusing to overwrite " + name
                ])
            }
            try data.write(to: destination, options: .atomic)
            entries.append(Entry(name: name, sha256: SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }.joined()))
        }
        let manifest = Manifest(
            schema: 1, method: "project-authored-geometric-renderer",
            license: "GPL-3.0-or-later", generator: "scripts/generate-original-artwork.swift",
            catalog: "Sources/DockIconSupport/SongbirdArtworkCatalog.swift", files: entries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: output.appendingPathComponent("asset-provenance.json"))
        print("Generated \(entries.count) original geometric images and provenance")
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    @MainActor
    private static func render(background: NSColor, accent: NSColor, logo: Bool) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "ArtworkGenerator", code: 4)
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.shouldAntialias = true
        context.cgContext.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        if !logo {
            background.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024),
                         xRadius: 180, yRadius: 180).fill()
        }
        (logo ? NSColor.black : NSColor(white: 0.12, alpha: 1)).setFill()
        NSBezierPath(ovalIn: NSRect(x: 184, y: 184, width: 656, height: 656)).fill()
        for radius in [CGFloat(224), CGFloat(264), CGFloat(304)] {
            let groove = NSBezierPath(ovalIn: NSRect(
                x: 512 - radius, y: 512 - radius, width: radius * 2, height: radius * 2
            ))
            groove.lineWidth = logo ? 14 : 6
            if logo {
                context.cgContext.setBlendMode(.clear)
                NSColor.black.setStroke()
                groove.stroke()
                context.cgContext.setBlendMode(.normal)
            } else {
                NSColor(white: 0.28, alpha: 1).setStroke()
                groove.stroke()
            }
        }
        if logo {
            context.cgContext.setBlendMode(.clear)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 480, y: 480, width: 64, height: 64)).fill()
            context.cgContext.setBlendMode(.normal)
        } else {
            accent.setFill()
            NSBezierPath(ovalIn: NSRect(x: 414, y: 414, width: 196, height: 196)).fill()
            background.setFill()
            NSBezierPath(ovalIn: NSRect(x: 494, y: 494, width: 36, height: 36)).fill()
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ArtworkGenerator", code: 5)
        }
        return data
    }
}
