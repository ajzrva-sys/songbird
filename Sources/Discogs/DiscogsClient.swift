import Foundation

public final class DiscogsClient: DiscogsCDSearching, @unchecked Sendable {
    private let session: URLSession
    private let clock: @Sendable () -> DiscogsFetchStamp?
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let userAgent: String
    private let tokenProvider: @Sendable () async throws -> String
    private let baseURL = URL(string: "https://api.discogs.com")!

    private static let defaultUserAgent = "Songbird/1.0 (macOS; personal/noncommercial)"

    public init(
        session: URLSession = DiscogsHTTP.makeSession(),
        userAgent: String = "Songbird/1.0 (macOS; personal/noncommercial)",
        clock: @escaping @Sendable () -> DiscogsFetchStamp? = { DiscogsClock.sample() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(for: .seconds($0))
        },
        tokenProvider: @escaping @Sendable () async throws -> String
    ) {
        self.session = session
        self.clock = clock
        self.sleep = sleep
        self.userAgent = userAgent
        self.tokenProvider = tokenProvider
    }

    private func requireFresh(_ fetches: [DiscogsFetchStamp]) throws {
        guard let now = clock() else { throw DiscogsError.freshnessUnavailable }
        guard !fetches.isEmpty, fetches.allSatisfy({ DiscogsFreshness.isFresh($0, at: now) }) else {
            throw DiscogsError.resultsExpired
        }
    }

    // MARK: - Search

    public func search(
        _ query: DiscogsArtworkSearchQuery,
        page: Int
    ) async throws -> DiscogsSearchPage {
        let token: String
        do {
            token = try await tokenProvider()
        } catch {
            throw DiscogsError.tokenMissing
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("database/search"),
            resolvingAgainstBaseURL: false
        )!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: "20"),
        ]
        // Build search term: artist + title. If year is known, append it.
        var searchTerms: [String] = []
        let artist = query.albumArtist.trimmingCharacters(in: .whitespaces)
        let title = query.albumTitle.trimmingCharacters(in: .whitespaces)
        if !artist.isEmpty { searchTerms.append(artist) }
        if !title.isEmpty { searchTerms.append(title) }
        let searchStr = searchTerms.joined(separator: " ")
        if !searchStr.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: searchStr))
        }
        if let year = query.year, year > 0 {
            queryItems.append(URLQueryItem(name: "year", value: String(year)))
        }
        // Discogs token auth: query param OR header. Query param is simpler.
        queryItems.append(URLQueryItem(name: "token", value: token))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw DiscogsError.noResults
        }

        let request = DiscogsHTTP.request(url: url, userAgent: userAgent)

        guard let fetchedAt = clock() else { throw DiscogsError.freshnessUnavailable }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        try requireFresh([fetchedAt])

        let http = response

        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw DiscogsError.tokenInvalid
        case 404:
            throw DiscogsError.noResults
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw DiscogsError.rateLimited(retryAfter: retry)
        case 500...599:
            throw DiscogsError.serverUnavailable
        default:
            throw DiscogsError.serverUnavailable
        }

        let decoded: DiscogsSearchResponse
        do {
            decoded = try JSONDecoder().decode(DiscogsSearchResponse.self, from: data)
        } catch {
            throw DiscogsError.decodingFailed
        }

        let results = decoded.results ?? []
        let candidates: [DiscogsArtworkCandidate] = results.compactMap { result in
            guard result.id > 0, let imageStr = result.coverImage,
                  let imageURL = URL(string: imageStr) else {
                return nil
            }
            let sourceURL = URL(string: "https://www.discogs.com/release/\(result.id)")!

            return DiscogsArtworkCandidate(
                id: result.id,
                title: result.title ?? query.albumTitle,
                artist: query.albumArtist,
                year: result.year,
                country: result.country,
                formats: result.format ?? [],
                genres: result.genre ?? [],
                styles: result.style ?? [],
                thumbnailURL: result.thumb.flatMap(URL.init),
                imageURL: imageURL,
                sourcePageURL: sourceURL,
                fetchedAt: fetchedAt
            )
        }

        let pageNum = decoded.pagination?.page ?? page
        let total = decoded.pagination?.pages ?? 1

        return DiscogsSearchPage(candidates: candidates, page: pageNum, totalPages: total, fetchedAt: fetchedAt)
    }

    public func releaseMetadata(id: Int) async throws -> DiscogsReleaseMetadata {
        let token: String
        do {
            token = try await tokenProvider()
        } catch {
            throw DiscogsError.tokenMissing
        }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("releases/\(id)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else { throw DiscogsError.noResults }
        let request = DiscogsHTTP.request(url: url, userAgent: userAgent)
        guard let fetchedAt = clock() else { throw DiscogsError.freshnessUnavailable }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        try requireFresh([fetchedAt])
        let http = response
        switch http.statusCode {
        case 200: break
        case 401, 403: throw DiscogsError.tokenInvalid
        case 404: throw DiscogsError.noResults
        case 429:
            throw DiscogsError.rateLimited(
                retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            )
        case 500...599: throw DiscogsError.serverUnavailable
        default: throw DiscogsError.serverUnavailable
        }
        guard let release = try? JSONDecoder().decode(DiscogsReleaseResponse.self, from: data) else {
            throw DiscogsError.decodingFailed
        }
        let tracks = (release.tracklist ?? []).compactMap { track -> DiscogsReleaseMetadata.Track? in
            guard track.type == nil || track.type == "track" else { return nil }
            let digits = track.position.prefix { $0.isNumber }
            guard let number = Int(digits), number > 0 else { return nil }
            return DiscogsReleaseMetadata.Track(
                number: number,
                title: track.title,
                duration: Self.parseDuration(track.duration)
            )
        }
        let primaryImage = release.images?.first(where: { $0.type?.lowercased() == "primary" })
            ?? release.images?.first
        return DiscogsReleaseMetadata(
            id: release.id,
            title: release.title,
            artist: release.artistsSort
                ?? release.artists?.map(\.name).joined(separator: " & ")
                ?? "Unknown Artist",
            year: release.year,
            country: release.country,
            formats: release.formats?.map(\.name) ?? [],
            tracks: tracks,
            artworkURL: primaryImage?.uri.flatMap(URL.init)
                ?? primaryImage?.uri150.flatMap(URL.init),
            fetchedAt: fetchedAt
        )
    }

    private static func parseDuration(_ raw: String?) -> TimeInterval? {
        guard let raw, !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    // MARK: - Image download

    /// Downloads the full-size image for a candidate. Returns the raw image data.
    public func downloadImage(from url: URL, evidence: DiscogsContentEvidence) async throws -> Data {
        guard evidence.releaseID > 0 else { throw DiscogsError.resultsExpired }
        let request = DiscogsHTTP.request(url: url, userAgent: userAgent)

        // Retry up to 2 times for transient failures.
        var lastError: Error?
        for attempt in 0...2 {
            try requireFresh(evidence.fetches)
            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                try requireFresh(evidence.fetches)

                let http = response
                guard http.statusCode == 200 else {
                    if http.statusCode == 429 {
                        throw DiscogsError.rateLimited(
                            retryAfter: http.value(forHTTPHeaderField: "Retry-After")
                                .flatMap(TimeInterval.init)
                        )
                    }
                    throw DiscogsError.imageDownloadFailed
                }
                // Reject unreasonably large payloads.
                guard data.count <= 20 * 1024 * 1024 else {
                    throw DiscogsError.imageDownloadFailed
                }
                try requireFresh(evidence.fetches)
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch DiscogsError.resultsExpired {
                throw DiscogsError.resultsExpired
            } catch DiscogsError.freshnessUnavailable {
                throw DiscogsError.freshnessUnavailable
            } catch {
                try Task.checkCancellation()
                try requireFresh(evidence.fetches)
                lastError = error
                if attempt < 2 {
                    let backoff = TimeInterval(attempt + 1)
                    try await sleep(backoff)
                    try Task.checkCancellation()
                    try requireFresh(evidence.fetches)
                }
            }
        }
        throw lastError ?? DiscogsError.imageDownloadFailed
    }
}
