import Foundation

public struct AudioCDMetadataTrack: Codable, Equatable, Sendable {
    public let number: Int
    public let title: String
    public let artist: String
}

public struct AudioCDMetadataCandidate: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let country: String?
    public let date: String?
    public let tracks: [AudioCDMetadataTrack]
    public let artworkURL: URL?
    public let score: Int
    public let discogsEvidence: DiscogsContentEvidence?

    public init(id: String, title: String, artist: String, country: String?, date: String?,
                tracks: [AudioCDMetadataTrack], artworkURL: URL?, score: Int,
                discogsEvidence: DiscogsContentEvidence? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.country = country
        self.date = date
        self.tracks = tracks
        self.artworkURL = artworkURL
        self.score = score
        self.discogsEvidence = discogsEvidence
    }
}

public struct AudioCDMetadataQuery: Equatable, Sendable {
    public struct Track: Equatable, Sendable {
        public let number: Int
        public let duration: TimeInterval

        public init(number: Int, duration: TimeInterval) {
            self.number = number
            self.duration = duration
        }
    }

    public let discID: String
    public let albumTitle: String?
    public let albumArtist: String?
    public let tracks: [Track]

    public init(
        discID: String,
        albumTitle: String? = nil,
        albumArtist: String? = nil,
        tracks: [Track]
    ) {
        self.discID = discID
        self.albumTitle = albumTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.albumArtist = albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.tracks = tracks
    }

    public var trackCount: Int { tracks.count }
}

public protocol AudioCDMetadataProviding: Sendable {
    func candidates(for query: AudioCDMetadataQuery) async throws -> [AudioCDMetadataCandidate]
}

public extension AudioCDMetadataProviding {
    func candidates(discID: String, trackCount: Int) async throws -> [AudioCDMetadataCandidate] {
        let tracks = trackCount > 0
            ? (1...trackCount).map { AudioCDMetadataQuery.Track(number: $0, duration: 0) }
            : []
        return try await candidates(for: AudioCDMetadataQuery(
            discID: discID,
            tracks: tracks
        ))
    }
}

public struct DisabledAudioCDMetadataProvider: AudioCDMetadataProviding {
    public init() {}
    public func candidates(for query: AudioCDMetadataQuery) async throws -> [AudioCDMetadataCandidate] { [] }
}

public protocol MusicBrainzHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: MusicBrainzHTTPClient {
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request, delegate: nil)
        guard let http = response as? HTTPURLResponse else { throw MusicBrainzError.invalidResponse }
        return (data, http)
    }
}

public enum MusicBrainzError: Error, LocalizedError, Equatable {
    case disabled
    case invalidResponse
    case server(Int)
    case decoding

    public var errorDescription: String? {
        switch self {
        case .disabled: "Online CD metadata is disabled until a contact URL or email is configured."
        case .invalidResponse: "MusicBrainz returned an invalid response."
        case .server(let status): "MusicBrainz returned HTTP \(status)."
        case .decoding: "Songbird could not understand the MusicBrainz response."
        }
    }
}

public actor MusicBrainzCDMetadataClient: AudioCDMetadataProviding {
    private let contact: String?
    private let http: any MusicBrainzHTTPClient
    private let cache: AudioCDMetadataCache
    private var lastRequest: ContinuousClock.Instant?

    public init(
        contact: String?,
        http: any MusicBrainzHTTPClient = URLSession.shared,
        cache: AudioCDMetadataCache = AudioCDMetadataCache()
    ) {
        self.contact = contact?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.http = http
        self.cache = cache
    }

    public init(
        contactURL: URL?,
        http: any MusicBrainzHTTPClient = URLSession.shared,
        cache: AudioCDMetadataCache = AudioCDMetadataCache()
    ) {
        self.init(contact: contactURL?.absoluteString, http: http, cache: cache)
    }

    public func candidates(for query: AudioCDMetadataQuery) async throws -> [AudioCDMetadataCandidate] {
        if let cached = await cache.load(discID: query.discID) { return cached }
        guard let contact else { throw MusicBrainzError.disabled }
        if let lastRequest {
            let elapsed = lastRequest.duration(to: .now)
            if elapsed < .seconds(1) {
                try await Task.sleep(for: .seconds(1) - elapsed)
            }
        }
        try Task.checkCancellation()
        guard var components = URLComponents(
            string: "https://musicbrainz.org/ws/2/discid/\(query.discID)"
        ) else { throw MusicBrainzError.invalidResponse }
        components.queryItems = [
            URLQueryItem(name: "fmt", value: "json"),
            // DiscID lookups include releases/media by default. Asking for
            // `media` explicitly is rejected by the endpoint with HTTP 400.
            URLQueryItem(name: "inc", value: "recordings+artist-credits"),
        ]
        guard let url = components.url else { throw MusicBrainzError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue(
            "Songbird/0.1 (\(contact))",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 15
        lastRequest = .now
        let (data, response) = try await http.data(for: request)
        if response.statusCode == 404 {
            await cache.store([], discID: query.discID)
            return []
        }
        guard response.statusCode == 200 else { throw MusicBrainzError.server(response.statusCode) }
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
            throw MusicBrainzError.decoding
        }
        let candidates = payload.releases.compactMap { release -> AudioCDMetadataCandidate? in
            guard let medium = release.media.first(where: { $0.tracks.count == query.trackCount })
                ?? release.media.first else { return nil }
            let tracks = medium.tracks.map { track in
                AudioCDMetadataTrack(
                    number: track.position,
                    title: track.title ?? track.recording?.title ?? "Track \(track.position)",
                    artist: Self.credit(track.artistCredit).ifEmpty(Self.credit(release.artistCredit))
                )
            }
            let exactCount = tracks.count == query.trackCount
            let official = release.status?.lowercased() == "official"
            let score = (exactCount ? 100 : 0) + (official ? 10 : 0) + (release.country != nil ? 1 : 0)
            return AudioCDMetadataCandidate(
                id: release.id,
                title: release.title,
                artist: Self.credit(release.artistCredit),
                country: release.country,
                date: release.date,
                tracks: tracks,
                artworkURL: URL(string: "https://coverartarchive.org/release/\(release.id)/front-500"),
                score: score
            )
        }.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return ($0.date ?? "") < ($1.date ?? "")
        }
        await cache.store(candidates, discID: query.discID)
        return candidates
    }

    private static func credit(_ credits: [Credit]?) -> String {
        credits?.map { $0.name }.joined(separator: " & ") ?? "Unknown Artist"
    }

    private struct Response: Decodable {
        let releases: [Release]
    }

    private struct Release: Decodable {
        let id: String
        let title: String
        let status: String?
        let country: String?
        let date: String?
        let artistCredit: [Credit]?
        let media: [Medium]

        enum CodingKeys: String, CodingKey {
            case id, title, status, country, date, media
            case artistCredit = "artist-credit"
        }
    }

    private struct Medium: Decodable { let tracks: [RemoteTrack] }
    private struct RemoteTrack: Decodable {
        let position: Int
        let title: String?
        let recording: Recording?
        let artistCredit: [Credit]?

        enum CodingKeys: String, CodingKey {
            case position, title, recording
            case artistCredit = "artist-credit"
        }
    }
    private struct Recording: Decodable { let title: String? }
    private struct Credit: Decodable { let name: String }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

public actor AudioCDMetadataCache {
    private struct Entry: Codable {
        let storedAt: Date
        let candidates: [AudioCDMetadataCandidate]
    }

    private let directory: URL
    private let lifetime: TimeInterval
    private let discogsClock: @Sendable () -> DiscogsFetchStamp?
    private let discogsCache: DiscogsResponseCache<[AudioCDMetadataCandidate]>

    public init(directory: URL? = nil, lifetime: TimeInterval = 30 * 24 * 60 * 60,
                clock: @escaping @Sendable () -> DiscogsFetchStamp? = { DiscogsClock.sample() }) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Songbird/CDMetadata", isDirectory: true)
        self.lifetime = lifetime
        self.discogsClock = clock
        discogsCache = DiscogsResponseCache(
            fileURL: self.directory.appendingPathComponent("discogs-responses-v2.json"),
            maximumAge: lifetime, clock: clock
        )
    }

    public func loadDiscogs(discID: String) async -> DiscogsResponseCache<[AudioCDMetadataCandidate]>.Hit? {
        guard let hit = await discogsCache.value(for: discID),
              !Task.isCancelled,
              Self.hasDiscogsEvidence(hit.value, fetches: hit.fetches),
              freshDiscogs(hit.fetches) else { return nil }
        return hit
    }

    @discardableResult
    public func storeDiscogs(_ candidates: [AudioCDMetadataCandidate], discID: String,
                             fetches: [DiscogsFetchStamp]) async -> Bool {
        guard !Task.isCancelled, Self.hasDiscogsEvidence(candidates, fetches: fetches) else { return false }
        let accepted = await discogsCache.store(candidates, fetches: fetches, for: discID)
        return accepted && !Task.isCancelled && freshDiscogs(fetches)
    }

    private func freshDiscogs(_ fetches: [DiscogsFetchStamp]) -> Bool {
        let now = discogsClock()
        return !fetches.isEmpty && fetches.allSatisfy {
            DiscogsFreshness.isFresh($0, at: now, maximumAge: lifetime)
        }
    }

    private static func hasDiscogsEvidence(_ candidates: [AudioCDMetadataCandidate],
                                           fetches: [DiscogsFetchStamp]) -> Bool {
        candidates.allSatisfy { candidate in
            guard let evidence = candidate.discogsEvidence,
                  evidence.releaseID > 0, !evidence.fetches.isEmpty else { return false }
            return evidence.fetches.allSatisfy { fetches.contains($0) }
        }
    }

    public func load(discID: String) -> [AudioCDMetadataCandidate]? {
        guard let data = try? Data(contentsOf: url(for: discID)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              Date().timeIntervalSince(entry.storedAt) < lifetime else { return nil }
        return entry.candidates
    }

    public func store(_ candidates: [AudioCDMetadataCandidate], discID: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Entry(storedAt: Date(), candidates: candidates)) else {
            return
        }
        try? data.write(to: url(for: discID), options: .atomic)
    }

    private func url(for discID: String) -> URL {
        let safe = discID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? discID
        return directory.appendingPathComponent(safe).appendingPathExtension("json")
    }
}
