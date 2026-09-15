import Foundation

// MARK: - Search types

public struct DiscogsArtworkSearchQuery: Equatable, Sendable {
    public let albumTitle: String
    public let albumArtist: String
    public let year: Int?

    public init(albumTitle: String, albumArtist: String, year: Int? = nil) {
        self.albumTitle = albumTitle
        self.albumArtist = albumArtist
        self.year = year
    }
}

public struct DiscogsArtworkCandidate: Identifiable, Equatable, Codable, Sendable {
    public let id: Int
    public let title: String
    public let artist: String
    public let year: Int?
    public let country: String?
    public let formats: [String]
    public let genres: [String]
    public let styles: [String]
    public let thumbnailURL: URL?
    public let imageURL: URL
    public let sourcePageURL: URL
    public let fetchedAt: DiscogsFetchStamp

    public var evidence: DiscogsContentEvidence {
        DiscogsContentEvidence(releaseID: id, fetches: [fetchedAt])
    }
}

public struct DiscogsSearchPage: Equatable, Sendable {
    public let candidates: [DiscogsArtworkCandidate]
    public let page: Int
    public let totalPages: Int
    public let fetchedAt: DiscogsFetchStamp
}

// MARK: - Client protocol

public protocol DiscogsSearching: Sendable {
    func search(_ query: DiscogsArtworkSearchQuery, page: Int) async throws -> DiscogsSearchPage
}

public struct DiscogsReleaseMetadata: Equatable, Sendable {
    public struct Track: Equatable, Sendable {
        public let number: Int
        public let title: String
        public let duration: TimeInterval?
    }

    public let id: Int
    public let title: String
    public let artist: String
    public let year: Int?
    public let country: String?
    public let formats: [String]
    public let tracks: [Track]
    public let artworkURL: URL?
    public let fetchedAt: DiscogsFetchStamp

    public var sourcePageURL: URL? { evidence.sourcePageURL }
    public var evidence: DiscogsContentEvidence {
        DiscogsContentEvidence(releaseID: id, fetches: [fetchedAt])
    }
}

public protocol DiscogsCDSearching: DiscogsSearching {
    func releaseMetadata(id: Int) async throws -> DiscogsReleaseMetadata
}

// MARK: - Errors

public enum DiscogsError: Error, LocalizedError {
    case tokenMissing
    case tokenInvalid
    case rateLimited(retryAfter: TimeInterval?)
    case networkUnavailable
    case serverUnavailable
    case noResults
    case decodingFailed
    case imageDownloadFailed
    case freshnessUnavailable
    case resultsExpired

    public var errorDescription: String? {
        switch self {
        case .tokenMissing:
            return "No Discogs token configured. Add one in Settings."
        case .tokenInvalid:
            return "Discogs token was rejected. Check Settings."
        case .rateLimited(let retry):
            if let seconds = retry {
                return "Rate limited. Retry after \(Int(seconds))s."
            }
            return "Rate limited. Wait before retrying."
        case .networkUnavailable:
            return "Network unavailable."
        case .serverUnavailable:
            return "Discogs is currently unavailable."
        case .noResults:
            return "No matching releases found."
        case .decodingFailed:
            return "Could not understand the Discogs response."
        case .resultsExpired:
            return "Discogs results expired. Search again."
        case .freshnessUnavailable:
            return "Discogs freshness could not be verified. Try again."
        case .imageDownloadFailed:
            return "Could not download the artwork."
        }
    }
}

// MARK: - Discogs API response shapes (internal)

struct DiscogsSearchResponse: Decodable {
    struct Result: Decodable {
        let id: Int
        let title: String?
        let year: Int?
        let country: String?
        let format: [String]?
        let genre: [String]?
        let style: [String]?
        let thumb: String?
        let coverImage: String?
        let resourceUrl: String?

        enum CodingKeys: String, CodingKey {
            case id, title, year, country, format, genre, style, thumb
            case coverImage = "cover_image"
            case resourceUrl = "resource_url"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            country = try container.decodeIfPresent(String.self, forKey: .country)
            format = try container.decodeIfPresent([String].self, forKey: .format)
            genre = try container.decodeIfPresent([String].self, forKey: .genre)
            style = try container.decodeIfPresent([String].self, forKey: .style)
            thumb = try container.decodeIfPresent(String.self, forKey: .thumb)
            coverImage = try container.decodeIfPresent(String.self, forKey: .coverImage)
            resourceUrl = try container.decodeIfPresent(String.self, forKey: .resourceUrl)

            if let numericYear = try? container.decodeIfPresent(Int.self, forKey: .year) {
                year = numericYear
            } else if let stringYear = try? container.decodeIfPresent(String.self, forKey: .year) {
                year = Int(stringYear)
            } else {
                year = nil
            }
        }
    }

    struct Pagination: Decodable {
        let page: Int?
        let pages: Int?
    }

    let results: [Result]?
    let pagination: Pagination?
}

struct DiscogsReleaseResponse: Decodable {
    struct Artist: Decodable { let name: String }
    struct Format: Decodable { let name: String }
    struct Track: Decodable {
        let position: String
        let title: String
        let duration: String?
        let type: String?

        enum CodingKeys: String, CodingKey {
            case position, title, duration
            case type = "type_"
        }
    }
    struct Image: Decodable {
        let type: String?
        let uri: String?
        let uri150: String?

        enum CodingKeys: String, CodingKey {
            case type, uri
            case uri150 = "uri150"
        }
    }

    let id: Int
    let title: String
    let artists: [Artist]?
    let artistsSort: String?
    let year: Int?
    let country: String?
    let formats: [Format]?
    let tracklist: [Track]?
    let images: [Image]?

    enum CodingKeys: String, CodingKey {
        case id, title, artists, year, country, formats, tracklist, images
        case artistsSort = "artists_sort"
    }
}
