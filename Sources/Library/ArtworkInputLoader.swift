import Foundation
import ImageIO

public enum ArtworkInputError: Error, LocalizedError, Equatable {
    case tooLarge(maximumMegabytes: Int)
    case invalidImage
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .tooLarge(let maximumMegabytes):
            "Artwork must be smaller than \(maximumMegabytes) MB."
        case .invalidImage:
            "The selected file is not a supported image."
        case .unreadable(let message):
            "The artwork could not be read: \(message)"
        }
    }
}

public actor ArtworkInputLoader {
    public static let maximumBytes = 16 * 1024 * 1024

    public init() {}

    public func load(from url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            return try validate(Data(contentsOf: url))
        } catch let error as ArtworkInputError {
            throw error
        } catch {
            throw ArtworkInputError.unreadable(error.localizedDescription)
        }
    }

    public func validate(_ data: Data) throws -> Data {
        guard data.count <= Self.maximumBytes else {
            throw ArtworkInputError.tooLarge(maximumMegabytes: 16)
        }
        guard CGImageSourceCreateWithData(data as CFData, nil) != nil else {
            throw ArtworkInputError.invalidImage
        }
        return data
    }
}
