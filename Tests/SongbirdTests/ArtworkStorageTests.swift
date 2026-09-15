import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SongbirdLib

final class ArtworkStorageTests: XCTestCase {
    func testLargeArtworkIsDownsampledForLibraryStorage() throws {
        let source = try makeJPEG(width: 2_400, height: 1_600)
        let normalized = ArtworkStorage.normalized(source)
        let size = try XCTUnwrap(ArtworkStorage.pixelSize(of: normalized))

        XCTAssertLessThan(normalized.count, source.count)
        XCTAssertLessThanOrEqual(max(size.width, size.height), ArtworkStorage.maximumPixelSize)
    }

    func testSmallArtworkIsPreservedByteForByte() throws {
        let source = try makeJPEG(width: 320, height: 320)

        XCTAssertEqual(ArtworkStorage.normalized(source), source)
    }

    func testInvalidArtworkIsPreservedInsteadOfDiscarded() {
        let source = Data("not an image".utf8)

        XCTAssertEqual(ArtworkStorage.normalized(source), source)
    }

    private func makeJPEG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.08, green: 0.48, blue: 0.92, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
