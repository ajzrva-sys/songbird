import Foundation

public actor DiscogsAudioCDMetadataProvider: AudioCDMetadataProviding {
    private let client: any DiscogsCDSearching
    private let searchCache: DiscogsArtworkSearchCache
    private let metadataCache: AudioCDMetadataCache
    private let clock: @Sendable () -> DiscogsFetchStamp?

    public init(
        client: any DiscogsCDSearching,
        searchCache: DiscogsArtworkSearchCache = .shared,
        metadataCache: AudioCDMetadataCache = AudioCDMetadataCache(
            directory: FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            .appendingPathComponent("Songbird/CDMetadata/Discogs", isDirectory: true)
        ),
        clock: @escaping @Sendable () -> DiscogsFetchStamp? = { DiscogsClock.sample() }
    ) {
        self.client = client
        self.searchCache = searchCache
        self.metadataCache = metadataCache
        self.clock = clock
    }

    public func candidates(for query: AudioCDMetadataQuery) async throws
        -> [AudioCDMetadataCandidate] {
        if let cached = await metadataCache.loadDiscogs(discID: query.discID) {
            try requireFresh(cached.fetches, candidates: cached.value)
            return cached.value
        }
        try Task.checkCancellation()
        let title = query.albumTitle.flatMap {
            $0.caseInsensitiveCompare("Audio CD") == .orderedSame ? nil : $0
        } ?? ""
        let artist = query.albumArtist.flatMap {
            $0.caseInsensitiveCompare("Unknown Artist") == .orderedSame ? nil : $0
        } ?? ""
        guard !title.isEmpty || !artist.isEmpty else {
            return []
        }

        let searchQuery = DiscogsArtworkSearchQuery(albumTitle: title, albumArtist: artist)
        let searchResults: [DiscogsArtworkCandidate]
        var fetches: [DiscogsFetchStamp]
        if let cached = await searchCache.candidates(for: searchQuery) {
            searchResults = cached.value
            fetches = cached.fetches
        } else {
            do {
                let page = try await client.search(searchQuery, page: 1)
                searchResults = page.candidates
                fetches = [page.fetchedAt]
                try requireFresh(fetches)
                await searchCache.store(searchResults, for: searchQuery, fetches: [page.fetchedAt])
            } catch DiscogsError.noResults {
                return []
            }
        }

        try requireFresh(fetches)
        let searchFetches = (fetches + searchResults.map(\.fetchedAt)).reduce(into: [DiscogsFetchStamp]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        try requireFresh(searchFetches)
        fetches = searchFetches
        let likelyCDs = searchResults.filter {
            $0.formats.contains { $0.localizedCaseInsensitiveContains("CD") }
        }
        let shortlist = (likelyCDs.isEmpty ? searchResults : likelyCDs).prefix(8)
        var found: [AudioCDMetadataCandidate] = []
        for result in shortlist {
            try Task.checkCancellation()
            do {
                let release = try await client.releaseMetadata(id: result.id)
                fetches.append(release.fetchedAt)
                try requireFresh(fetches, candidates: found)
                guard release.tracks.count == query.trackCount else { continue }
                let durationScore = Self.durationScore(
                    expected: query.tracks,
                    actual: release.tracks
                )
                let cdScore = release.formats.contains {
                    $0.localizedCaseInsensitiveContains("CD")
                } ? 20 : 0
                found.append(AudioCDMetadataCandidate(
                    id: "discogs:\(release.id)",
                    title: release.title,
                    artist: release.artist,
                    country: release.country,
                    date: release.year.map(String.init),
                    tracks: release.tracks.map {
                        AudioCDMetadataTrack(
                            number: $0.number,
                            title: $0.title,
                            artist: release.artist
                        )
                    },
                    artworkURL: release.artworkURL ?? result.imageURL,
                    score: 100 + cdScore + durationScore,
                    discogsEvidence: DiscogsContentEvidence(
                        releaseID: release.id,
                        fetches: release.artworkURL == nil
                            ? searchFetches + [release.fetchedAt] : [release.fetchedAt]
                    )
                ))
            } catch DiscogsError.noResults {
                try requireFresh(fetches, candidates: found)
                continue
            }
        }
        found.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return ($0.date ?? "") < ($1.date ?? "")
        }
        try requireFresh(fetches, candidates: found)
        await metadataCache.storeDiscogs(found, discID: query.discID, fetches: fetches)
        try requireFresh(fetches, candidates: found)
        return found
    }

    private func requireFresh(_ fetches: [DiscogsFetchStamp],
                              candidates: [AudioCDMetadataCandidate] = []) throws {
        try Task.checkCancellation()
        guard let now = clock() else { throw DiscogsError.freshnessUnavailable }
        guard !fetches.isEmpty, fetches.allSatisfy({ DiscogsFreshness.isFresh($0, at: now) }),
              candidates.allSatisfy({ $0.discogsEvidence?.isFresh(at: now) == true }) else {
            throw DiscogsError.resultsExpired
        }
    }

    private static func durationScore(
        expected: [AudioCDMetadataQuery.Track],
        actual: [DiscogsReleaseMetadata.Track]
    ) -> Int {
        let actualByNumber = Dictionary(uniqueKeysWithValues: actual.map { ($0.number, $0) })
        let deltas = expected.compactMap { expectedTrack -> TimeInterval? in
            guard expectedTrack.duration > 0,
                  let actualDuration = actualByNumber[expectedTrack.number]?.duration else { return nil }
            return abs(expectedTrack.duration - actualDuration)
        }
        guard !deltas.isEmpty else { return 0 }
        let mean = deltas.reduce(0, +) / Double(deltas.count)
        return max(-40, 40 - Int(mean.rounded()))
    }
}

public actor MusicBrainzDiscogsMetadataProvider: AudioCDMetadataProviding {
    private let musicBrainz: any AudioCDMetadataProviding
    private let discogs: any AudioCDMetadataProviding

    public init(
        musicBrainz: any AudioCDMetadataProviding,
        discogs: any AudioCDMetadataProviding
    ) {
        self.musicBrainz = musicBrainz
        self.discogs = discogs
    }

    public func candidates(for query: AudioCDMetadataQuery) async throws
        -> [AudioCDMetadataCandidate] {
        let primary = try await musicBrainz.candidates(for: query)
        return primary.isEmpty ? try await discogs.candidates(for: query) : primary
    }
}
