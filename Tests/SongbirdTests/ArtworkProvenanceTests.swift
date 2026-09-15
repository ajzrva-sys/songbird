import CryptoKit
import Foundation
import XCTest
@testable import SongbirdLib

final class ArtworkProvenanceTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private struct Manifest: Decodable {
        let schema: Int
        let method: String
        let license: String
        let files: [Entry]
    }

    private struct Entry: Decodable {
        let name: String
        let sha256: String
    }

    func testREADMEGalleryMatchesRecordedScreenshots() throws {
        struct ScreenshotManifest: Decodable {
            struct Image: Decodable {
                let file: String
                let sha256: String
                let bytes: Int
            }
            let status: String?
            let images: [Image]
        }
        struct RetiredAssets: Decodable { let before_paths: [String] }
        let screenshots = root.appendingPathComponent("docs/screenshots")
        let metadata = try JSONDecoder().decode(ScreenshotManifest.self, from:
            Data(contentsOf: screenshots.appendingPathComponent("manifest.json")))
        XCTAssertEqual(metadata.status, "captured")
        XCTAssertFalse(metadata.images.isEmpty)
        let names = Set(metadata.images.map(\.file))
        XCTAssertEqual(names.count, metadata.images.count)
        let actual = try FileManager.default.contentsOfDirectory(
            at: screenshots, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "png" }
        XCTAssertEqual(Set(actual.map(\.lastPathComponent)), names)
        let retired = try JSONDecoder().decode(RetiredAssets.self, from:
            Data(contentsOf: root.appendingPathComponent("publication/retired-asset-hashes.json")))
        let oldScreenshots = retired.before_paths.filter { $0.hasPrefix("docs/screenshots/") }
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        let notes = try String(contentsOf: screenshots.appendingPathComponent("README.md"), encoding: .utf8)
        for entry in metadata.images {
            let data = try Data(contentsOf: screenshots.appendingPathComponent(entry.file))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, entry.sha256, entry.file)
            XCTAssertEqual(data.count, entry.bytes, entry.file)
            XCTAssertTrue(readme.contains("](docs/screenshots/" + entry.file + ")"), entry.file)
            XCTAssertTrue(notes.contains("](" + entry.file + ")"), entry.file)
        }
        for path in oldScreenshots {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), path)
            XCTAssertFalse(readme.contains("](" + path + ")"), path)
            XCTAssertFalse(notes.contains("](" + URL(fileURLWithPath: path).lastPathComponent + ")"), path)
        }
    }

    func testEveryRuntimeImageMatchesRecordedProvenance() throws {
        let folder = root.appendingPathComponent("Sources/Resources")
        let manifestURL = folder.appendingPathComponent("asset-provenance.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path),
                      "Runtime images need recorded file provenance")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        XCTAssertEqual(manifest.schema, 1)
        XCTAssertEqual(manifest.method, "owner-approved-retained-artwork")
        XCTAssertFalse(manifest.license.isEmpty)
        let actual = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        ).filter { ["png", "svg"].contains($0.pathExtension) }
        XCTAssertEqual(Set(actual.map(\.lastPathComponent)), Set(manifest.files.map(\.name)))
        XCTAssertEqual(manifest.files.count, Set(manifest.files.map(\.name)).count)
        for entry in manifest.files {
            let data = try Data(contentsOf: folder.appendingPathComponent(entry.name))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, entry.sha256, entry.name)
        }
        let dockNames = Set(SongbirdDockIconChoice.allCases.map { $0.resourceName + ".png" })
        XCTAssertTrue(dockNames.isSubset(of: Set(manifest.files.map(\.name))))
    }
}
