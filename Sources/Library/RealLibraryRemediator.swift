import Foundation
import SwiftData

public struct LocalLibraryRemediationReport: Codable, Equatable, Sendable {
    public var tracksScanned = 0
    public var unreadableFiles = 0
    public var missingFiles = 0
    public var unavailableFiles = 0
    public var artistsFilled = 0
    public var albumsFilled = 0
    public var titlesFilled = 0
    public var albumArtistsFilled = 0
    public var genresFilled = 0
    public var yearsFilled = 0
    public var trackNumbersFilled = 0
    public var trackTotalsFilled = 0
    public var discNumbersFilled = 0
    public var discTotalsFilled = 0
    public var artworkFilled = 0
    public var bpmTagsFilled = 0
    public var bpmCalculated = 0
    public var bpmDetectorZero = 0
    public var caseVariantsUnified = 0
    public var albumRecordsUpdated = 0
    public var artistRecordsUpdated = 0

    public init() {}
}

public struct DiscogsLibraryRemediationReport: Codable, Equatable, Sendable {
    public var albumsConsidered = 0
    public var cacheHits = 0
    public var networkSearches = 0
    public var highConfidenceMatches = 0
    public var fuzzyConfidenceMatches = 0
    public var genresFilled = 0
    public var trackYearsFilled = 0
    public var albumYearsFilled = 0
    public var artworkFilled = 0
    public var trackNumbersFilled = 0
    public var releaseMetadataRequests = 0
    public var lowConfidenceSkipped = 0
    public var noResultSkipped = 0
    public var failures = 0

    public init() {}
}

public struct AppleCatalogLibraryRemediationReport: Codable, Equatable, Sendable {
    public var albumsConsidered = 0
    public var networkSearches = 0
    public var exactMatches = 0
    public var genresFilled = 0
    public var trackYearsFilled = 0
    public var albumYearsFilled = 0
    public var artworkFilled = 0
    public var trackNumbersFilled = 0
    public var lookupRequests = 0
    public var ambiguousSkipped = 0
    public var noResultSkipped = 0
    public var failures = 0

    public init() {}
}

struct AppleCatalogCandidate: Codable, Equatable, Sendable {
    let collectionId: Int?
    let artistName: String
    let collectionName: String
    let releaseDate: String?
    let primaryGenreName: String?
    let artworkUrl100: URL?
}

private struct AppleCatalogSearchResponse: Decodable, Sendable {
    let results: [AppleCatalogCandidate]
}

private struct AppleCatalogLookupResponse: Decodable, Sendable {
    let results: [AppleCatalogTrack]
}

private struct AppleCatalogTrack: Decodable, Sendable {
    let wrapperType: String?
    let collectionId: Int?
    let trackName: String?
    let trackNumber: Int?
}

public struct LibraryRemediationPreview: Codable, Equatable, Sendable {
    public let tracks: Int
    public let albums: Int
    public let missingArtists: Int
    public let missingAlbums: Int
    public let missingTitles: Int
    public let missingGenres: Int
    public let missingTrackNumbers: Int
    public let missingTrackYears: Int
    public let missingAlbumYears: Int
    public let missingArtwork: Int

    public init(
        tracks: Int,
        albums: Int,
        missingArtists: Int,
        missingAlbums: Int,
        missingTitles: Int,
        missingGenres: Int,
        missingTrackNumbers: Int,
        missingTrackYears: Int,
        missingAlbumYears: Int,
        missingArtwork: Int
    ) {
        self.tracks = tracks
        self.albums = albums
        self.missingArtists = missingArtists
        self.missingAlbums = missingAlbums
        self.missingTitles = missingTitles
        self.missingGenres = missingGenres
        self.missingTrackNumbers = missingTrackNumbers
        self.missingTrackYears = missingTrackYears
        self.missingAlbumYears = missingAlbumYears
        self.missingArtwork = missingArtwork
    }
}

public struct DiscogsRemediationAuditCandidate: Codable, Equatable, Sendable {
    public let title: String
    public let sourcePageURL: URL?
    public let evidence: DiscogsContentEvidence
    public let checkedAt: DiscogsFetchStamp?
    public let isFresh: Bool
}

public struct DiscogsRemediationAuditItem: Codable, Equatable, Sendable {
    public let albumTitle: String
    public let albumArtist: String
    public let candidateTitles: [String]
    public let candidates: [DiscogsRemediationAuditCandidate]

    public init(albumTitle: String, albumArtist: String, candidateTitles: [String],
                candidates: [DiscogsRemediationAuditCandidate] = []) {
        self.albumTitle = albumTitle
        self.albumArtist = albumArtist
        self.candidateTitles = candidateTitles
        self.candidates = candidates
    }

    /// A transient output snapshot, not permission to retain imported content.
    public func revalidated(at now: DiscogsFetchStamp?) -> Self? {
        let fresh = candidates.compactMap { candidate -> DiscogsRemediationAuditCandidate? in
            guard candidate.evidence.isFresh(at: now) else { return nil }
            return DiscogsRemediationAuditCandidate(
                title: candidate.title, sourcePageURL: candidate.evidence.sourcePageURL,
                evidence: candidate.evidence, checkedAt: now, isFresh: true)
        }
        guard !fresh.isEmpty else { return nil }
        return Self(albumTitle: albumTitle, albumArtist: albumArtist,
                    candidateTitles: fresh.map(\.title), candidates: fresh)
    }
}

public struct IdentifierMetadataRepairProposal: Codable, Equatable, Sendable {
    public let albumID: UUID
    public let albumTitle: String
    public let corruptValue: String
    public let replacement: String
    public let trackFields: Int
    public let albumFields: Int

    public var totalFields: Int { trackFields + albumFields }

    public init(
        albumID: UUID,
        albumTitle: String,
        corruptValue: String,
        replacement: String,
        trackFields: Int,
        albumFields: Int
    ) {
        self.albumID = albumID
        self.albumTitle = albumTitle
        self.corruptValue = corruptValue
        self.replacement = replacement
        self.trackFields = trackFields
        self.albumFields = albumFields
    }
}

public struct IdentifierMetadataRepairReport: Codable, Equatable, Sendable {
    public let proposals: [IdentifierMetadataRepairProposal]
    public let albumsUpdated: Int
    public let tracksUpdated: Int
    public let fieldsUpdated: Int

    public init(
        proposals: [IdentifierMetadataRepairProposal],
        albumsUpdated: Int,
        tracksUpdated: Int,
        fieldsUpdated: Int
    ) {
        self.proposals = proposals
        self.albumsUpdated = albumsUpdated
        self.tracksUpdated = tracksUpdated
        self.fieldsUpdated = fieldsUpdated
    }
}

// Operation-local seams; no global test override and no eager credential lookup.
protocol DiscogsRemediationClient: DiscogsCDSearching {
    func downloadImage(from url: URL, evidence: DiscogsContentEvidence) async throws -> Data
}

extension DiscogsClient: DiscogsRemediationClient {}

@MainActor
struct DiscogsRemediationDependencies {
    let client: any DiscogsRemediationClient
    let cache: DiscogsArtworkSearchCache
    var clock: () -> DiscogsFetchStamp? = { DiscogsClock.sample() }
    var sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    var normalize: (Data) async throws -> Data = { data in
        guard ArtworkStorage.pixelSize(of: data) != nil else { throw DiscogsError.imageDownloadFailed }
        return ArtworkStorage.normalized(data)
    }
    var save: (ModelContext) throws -> Void = { try $0.save() }

    func requireFresh(_ evidence: DiscogsContentEvidence) throws {
        guard let now = clock() else { throw DiscogsError.freshnessUnavailable }
        guard evidence.isFresh(at: now) else { throw DiscogsError.resultsExpired }
    }

    static func live() -> Self {
        Self(client: DiscogsClient(tokenProvider: { try await DiscogsKeychain.load() }), cache: .shared)
    }
}

@MainActor
public enum RealLibraryRemediator {
    /// Value-only targets survive cache/network awaits. UUID reuse is not identity.
    private struct DiscogsTarget {
        struct TrackIdentity: Hashable {
            let id: UUID
            let persistentID: PersistentIdentifier
            let title: String
            let path: String
            let duration: TimeInterval

            init(_ track: Track) {
                id = track.id
                persistentID = track.persistentModelID
                title = track.title
                path = track.path
                duration = track.duration
            }
        }

        let id: UUID
        let persistentID: PersistentIdentifier
        let title: String
        let artist: String
        let year: Int
        let lookupArtist: String
        let needsArtwork: Bool
        let tracks: Set<TrackIdentity>

        @MainActor
        init(_ album: Album) {
            id = album.id
            persistentID = album.persistentModelID
            title = album.title
            artist = album.artist
            year = album.year
            lookupArtist = isCompilation(album) ? "Various Artists" : album.artist
            needsArtwork = album.artworkData == nil
            tracks = Set(album.tracks.map(TrackIdentity.init))
        }

        func resolve(in context: ModelContext) throws -> Album? {
            let id = id
            let matches = try context.fetch(FetchDescriptor<Album>(predicate: #Predicate { $0.id == id }))
            guard matches.count == 1, let album = matches.first,
                  !album.isDeleted, album.persistentModelID == persistentID,
                  album.title == title, album.artist == artist,
                  album.tracks.allSatisfy({ !$0.isDeleted && $0.albumRelation?.persistentModelID == persistentID }),
                  Set(album.tracks.map(TrackIdentity.init)) == tracks else { return nil }
            return album
        }
    }

    private struct ReadInput: Sendable {
        let id: UUID
        let path: String
    }

    private struct ReadResult: Sendable {
        let id: UUID
        let metadata: AudioMetadata?
        let folderArtwork: Data?
        let resolution: FileResolution
    }

    private struct BPMReadResult: Sendable {
        let id: UUID
        let resolution: FileResolution
        let taggedBPM: Int
        let detectedBPM: Int
    }

    public static func preview(in context: ModelContext) throws -> LibraryRemediationPreview {
        let tracks = try context.fetch(FetchDescriptor<Track>())
        let albums = try context.fetch(FetchDescriptor<Album>())
        return LibraryRemediationPreview(
            tracks: tracks.count,
            albums: albums.count,
            missingArtists: tracks.count(where: { isMissingArtist($0.artist) }),
            missingAlbums: tracks.count(where: { isMissingAlbum($0.album) }),
            missingTitles: tracks.count(where: { normalized($0.title).isEmpty }),
            missingGenres: tracks.count(where: { GenreMetadata.isMissing($0.genre) }),
            missingTrackNumbers: tracks.count(where: { $0.trackNumber == 0 }),
            missingTrackYears: tracks.count(where: { $0.year == 0 }),
            missingAlbumYears: albums.count(where: { $0.year == 0 }),
            missingArtwork: albums.count(where: { $0.artworkData == nil })
        )
    }

    /// Finds the narrowly defined corruption where an Album artist and every related
    /// Track album artist contain the same UUID-shaped value, while every Track artist
    /// unanimously supplies one ordinary human-readable replacement.
    public static func previewIdentifierMetadataRepairs(
        in context: ModelContext
    ) throws -> [IdentifierMetadataRepairProposal] {
        let albums = try context.fetch(FetchDescriptor<Album>())
        return albums.compactMap { album in
            let corruptValue = normalized(album.artist)
            guard canonicalIdentifier(corruptValue) != nil else { return nil }

            let tracks = album.tracks
            guard tracks.isEmpty == false,
                  tracks.allSatisfy({ track in
                      canonicalIdentifier(track.albumArtist)
                          == canonicalIdentifier(corruptValue)
                  }) else {
                return nil
            }

            let artists = tracks.map { normalized($0.artist) }
            guard artists.allSatisfy({ artist in
                isMissingArtist(artist) == false && canonicalIdentifier(artist) == nil
            }), let replacement = unanimous(artists) else {
                return nil
            }

            return IdentifierMetadataRepairProposal(
                albumID: album.id,
                albumTitle: album.title,
                corruptValue: corruptValue,
                replacement: replacement,
                trackFields: tracks.count,
                albumFields: 1
            )
        }.sorted { lhs, rhs in
            let titleOrder = lhs.albumTitle.localizedCaseInsensitiveCompare(rhs.albumTitle)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.albumID.uuidString < rhs.albumID.uuidString
        }
    }

    /// Applies only an already reviewed proposal set. Any scope drift aborts before mutation.
    public static func applyIdentifierMetadataRepairs(
        in context: ModelContext,
        expectedProposals: [IdentifierMetadataRepairProposal]
    ) throws -> IdentifierMetadataRepairReport {
        let currentProposals = try previewIdentifierMetadataRepairs(in: context)
        guard currentProposals == expectedProposals else {
            throw IdentifierMetadataRepairError.proposalScopeChanged
        }

        let albums = try context.fetch(FetchDescriptor<Album>())
        let albumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
        var albumsUpdated = 0
        var tracksUpdated = 0

        for proposal in expectedProposals {
            guard let album = albumsByID[proposal.albumID],
                  normalized(album.artist) == proposal.corruptValue,
                  album.tracks.count == proposal.trackFields,
                  album.tracks.allSatisfy({
                      canonicalIdentifier($0.albumArtist)
                          == canonicalIdentifier(proposal.corruptValue)
                  }) else {
                throw IdentifierMetadataRepairError.proposalScopeChanged
            }

            album.artist = proposal.replacement
            albumsUpdated += 1
            for track in album.tracks {
                track.albumArtist = proposal.replacement
                tracksUpdated += 1
            }
        }

        try context.save()
        return IdentifierMetadataRepairReport(
            proposals: expectedProposals,
            albumsUpdated: albumsUpdated,
            tracksUpdated: tracksUpdated,
            fieldsUpdated: albumsUpdated + tracksUpdated
        )
    }

    public static func applyLocalEvidence(
        in context: ModelContext
    ) async throws -> LocalLibraryRemediationReport {
        var report = LocalLibraryRemediationReport()
        let tracks = try context.fetch(FetchDescriptor<Track>())
        let albums = try context.fetch(FetchDescriptor<Album>())
        let artists = try context.fetch(FetchDescriptor<Artist>())
        report.tracksScanned = tracks.count

        let trackByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        var albumByTrackID: [UUID: Album] = [:]
        for album in albums {
            for track in album.tracks { albumByTrackID[track.id] = album }
        }

        let inputs = tracks.compactMap { track -> ReadInput? in
            let needsArtwork = albumByTrackID[track.id]?.artworkData == nil
            guard needsArtwork || needsMetadata(track) else { return nil }
            return ReadInput(id: track.id, path: track.path)
        }

        for start in stride(from: 0, to: inputs.count, by: 24) {
            let end = min(start + 24, inputs.count)
            let chunk = Array(inputs[start..<end])
            let results = await withTaskGroup(of: ReadResult.self) { group in
                for input in chunk {
                    group.addTask {
                        let resolution = FilesystemPathResolver().resolve(input.path)
                        guard case .available(let url) = resolution else {
                            return ReadResult(
                                id: input.id,
                                metadata: nil,
                                folderArtwork: nil,
                                resolution: resolution
                            )
                        }
                        async let metadata = MetadataReader.read(
                            from: url,
                            detectMissingBPM: false
                        )
                        let folderArtwork = TrackImporter.folderArtworkData(for: url)
                        return await ReadResult(
                            id: input.id,
                            metadata: metadata,
                            folderArtwork: folderArtwork,
                            resolution: resolution
                        )
                    }
                }
                var values: [ReadResult] = []
                for await value in group { values.append(value) }
                return values
            }

            for result in results {
                guard let track = trackByID[result.id] else { continue }
                guard case .available(let actualURL) = result.resolution else {
                    if case .missing = result.resolution {
                        report.missingFiles += 1
                    } else {
                        report.unavailableFiles += 1
                    }
                    continue
                }
                if !LibraryPathIdentity.hasSameScalarSpelling(track.path, actualURL.path) {
                    track.path = Track.standardizedPath(actualURL.path)
                }
                guard let metadata = result.metadata else {
                    report.unreadableFiles += 1
                    continue
                }
                apply(metadata, to: track, report: &report)
                if let album = albumByTrackID[track.id], album.artworkData == nil,
                   let artwork = metadata.artworkData ?? result.folderArtwork,
                   ArtworkStorage.pixelSize(of: artwork) != nil {
                    album.artworkData = ArtworkStorage.normalized(artwork)
                    report.artworkFilled += 1
                }
            }
            if context.hasChanges { try context.save() }
            print("Local metadata: \(end) of \(inputs.count)")
        }

        applyFolderAndSiblingEvidence(to: tracks, report: &report)
        applyUnanimousAlbumEvidence(albums: albums, report: &report)
        applyCrossRecordEvidence(albums: albums, tracks: tracks, report: &report)
        applyCaseCanonicalization(to: tracks, report: &report)
        updateRelationshipRecords(albums: albums, artists: artists, report: &report)
        if context.hasChanges { try context.save() }
        return report
    }

    public static func applyLocalInference(
        in context: ModelContext
    ) throws -> LocalLibraryRemediationReport {
        var report = LocalLibraryRemediationReport()
        let tracks = try context.fetch(FetchDescriptor<Track>())
        let albums = try context.fetch(FetchDescriptor<Album>())
        let artists = try context.fetch(FetchDescriptor<Artist>())
        report.tracksScanned = tracks.count
        applyFolderAndSiblingEvidence(to: tracks, report: &report)
        applyUnanimousAlbumEvidence(albums: albums, report: &report)
        applyCrossRecordEvidence(albums: albums, tracks: tracks, report: &report)
        applyCaseCanonicalization(to: tracks, report: &report)
        updateRelationshipRecords(albums: albums, artists: artists, report: &report)
        if context.hasChanges { try context.save() }
        return report
    }

    public static func applyMissingBPM(
        in context: ModelContext
    ) async throws -> LocalLibraryRemediationReport {
        var report = LocalLibraryRemediationReport()
        let tracks = try context.fetch(FetchDescriptor<Track>(
            predicate: #Predicate { $0.beatsPerMinute == 0 }
        ))
        report.tracksScanned = tracks.count
        let trackByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let inputs = tracks.map { ReadInput(id: $0.id, path: $0.path) }

        for start in stride(from: 0, to: inputs.count, by: 4) {
            let end = min(start + 4, inputs.count)
            let chunk = Array(inputs[start..<end])
            let results = await withTaskGroup(of: BPMReadResult.self) { group in
                for input in chunk {
                    group.addTask {
                        let resolution = FilesystemPathResolver().resolve(input.path)
                        guard case .available(let url) = resolution else {
                            return BPMReadResult(
                                id: input.id,
                                resolution: resolution,
                                taggedBPM: 0,
                                detectedBPM: 0
                            )
                        }
                        let taggedBPM = await MetadataReader.read(
                            from: url,
                            detectMissingBPM: false
                        )?.beatsPerMinute ?? 0
                        let detectedBPM = taggedBPM > 0
                            ? 0
                            : await MetadataReader.detectBPM(from: url)
                        return BPMReadResult(
                            id: input.id,
                            resolution: resolution,
                            taggedBPM: taggedBPM,
                            detectedBPM: detectedBPM
                        )
                    }
                }
                var values: [BPMReadResult] = []
                for await value in group { values.append(value) }
                return values
            }

            for result in results {
                guard let track = trackByID[result.id], track.beatsPerMinute == 0 else { continue }
                guard case .available(let actualURL) = result.resolution else {
                    if case .missing = result.resolution {
                        report.missingFiles += 1
                    } else {
                        report.unavailableFiles += 1
                    }
                    continue
                }
                if !LibraryPathIdentity.hasSameScalarSpelling(track.path, actualURL.path) {
                    track.path = Track.standardizedPath(actualURL.path)
                }
                guard let bpm = acceptedMissingBPM(
                    current: track.beatsPerMinute,
                    tagged: result.taggedBPM,
                    detected: result.detectedBPM
                ) else {
                    report.bpmDetectorZero += 1
                    continue
                }
                track.beatsPerMinute = bpm
                if result.taggedBPM == bpm {
                    report.bpmTagsFilled += 1
                } else {
                    report.bpmCalculated += 1
                }
            }
            if context.hasChanges { try context.save() }
            print("BPM verification: \(end) of \(inputs.count)")
        }
        return report
    }

    static func acceptedMissingBPM(current: Int, tagged: Int, detected: Int) -> Int? {
        guard current == 0 else { return nil }
        if (1...999).contains(tagged) { return tagged }
        if (1...999).contains(detected) { return detected }
        return nil
    }

    public static func applyDiscogsEvidence(
        in context: ModelContext,
        allowNetwork: Bool = true,
        allowFuzzyMatches: Bool = false,
        refreshEmptyResults: Bool = false
    ) async throws -> DiscogsLibraryRemediationReport {
        try await applyDiscogsEvidence(in: context, allowNetwork: allowNetwork,
                                       allowFuzzyMatches: allowFuzzyMatches,
                                       refreshEmptyResults: refreshEmptyResults,
                                       dependencies: .live())
    }

    static func applyDiscogsEvidence(
        in context: ModelContext,
        allowNetwork: Bool = true,
        allowFuzzyMatches: Bool = false,
        refreshEmptyResults: Bool = false,
        dependencies: DiscogsRemediationDependencies
    ) async throws -> DiscogsLibraryRemediationReport {
        var report = DiscogsLibraryRemediationReport()
        let albums = try context.fetch(FetchDescriptor<Album>(
            sortBy: [SortDescriptor(\Album.artist), SortDescriptor(\Album.title)]
        )).filter { album in
            album.tracks.isEmpty == false && needsDiscogs(album)
        }.map(DiscogsTarget.init)
        report.albumsConsidered = albums.count
        let cache = dependencies.cache
        var lastRequestDate: Date?

        for (index, target) in albums.enumerated() {
            let lookupArtist = target.lookupArtist
            var query = DiscogsArtworkSearchQuery(
                albumTitle: target.title,
                albumArtist: lookupArtist,
                year: target.year > 0 ? target.year : nil
            )
            var hit = await cache.candidates(for: query)
            var candidates = hit?.value
            var fetches = hit?.fetches ?? []
            if candidates?.isEmpty != false, query.year != nil {
                let yearless = DiscogsArtworkSearchQuery(
                    albumTitle: target.title,
                    albumArtist: lookupArtist
                )
                hit = await cache.candidates(for: yearless)
                candidates = hit?.value
                fetches = hit?.fetches ?? []
                query = yearless
            }
            if refreshEmptyResults, candidates?.isEmpty != false {
                query = DiscogsArtworkSearchQuery(
                    albumTitle: albumCore(target.title),
                    albumArtist: lookupArtist
                )
                candidates = nil
            }
            if candidates != nil {
                report.cacheHits += 1
            } else {
                guard allowNetwork else {
                    report.noResultSkipped += 1
                    continue
                }
                if let lastRequestDate {
                    let delay = 2.1 - Date().timeIntervalSince(lastRequestDate)
                    if delay > 0 { try await dependencies.sleep(delay) }
                }
                lastRequestDate = Date()
                do {
                    let client = dependencies.client
                    let page = try await client.search(query, page: 1)
                    candidates = Array(page.candidates.prefix(5))
                    fetches = [page.fetchedAt]
                    await cache.store(candidates ?? [], for: query, fetches: [page.fetchedAt])
                    report.networkSearches += 1
                } catch DiscogsError.rateLimited(let retryAfter) {
                    try await dependencies.sleep(max(60, retryAfter ?? 60))
                    report.failures += 1
                    continue
                } catch {
                    report.failures += 1
                    continue
                }
            }

            guard let candidates, candidates.isEmpty == false else {
                report.noResultSkipped += 1
                continue
            }
            let highConfidenceCandidate = candidates.first(where: {
                isHighConfidence(candidate: $0, albumTitle: target.title, albumArtist: lookupArtist)
            })
            let fuzzyCandidate = allowFuzzyMatches ? candidates.first(where: {
                isFuzzyConfidence(candidate: $0, albumTitle: target.title, albumArtist: lookupArtist)
            }) : nil
            guard let candidate = highConfidenceCandidate ?? fuzzyCandidate else {
                report.lowConfidenceSkipped += 1
                continue
            }

            if highConfidenceCandidate != nil {
                report.highConfidenceMatches += 1
            } else {
                report.fuzzyConfidenceMatches += 1
            }
            let evidence = discogsEvidence(candidate, fetches: fetches)
            let artwork: Data?
            do {
                try dependencies.requireFresh(evidence)
                if allowNetwork, target.needsArtwork {
                    let data = try await dependencies.client.downloadImage(
                        from: candidate.imageURL, evidence: evidence)
                    try dependencies.requireFresh(evidence)
                    artwork = try await dependencies.normalize(data)
                } else {
                    artwork = nil
                }
                // The last await includes normalization, not just the image transport.
                try dependencies.requireFresh(evidence)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                report.failures += 1
                continue
            }
            guard let album = try target.resolve(in: context) else {
                report.failures += 1
                continue
            }
            let beforeYear = album.year
            let beforeArtwork = album.artworkData
            let beforeTracks = album.tracks.map { ($0, $0.genre, $0.year) }
            let genre = DiscogsGenreSuggestionPolicy.suggestedGenre(from: [candidate.genres, candidate.styles])
            try dependencies.requireFresh(evidence)
            if let genre {
                for track in album.tracks where GenreMetadata.isMissing(track.genre) {
                    track.genre = genre
                    report.genresFilled += 1
                }
            }
            if let year = candidate.year, year > 0 {
                if album.year == 0 {
                    album.year = year
                    report.albumYearsFilled += 1
                }
                for track in album.tracks where track.year == 0 {
                    track.year = year
                    report.trackYearsFilled += 1
                }
            }
            if let artwork, album.artworkData == nil {
                album.artworkData = artwork
                report.artworkFilled += 1
            }
            do {
                try dependencies.requireFresh(evidence)
                if context.hasChanges { try dependencies.save(context) }
            } catch {
                // SwiftData rollback alone can leave retained model values changed.
                album.year = beforeYear
                album.artworkData = beforeArtwork
                for (track, genre, year) in beforeTracks {
                    track.genre = genre
                    track.year = year
                }
                context.rollback()
                throw error
            }
            if index.isMultiple(of: 25) {
                print("Discogs: \(index + 1) of \(albums.count)")
            }
        }
        return report
    }

    public static func applyAppleCatalogEvidence(
        in context: ModelContext,
        country: String = "US",
        artworkOnly: Bool = false
    ) async throws -> AppleCatalogLibraryRemediationReport {
        var report = AppleCatalogLibraryRemediationReport()
        let albums = try context.fetch(FetchDescriptor<Album>()).filter {
            artworkOnly ? $0.artworkData == nil : needsDiscogs($0)
        }
        report.albumsConsidered = albums.count
        var lastRequestDate: Date?

        for (index, album) in albums.enumerated() {
            if let lastRequestDate {
                let delay = 3.2 - Date().timeIntervalSince(lastRequestDate)
                if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            }
            lastRequestDate = Date()
            do {
                let compilation = isCompilation(album)
                let lookupArtist = compilation ? "Various Artists" : album.artist
                var components = URLComponents(string: "https://itunes.apple.com/search")!
                components.queryItems = [
                    URLQueryItem(name: "term", value: "\(lookupArtist) \(album.title)"),
                    URLQueryItem(name: "country", value: country),
                    URLQueryItem(name: "media", value: "music"),
                    URLQueryItem(name: "entity", value: "album"),
                    URLQueryItem(name: "limit", value: "25"),
                ]
                var request = URLRequest(url: components.url!)
                request.setValue("Songbird/1.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                report.networkSearches += 1
                guard response.statusCode == 200 else {
                    report.failures += 1
                    continue
                }
                let decoded = try JSONDecoder().decode(AppleCatalogSearchResponse.self, from: data)
                let matches = decoded.results.filter {
                    isExactAppleCatalogMatch(
                        candidate: $0,
                        albumTitle: album.title,
                        albumArtist: album.artist,
                        isCompilation: compilation
                    )
                }
                guard matches.isEmpty == false else {
                    report.noResultSkipped += 1
                    continue
                }
                report.exactMatches += 1

                let years = Set(matches.compactMap(appleCatalogYear))
                let genres = Set(matches.compactMap { candidate -> String? in
                    guard let genre = candidate.primaryGenreName,
                          GenreMetadata.isMissing(genre) == false else { return nil }
                    return GenreMetadata.normalized(genre)
                })
                let artworkMatches = album.year > 0
                    ? matches.filter { appleCatalogYear($0) == album.year }
                    : matches
                let artworkURLs = Set(artworkMatches.compactMap(\.artworkUrl100))
                var changed = false
                if years.count == 1, let year = years.first {
                    if album.year == 0 {
                        album.year = year
                        report.albumYearsFilled += 1
                        changed = true
                    }
                    for track in album.tracks where track.year == 0 {
                        track.year = year
                        report.trackYearsFilled += 1
                        changed = true
                    }
                }
                if genres.count == 1, let genre = genres.first {
                    for track in album.tracks where GenreMetadata.isMissing(track.genre) {
                        track.genre = genre
                        report.genresFilled += 1
                        changed = true
                    }
                }
                if album.artworkData == nil, artworkURLs.count == 1,
                   let url = artworkURLs.first {
                    let largeURL = URL(string: url.absoluteString.replacingOccurrences(
                        of: "100x100bb",
                        with: "600x600bb"
                    )) ?? url
                    let (artworkData, artworkResponse) = try await URLSession.shared.data(from: largeURL)
                    if (artworkResponse as? HTTPURLResponse)?.statusCode == 200,
                       ArtworkStorage.pixelSize(of: artworkData) != nil {
                        album.artworkData = ArtworkStorage.normalized(artworkData)
                        report.artworkFilled += 1
                        changed = true
                    }
                }
                if matches.count > 1 && years.count != 1 && genres.count != 1 && artworkURLs.count != 1 {
                    report.ambiguousSkipped += 1
                }
                if changed, context.hasChanges { try context.save() }
            } catch {
                report.failures += 1
            }
            if index.isMultiple(of: 10) {
                print("Apple catalog: \(index + 1) of \(albums.count)")
            }
        }
        return report
    }

    public static func applyAppleCatalogTrackNumbers(
        in context: ModelContext,
        country: String = "US"
    ) async throws -> AppleCatalogLibraryRemediationReport {
        var report = AppleCatalogLibraryRemediationReport()
        let albums = try context.fetch(FetchDescriptor<Album>()).filter {
            $0.tracks.contains(where: { $0.trackNumber == 0 })
        }
        report.albumsConsidered = albums.count
        var lastRequestDate: Date?

        func waitForRequestSlot() async throws {
            if let lastRequestDate {
                let delay = 3.2 - Date().timeIntervalSince(lastRequestDate)
                if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            }
            lastRequestDate = Date()
        }

        for (index, album) in albums.enumerated() {
            do {
                try await waitForRequestSlot()
                let compilation = isCompilation(album)
                let lookupArtist = compilation ? "Various Artists" : album.artist
                var components = URLComponents(string: "https://itunes.apple.com/search")!
                components.queryItems = [
                    URLQueryItem(name: "term", value: "\(lookupArtist) \(album.title)"),
                    URLQueryItem(name: "country", value: country),
                    URLQueryItem(name: "media", value: "music"),
                    URLQueryItem(name: "entity", value: "album"),
                    URLQueryItem(name: "limit", value: "25"),
                ]
                var request = URLRequest(url: components.url!)
                request.setValue("Songbird/1.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                report.networkSearches += 1
                guard response.statusCode == 200 else {
                    report.failures += 1
                    continue
                }
                let decoded = try JSONDecoder().decode(AppleCatalogSearchResponse.self, from: data)
                let matches = decoded.results.filter {
                    isExactAppleCatalogMatch(
                        candidate: $0,
                        albumTitle: album.title,
                        albumArtist: album.artist,
                        isCompilation: compilation
                    )
                }
                let collectionIDs = Set(matches.compactMap(\.collectionId))
                guard collectionIDs.isEmpty == false else {
                    report.noResultSkipped += 1
                    continue
                }
                report.exactMatches += 1

                var numbersByTitle: [String: Set<Int>] = [:]
                for collectionID in collectionIDs {
                    try await waitForRequestSlot()
                    var lookup = URLComponents(string: "https://itunes.apple.com/lookup")!
                    lookup.queryItems = [
                        URLQueryItem(name: "id", value: String(collectionID)),
                        URLQueryItem(name: "entity", value: "song"),
                        URLQueryItem(name: "country", value: country),
                    ]
                    let (lookupData, lookupResponse) = try await URLSession.shared.data(from: lookup.url!)
                    report.lookupRequests += 1
                    guard (lookupResponse as? HTTPURLResponse)?.statusCode == 200 else {
                        report.failures += 1
                        continue
                    }
                    let decodedLookup = try JSONDecoder().decode(
                        AppleCatalogLookupResponse.self,
                        from: lookupData
                    )
                    let grouped = Dictionary(grouping: decodedLookup.results.compactMap { item -> (String, Int)? in
                        guard item.wrapperType == "track", let title = item.trackName,
                              let number = item.trackNumber, number > 0 else { return nil }
                        return (searchable(trackCore(title)), number)
                    }, by: { $0.0 })
                    for (title, values) in grouped where values.count == 1 {
                        numbersByTitle[title, default: []].insert(values[0].1)
                    }
                }

                for track in album.tracks where track.trackNumber == 0 {
                    let numbers = numbersByTitle[searchable(trackCore(track.title)), default: []]
                    if numbers.count == 1, let number = numbers.first {
                        track.trackNumber = number
                        report.trackNumbersFilled += 1
                    }
                }
                if context.hasChanges { try context.save() }
            } catch {
                report.failures += 1
            }
            if index.isMultiple(of: 5) {
                print("Apple tracklists: \(index + 1) of \(albums.count)")
            }
        }
        return report
    }

    static func isExactAppleCatalogMatch(
        candidate: AppleCatalogCandidate,
        albumTitle: String,
        albumArtist: String,
        isCompilation: Bool
    ) -> Bool {
        let candidateTitle = searchable(albumCore(candidate.collectionName))
        let title = searchable(albumCore(albumTitle))
        guard candidateTitle.isEmpty == false, candidateTitle == title else { return false }
        if isCompilation, searchable(candidate.artistName) == "various artists" { return true }
        return searchable(candidate.artistName) == searchable(albumArtist)
    }

    private static func appleCatalogYear(_ candidate: AppleCatalogCandidate) -> Int? {
        guard let releaseDate = candidate.releaseDate,
              let year = Int(releaseDate.prefix(4)),
              (1900...Calendar.current.component(.year, from: Date()) + 1).contains(year)
        else { return nil }
        return year
    }

    private static func isCompilation(_ album: Album) -> Bool {
        let artists = Set(album.tracks.map { searchable($0.artist) }.filter { $0.isEmpty == false })
        if artists.count > 1 { return true }
        return album.tracks.contains { track in
            let path = searchable(track.path)
            return path.contains("various artists") || path.contains("compilations")
        }
    }

    public static func auditDiscogsEvidence(
        in context: ModelContext,
        limit: Int = 80
    ) async throws -> [DiscogsRemediationAuditItem] {
        try await auditDiscogsEvidence(in: context, limit: limit, dependencies: .live())
    }

    static func auditDiscogsEvidence(
        in context: ModelContext, limit: Int = 80, dependencies: DiscogsRemediationDependencies
    ) async throws -> [DiscogsRemediationAuditItem] {
        let albums = try context.fetch(FetchDescriptor<Album>()).filter {
            $0.tracks.isEmpty == false && needsDiscogs($0)
        }
        let cache = dependencies.cache
        var items: [DiscogsRemediationAuditItem] = []
        for album in albums {
            let lookupArtist = isCompilation(album) ? "Various Artists" : album.artist
            let query = DiscogsArtworkSearchQuery(
                albumTitle: album.title,
                albumArtist: lookupArtist,
                year: album.year > 0 ? album.year : nil
            )
            var hit = await cache.candidates(for: query)
            if hit == nil, query.year != nil {
                hit = await cache.candidates(for: DiscogsArtworkSearchQuery(
                    albumTitle: album.title,
                    albumArtist: lookupArtist
                ))
            }
            guard let hit, hit.value.isEmpty == false,
                  hit.value.contains(where: {
                      isHighConfidence(
                          candidate: $0,
                          albumTitle: album.title,
                          albumArtist: lookupArtist
                      )
                  }) == false else { continue }
            let now = dependencies.clock()
            let candidates = hit.value.prefix(3).map { candidate in
                let evidence = discogsEvidence(candidate, fetches: hit.fetches)
                return DiscogsRemediationAuditCandidate(title: candidate.title, sourcePageURL: evidence.sourcePageURL,
                                                        evidence: evidence, checkedAt: now, isFresh: evidence.isFresh(at: now))
            }
            items.append(DiscogsRemediationAuditItem(
                albumTitle: album.title,
                albumArtist: album.artist,
                candidateTitles: candidates.map(\.title), candidates: candidates
            ))
            if items.count >= limit { break }
        }
        let now = dependencies.clock()
        return items.compactMap { $0.revalidated(at: now) }
    }

    public static func applyDiscogsTrackNumbers(
        in context: ModelContext
    ) async throws -> DiscogsLibraryRemediationReport {
        try await applyDiscogsTrackNumbers(in: context, dependencies: .live())
    }

    static func applyDiscogsTrackNumbers(
        in context: ModelContext,
        dependencies: DiscogsRemediationDependencies
    ) async throws -> DiscogsLibraryRemediationReport {
        var report = DiscogsLibraryRemediationReport()
        let albums = try context.fetch(FetchDescriptor<Album>(
            sortBy: [SortDescriptor(\Album.artist), SortDescriptor(\Album.title)]
        )).filter { album in
            album.tracks.contains(where: { $0.trackNumber == 0 })
        }.map(DiscogsTarget.init)
        report.albumsConsidered = albums.count
        let cache = dependencies.cache
        let client = dependencies.client
        var lastRequestDate: Date?

        for (index, target) in albums.enumerated() {
            let lookupArtist = target.lookupArtist
            let query = DiscogsArtworkSearchQuery(
                albumTitle: target.title,
                albumArtist: lookupArtist,
                year: target.year > 0 ? target.year : nil
            )
            var hit = await cache.candidates(for: query)
            if hit == nil, query.year != nil {
                hit = await cache.candidates(for: DiscogsArtworkSearchQuery(
                    albumTitle: target.title,
                    albumArtist: lookupArtist
                ))
            }
            guard let hit else {
                report.noResultSkipped += 1
                continue
            }
            guard let candidate = hit.value.first(where: {
                isHighConfidence(candidate: $0, albumTitle: target.title, albumArtist: lookupArtist)
                    || isFuzzyConfidence(candidate: $0, albumTitle: target.title, albumArtist: lookupArtist)
            }) else {
                report.lowConfidenceSkipped += 1
                continue
            }
            if let lastRequestDate {
                let delay = 2.1 - Date().timeIntervalSince(lastRequestDate)
                if delay > 0 { try await dependencies.sleep(delay) }
            }
            lastRequestDate = Date()
            do {
                let searchEvidence = discogsEvidence(candidate, fetches: hit.fetches)
                try dependencies.requireFresh(searchEvidence)
                let release = try await client.releaseMetadata(id: candidate.id)
                report.releaseMetadataRequests += 1
                guard release.id == candidate.id else { throw DiscogsError.decodingFailed }
                let evidence = DiscogsContentEvidence(
                    releaseID: candidate.id, fetches: searchEvidence.fetches + [release.fetchedAt])
                try dependencies.requireFresh(evidence)
                guard let album = try target.resolve(in: context) else {
                    report.failures += 1
                    continue
                }
                let byTitle = Dictionary(grouping: release.tracks) { searchable(trackCore($0.title)) }
                var updates: [(track: Track, number: Int)] = []
                for track in album.tracks where track.trackNumber == 0 {
                    let matches = byTitle[searchable(trackCore(track.title)), default: []]
                    let selected: DiscogsReleaseMetadata.Track?
                    if matches.count == 1 {
                        selected = matches[0]
                    } else {
                        let durationMatches = matches.filter { releaseTrack in
                            guard let duration = releaseTrack.duration, track.duration > 0 else {
                                return false
                            }
                            return abs(duration - track.duration) <= 4
                        }
                        selected = durationMatches.count == 1 ? durationMatches[0] : nil
                    }
                    if let selected, selected.number > 0 {
                        updates.append((track, selected.number))
                    }
                }
                try dependencies.requireFresh(evidence)
                let beforeTracks = updates.map { ($0.track, $0.track.trackNumber, $0.track.trackTotal) }
                let beforeCount = report.trackNumbersFilled
                do {
                    for (track, number) in updates {
                        track.trackNumber = number
                        report.trackNumbersFilled += 1
                        if track.trackTotal == 0 { track.trackTotal = release.tracks.count }
                    }
                    try dependencies.requireFresh(evidence)
                    if context.hasChanges { try dependencies.save(context) }
                } catch {
                    for (track, number, total) in beforeTracks {
                        track.trackNumber = number
                        track.trackTotal = total
                    }
                    context.rollback()
                    report.trackNumbersFilled = beforeCount
                    throw error
                }
            } catch DiscogsError.rateLimited(let retryAfter) {
                try await dependencies.sleep(max(60, retryAfter ?? 60))
                report.failures += 1
            } catch {
                report.failures += 1
            }
            if index.isMultiple(of: 10) {
                print("Discogs tracklists: \(index + 1) of \(albums.count)")
            }
        }
        return report
    }

    private static func discogsEvidence(
        _ candidate: DiscogsArtworkCandidate, fetches: [DiscogsFetchStamp]
    ) -> DiscogsContentEvidence {
        DiscogsContentEvidence(releaseID: candidate.id,
                               fetches: fetches.contains(candidate.fetchedAt) ? fetches : fetches + [candidate.fetchedAt])
    }

    static func isHighConfidence(
        candidate: DiscogsArtworkCandidate,
        albumTitle: String,
        albumArtist: String
    ) -> Bool {
        let candidateValue = searchable(candidate.title)
        let title = searchable(albumTitle)
        let artist = searchable(albumArtist)
        guard title.isEmpty == false, candidateValue.contains(title) else { return false }
        if isMissingArtist(albumArtist) || artist == "various artists" { return true }
        return artist.isEmpty == false && candidateValue.contains(artist)
    }

    static func parsedTrackNumber(from value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns: [(source: String, capture: Int)] = [
            (#"^(\d{1,2})[-.](\d{1,3})(?:\s+|[-._])"#, 2),
            (#"^(\d{1,3})\s*[-._:]\s+"#, 1),
            (#"^[Tt]rack\s+(\d{1,3})\s*[-._:]?\s*"#, 1),
            (#"^(\d{1,3})\.\s+"#, 1),
            (#"^(\d{1,3})\s+.+"#, 1),
        ]
        for item in patterns {
            let pattern = try! NSRegularExpression(pattern: item.source)
            if let match = pattern.firstMatch(
                in: trimmed,
                range: NSRange(trimmed.startIndex..., in: trimmed)
            ), let range = Range(match.range(at: item.capture), in: trimmed) {
                return Int(trimmed[range])
            }
        }
        let partPattern = try! NSRegularExpression(
            pattern: #"^Part\s+(I|II|III|IV|V|VI|VII|VIII|IX|X)(?=\s|[_:.-]|$)"#,
            options: [.caseInsensitive]
        )
        if let match = partPattern.firstMatch(
            in: trimmed,
            range: NSRange(trimmed.startIndex..., in: trimmed)
        ), let range = Range(match.range(at: 1), in: trimmed) {
            let values = ["I": 1, "II": 2, "III": 3, "IV": 4, "V": 5,
                          "VI": 6, "VII": 7, "VIII": 8, "IX": 9, "X": 10]
            return values[String(trimmed[range]).uppercased()]
        }
        return nil
    }

    static func parsedFolderYear(from path: String) -> Int? {
        let url = URL(fileURLWithPath: path).deletingLastPathComponent()
        let components = Array(url.pathComponents.suffix(3))
        let patterns = [
            #"(?:^| - )((?:19|20)\d{2})(?= - | \[| \{|$)"#,
            #"\(((?:19|20)\d{2})\)"#,
            #"\[((?:19|20)\d{2})\]"#,
        ]
        var years: Set<Int> = []
        for component in components {
            for source in patterns {
                let pattern = try! NSRegularExpression(pattern: source)
                let range = NSRange(component.startIndex..., in: component)
                for match in pattern.matches(in: component, range: range) {
                    guard let valueRange = Range(match.range(at: 1), in: component),
                          let year = Int(component[valueRange]),
                          (1900...Calendar.current.component(.year, from: Date()) + 1).contains(year)
                    else { continue }
                    years.insert(year)
                }
            }
        }
        return years.count == 1 ? years.first : nil
    }

    static func parsedRemasterYear(from value: String) -> Int? {
        let pattern = try! NSRegularExpression(
            pattern: #"\b((?:19|20)\d{2})\s+remaster(?:ed)?\b"#,
            options: [.caseInsensitive]
        )
        guard let match = pattern.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ), let range = Range(match.range(at: 1), in: value),
              let year = Int(value[range]),
              (1900...Calendar.current.component(.year, from: Date()) + 1).contains(year)
        else { return nil }
        return year
    }

    static func normalizedSequentialTrackNumbers(_ values: [Int]) -> [Int]? {
        guard values.isEmpty == false,
              let minimum = values.min(), minimum >= 1_000,
              let maximum = values.max(),
              Set(values).count == values.count,
              maximum - minimum + 1 == values.count
        else { return nil }
        return values.map { $0 - minimum + 1 }
    }

    private static func sequentialFilenamePrefix(from path: String) -> Int? {
        let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let pattern = try! NSRegularExpression(pattern: #"^(\d{4})\.\s+"#)
        guard let match = pattern.firstMatch(
            in: filename,
            range: NSRange(filename.startIndex..., in: filename)
        ), let range = Range(match.range(at: 1), in: filename) else { return nil }
        return Int(filename[range])
    }

    static func isFuzzyConfidence(
        candidate: DiscogsArtworkCandidate,
        albumTitle: String,
        albumArtist: String
    ) -> Bool {
        let candidateTokens = Set(searchable(candidate.title).split(separator: " ").map(String.init))
        let titleTokens = significantTokens(in: albumCore(albumTitle))
        let artistTokens = significantTokens(in: albumArtist)
        guard titleTokens.isEmpty == false, candidateTokens.isEmpty == false else { return false }

        let compactCandidate = searchable(candidate.title).replacingOccurrences(of: " ", with: "")
        let compactTitle = searchable(albumCore(albumTitle)).replacingOccurrences(of: " ", with: "")
        let compactArtist = searchable(albumArtist).replacingOccurrences(of: " ", with: "")
        let titleNumbers = Set(titleTokens.filter { $0.allSatisfy(\.isNumber) })
        guard titleNumbers.isSubset(of: candidateTokens) else { return false }
        if compactTitle.isEmpty == false, compactCandidate.contains(compactTitle) {
            if isMissingArtist(albumArtist) || searchable(albumArtist) == "various artists" {
                return true
            }
            if compactArtist.isEmpty == false, compactCandidate.contains(compactArtist) {
                return true
            }
        }

        let titleMatches = titleTokens.filter(candidateTokens.contains).count
        let titleCoverage = Double(titleMatches) / Double(titleTokens.count)
        guard titleCoverage >= 0.75 else { return false }

        if isMissingArtist(albumArtist) || searchable(albumArtist) == "various artists" {
            return titleCoverage >= 0.85
        }
        guard artistTokens.isEmpty == false else { return false }
        let artistMatches = artistTokens.filter(candidateTokens.contains).count
        let artistCoverage = Double(artistMatches) / Double(artistTokens.count)
        return artistMatches >= 1 && artistCoverage >= 0.5
    }

    private static func apply(
        _ metadata: AudioMetadata,
        to track: Track,
        report: inout LocalLibraryRemediationReport
    ) {
        if isMissingArtist(track.artist), isMissingArtist(metadata.artist) == false {
            track.artist = normalized(metadata.artist); report.artistsFilled += 1
        }
        if isMissingAlbum(track.album), isMissingAlbum(metadata.album) == false {
            track.album = normalized(metadata.album); report.albumsFilled += 1
        }
        if normalized(track.title).isEmpty, normalized(metadata.title).isEmpty == false {
            track.title = normalized(metadata.title); report.titlesFilled += 1
        }
        if isMissingArtist(track.albumArtist), isMissingArtist(metadata.albumArtist) == false {
            track.albumArtist = normalized(metadata.albumArtist); report.albumArtistsFilled += 1
        }
        if GenreMetadata.isMissing(track.genre), GenreMetadata.isMissing(metadata.genre) == false {
            track.genre = GenreMetadata.normalized(metadata.genre); report.genresFilled += 1
        }
        if track.year == 0, metadata.year > 0 { track.year = metadata.year; report.yearsFilled += 1 }
        if track.trackNumber == 0, metadata.trackNumber > 0 {
            track.trackNumber = metadata.trackNumber; report.trackNumbersFilled += 1
        }
        if track.trackTotal == 0, metadata.trackTotal > 0 {
            track.trackTotal = metadata.trackTotal; report.trackTotalsFilled += 1
        }
        if track.discNumber == 0, metadata.discNumber > 0 {
            track.discNumber = metadata.discNumber; report.discNumbersFilled += 1
        }
        if track.discTotal == 0, metadata.discTotal > 0 {
            track.discTotal = metadata.discTotal; report.discTotalsFilled += 1
        }
    }

    private static func applyFolderAndSiblingEvidence(
        to tracks: [Track],
        report: inout LocalLibraryRemediationReport
    ) {
        let byFolder = Dictionary(grouping: tracks) {
            URL(fileURLWithPath: $0.path).deletingLastPathComponent().standardizedFileURL.path
        }
        for track in tracks {
            let url = URL(fileURLWithPath: track.path)
            let folder = url.deletingLastPathComponent()
            let siblings = byFolder[folder.standardizedFileURL.path, default: []]
            if isMissingAlbum(track.album) {
                let known = siblings.map(\.album).filter { isMissingAlbum($0) == false }
                if let value = unanimous(known) ?? meaningfulFolderName(folder) {
                    track.album = value; report.albumsFilled += 1
                }
            }
            if isMissingArtist(track.artist) {
                let known = siblings.map(\.artist).filter { isMissingArtist($0) == false }
                let albumFolder = isDiscFolder(folder.lastPathComponent)
                    ? folder.deletingLastPathComponent()
                    : folder
                let artistFolder = albumFolder.deletingLastPathComponent()
                if let value = unanimous(known) ?? meaningfulFolderName(artistFolder) {
                    track.artist = value; report.artistsFilled += 1
                }
            }
            if isMissingArtist(track.albumArtist), isMissingArtist(track.artist) == false {
                track.albumArtist = track.artist; report.albumArtistsFilled += 1
            }
            if normalized(track.title).isEmpty {
                let value = url.deletingPathExtension().lastPathComponent
                if value.isEmpty == false { track.title = value; report.titlesFilled += 1 }
            }
            if track.trackNumber == 0 {
                let filename = url.deletingPathExtension().lastPathComponent
                if let number = parsedTrackNumber(from: track.title)
                    ?? parsedTrackNumber(from: filename), number > 0 {
                    track.trackNumber = number; report.trackNumbersFilled += 1
                }
            }
            if track.year == 0, let year = parsedFolderYear(from: track.path) {
                track.year = year
                report.yearsFilled += 1
            }
        }
    }

    private static func applyUnanimousAlbumEvidence(
        albums: [Album],
        report: inout LocalLibraryRemediationReport
    ) {
        for album in albums where album.tracks.isEmpty == false {
            let missingNumberTracks = album.tracks.filter { $0.trackNumber == 0 }
            let sequentialPrefixes = missingNumberTracks.compactMap {
                sequentialFilenamePrefix(from: $0.path)
            }
            if sequentialPrefixes.count == missingNumberTracks.count,
               let numbers = normalizedSequentialTrackNumbers(sequentialPrefixes) {
                for (track, number) in zip(missingNumberTracks, numbers) {
                    track.trackNumber = number
                    report.trackNumbersFilled += 1
                }
            }
            let editionYears = Set(
                ([album.title] + album.tracks.map(\.title)).compactMap(parsedRemasterYear)
            )
            if editionYears.count == 1, let year = editionYears.first {
                if album.year == 0 {
                    album.year = year
                    report.albumRecordsUpdated += 1
                }
                for track in album.tracks where track.year == 0 {
                    track.year = year
                    report.yearsFilled += 1
                }
            }
            let genres = album.tracks.map(\.genre).filter { GenreMetadata.isMissing($0) == false }
            if let genre = unanimous(genres) {
                for track in album.tracks where GenreMetadata.isMissing(track.genre) {
                    track.genre = genre; report.genresFilled += 1
                }
            }
            let years = Set(album.tracks.map(\.year).filter { $0 > 0 })
            if years.count == 1, let year = years.first {
                for track in album.tracks where track.year == 0 {
                    track.year = year; report.yearsFilled += 1
                }
            }
            let discs = Dictionary(grouping: album.tracks) { $0.discNumber }
            for discTracks in discs.values {
                let missing = discTracks.filter { $0.trackNumber == 0 }
                guard missing.count == 1, let track = missing.first else { continue }
                if discTracks.count == 1 {
                    track.trackNumber = 1
                    report.trackNumbersFilled += 1
                    if track.trackTotal == 0 {
                        track.trackTotal = 1
                        report.trackTotalsFilled += 1
                    }
                    continue
                }
                let known = Set(discTracks.map(\.trackNumber).filter { $0 > 0 })
                let available = Set(1...discTracks.count).subtracting(known)
                if available.count == 1, let number = available.first {
                    track.trackNumber = number
                    report.trackNumbersFilled += 1
                }
            }
            let titleGroups = Dictionary(grouping: album.tracks) { searchable($0.title) }
            let groupNumbers = titleGroups.mapValues { group in
                Set(group.map(\.trackNumber).filter { $0 > 0 })
            }
            let missingGroups = titleGroups.filter { groupNumbers[$0.key, default: []].isEmpty }
            let knownNumbers = Set(groupNumbers.values.flatMap { $0 })
            let available = Set(1...titleGroups.count).subtracting(knownNumbers)
            if missingGroups.count == 1, available.count == 1,
               let number = available.first, let group = missingGroups.first?.value {
                for track in group where track.trackNumber == 0 {
                    track.trackNumber = number
                    report.trackNumbersFilled += 1
                }
            }
        }
    }

    private static func applyCaseCanonicalization(
        to tracks: [Track],
        report: inout LocalLibraryRemediationReport
    ) {
        canonicalize(tracks: tracks, get: { $0.artist }, set: { $0.artist = $1 }, report: &report)
        canonicalize(tracks: tracks, get: { $0.album }, set: { $0.album = $1 }, report: &report)
        canonicalize(tracks: tracks, get: { $0.albumArtist }, set: { $0.albumArtist = $1 }, report: &report)
        canonicalize(tracks: tracks, get: { $0.genre }, set: { $0.genre = $1 }, report: &report)
    }

    private static func applyCrossRecordEvidence(
        albums: [Album],
        tracks: [Track],
        report: inout LocalLibraryRemediationReport
    ) {
        let albumGroups = Dictionary(grouping: albums.filter { $0.tracks.isEmpty == false }) {
            "\(searchable($0.artist))\u{1f}\(searchable($0.title))"
        }
        for group in albumGroups.values {
            let years = Set(group.map(\.year).filter { $0 > 0 })
            let artwork = group.compactMap(\.artworkData)
            let sharedArtwork: Data? = {
                guard let first = artwork.first,
                      artwork.dropFirst().allSatisfy({ $0 == first }) else { return nil }
                return first
            }()
            let allTracks = group.flatMap(\.tracks)
            let genres = allTracks.map(\.genre).filter { GenreMetadata.isMissing($0) == false }
            let sharedGenre = unanimous(genres)
            let numbersByTitle = Dictionary(grouping: allTracks.filter { $0.trackNumber > 0 }) {
                searchable($0.title)
            }.mapValues { Set($0.map(\.trackNumber)) }

            for album in group {
                if album.year == 0, years.count == 1, let year = years.first {
                    album.year = year
                    report.albumRecordsUpdated += 1
                }
                if album.artworkData == nil, let sharedArtwork {
                    album.artworkData = sharedArtwork
                    report.artworkFilled += 1
                }
                for track in album.tracks {
                    if track.year == 0, years.count == 1, let year = years.first {
                        track.year = year
                        report.yearsFilled += 1
                    }
                    if GenreMetadata.isMissing(track.genre), let sharedGenre {
                        track.genre = sharedGenre
                        report.genresFilled += 1
                    }
                    if track.trackNumber == 0 {
                        let numbers = numbersByTitle[searchable(track.title), default: []]
                        if numbers.count == 1, let number = numbers.first {
                            track.trackNumber = number
                            report.trackNumbersFilled += 1
                        }
                    }
                }
            }
        }

        let artistGroups = Dictionary(grouping: tracks.filter { isMissingArtist($0.artist) == false }) {
            searchable($0.artist)
        }
        for group in artistGroups.values {
            let genres = group.map(\.genre).filter { GenreMetadata.isMissing($0) == false }
            guard let genre = unanimous(genres) else { continue }
            for track in group where GenreMetadata.isMissing(track.genre) {
                track.genre = genre
                report.genresFilled += 1
            }
        }
    }

    private static func canonicalize(
        tracks: [Track],
        get: (Track) -> String,
        set: (Track, String) -> Void,
        report: inout LocalLibraryRemediationReport
    ) {
        let grouped = Dictionary(grouping: tracks.filter { normalized(get($0)).isEmpty == false }) {
            normalized(get($0)).lowercased()
        }
        for values in grouped.values {
            let counts = Dictionary(grouping: values.map(get), by: { $0 }).mapValues(\.count)
            guard counts.count > 1 else { continue }
            let ranked = counts.sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            guard ranked.count == 1 || ranked[0].value > ranked[1].value else { continue }
            let canonical = ranked[0].key
            for track in values where get(track) != canonical {
                set(track, canonical); report.caseVariantsUnified += 1
            }
        }
    }

    private static func updateRelationshipRecords(
        albums: [Album],
        artists: [Artist],
        report: inout LocalLibraryRemediationReport
    ) {
        for album in albums where album.tracks.isEmpty == false {
            var changed = false
            if isMissingAlbum(album.title),
               let title = unanimous(album.tracks.map(\.album).filter { isMissingAlbum($0) == false }) {
                album.title = title; changed = true
            }
            if isMissingArtist(album.artist),
               let artist = unanimous(album.tracks.map { track in
                   isMissingArtist(track.albumArtist) ? track.artist : track.albumArtist
               }.filter { isMissingArtist($0) == false }) {
                album.artist = artist; changed = true
            }
            if album.year == 0 {
                let years = Set(album.tracks.map(\.year).filter { $0 > 0 })
                if years.count == 1, let year = years.first { album.year = year; changed = true }
            }
            if changed { report.albumRecordsUpdated += 1 }
        }
        for artist in artists where artist.tracks.isEmpty == false && isMissingArtist(artist.name) {
            if let name = unanimous(artist.tracks.map(\.artist).filter { isMissingArtist($0) == false }) {
                artist.name = name; report.artistRecordsUpdated += 1
            }
        }
    }

    private static func needsMetadata(_ track: Track) -> Bool {
        isMissingArtist(track.artist) || isMissingAlbum(track.album)
            || normalized(track.title).isEmpty || isMissingArtist(track.albumArtist)
            || GenreMetadata.isMissing(track.genre) || track.year == 0
            || track.trackNumber == 0 || track.trackTotal == 0
            || track.discNumber == 0 || track.discTotal == 0
    }

    private static func needsDiscogs(_ album: Album) -> Bool {
        guard isMissingAlbum(album.title) == false, isMissingArtist(album.artist) == false else {
            return false
        }
        return album.artworkData == nil || album.year == 0
            || album.tracks.contains(where: {
                GenreMetadata.isMissing($0.genre) || $0.year == 0
            })
    }

    private static func isMissingArtist(_ value: String) -> Bool {
        let value = normalized(value)
        return value.isEmpty || value.caseInsensitiveCompare("Unknown Artist") == .orderedSame
    }

    private static func isMissingAlbum(_ value: String) -> Bool {
        let value = normalized(value)
        return value.isEmpty || value.caseInsensitiveCompare("Unknown Album") == .orderedSame
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func canonicalIdentifier(_ value: String) -> String? {
        let value = normalized(value)
        guard value.count == 36,
              value[value.index(value.startIndex, offsetBy: 8)] == "-",
              value[value.index(value.startIndex, offsetBy: 13)] == "-",
              value[value.index(value.startIndex, offsetBy: 18)] == "-",
              value[value.index(value.startIndex, offsetBy: 23)] == "-",
              UUID(uuidString: value) != nil else {
            return nil
        }
        return value.lowercased()
    }

    private static func searchable(_ value: String) -> String {
        let folded = normalized(value).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let cleaned = folded.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " "
        }
        return String(cleaned).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func albumCore(_ value: String) -> String {
        let bracketStripped = value.replacingOccurrences(
            of: #"\s*[\(\[].*[\)\]]\s*$"#,
            with: "",
            options: .regularExpression
        )
        return bracketStripped.replacingOccurrences(
            of: #"\s*-\s*(?:(?:the\s+\d+(?:st|nd|rd|th)\s+)?(?:summer\s+)?(?:mini\s+)?album|single|ep|sm\s+station|the\s+millennium\s+collection)\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    static func trackCore(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\s*(?:[-–—]\s*)?(?:\(|\[)?(?:mixed|original mix|radio edit|edit)(?:\)|\])?\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func significantTokens(in value: String) -> Set<String> {
        let ignored: Set<String> = [
            "a", "an", "and", "the", "of", "edition", "deluxe", "remaster",
            "remastered", "original", "version", "vinyl", "sacd", "hybrid",
            "import", "pressing", "mono", "stereo", "single", "cd",
        ]
        return Set(searchable(value).split(separator: " ").map(String.init).filter {
            ignored.contains($0) == false
        })
    }

    private static func unanimous(_ values: [String]) -> String? {
        let meaningful = values.map(normalized).filter { $0.isEmpty == false }
        let grouped = Dictionary(grouping: meaningful) { $0.lowercased() }
        guard grouped.count == 1 else { return nil }
        return grouped.values.first?.first
    }

    private static func meaningfulFolderName(_ url: URL) -> String? {
        let value = normalized(url.lastPathComponent)
        guard value.isEmpty == false else { return nil }
        let blocked: Set<String> = [
            "music", "downloads", "audio", "media", "library", "itunes",
            "amarra", "home", "desktop", "documents",
        ]
        guard blocked.contains(value.lowercased()) == false, isDiscFolder(value) == false else {
            return nil
        }
        return value
    }

    private static func isDiscFolder(_ value: String) -> Bool {
        value.range(
            of: #"^(cd|disc|disk)\s*\d+$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

private enum IdentifierMetadataRepairError: Error, LocalizedError {
    case proposalScopeChanged

    var errorDescription: String? {
        "Identifier metadata repair scope changed after preview; no changes were saved."
    }
}
