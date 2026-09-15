import XCTest

@testable import SongbirdLib

final class DiscogsCDCacheTests: XCTestCase {
    func testCDCacheWrapperRechecksAfterKernelActorHop() async throws {
        let fixture = try DiscogsHTTPFixture()
        let folder = fixture.directory.appendingPathComponent("metadata")
        let stamp = TestDiscogsClock.stamp()
        let writer = AudioCDMetadataCache(directory: folder, clock: { stamp })
        let candidate = AudioCDMetadataCandidate(id: "discogs:42", title: "Album", artist: "Artist",
            country: nil, date: nil, tracks: [], artworkURL: nil, score: 1,
            discogsEvidence: .init(releaseID: 42, fetches: [stamp]))
        let seeded = await writer.storeDiscogs([candidate], discID: "disc", fetches: [stamp])
        XCTAssertTrue(seeded)
        let loadClock = TestDiscogsClock([stamp, TestDiscogsClock.stamp(18_000)])
        let reader = AudioCDMetadataCache(directory: folder, clock: { loadClock.sample() })
        let hit = await reader.loadDiscogs(discID: "disc")
        XCTAssertNil(hit, "Fresh kernel return must be checked again after the actor hop")
        let storeClock = TestDiscogsClock([stamp, TestDiscogsClock.stamp(18_000)])
        let storing = AudioCDMetadataCache(directory: fixture.directory.appendingPathComponent("other"),
            clock: { storeClock.sample() })
        let accepted = await storing.storeDiscogs([candidate], discID: "disc", fetches: [stamp])
        XCTAssertFalse(accepted, "Expired actor-hop completion cannot report accepted content")
    }

    func testActualReleasePipelineCannotPublishAfterDelayedResponseHandoff() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock()
        let client = GatedDiscogsCDClient(client: DiscogsClient(session: fixture.session,
            clock: { clock.sample() }, tokenProvider: { "synthetic" }))
        let provider = DiscogsAudioCDMetadataProvider(client: client,
            searchCache: .init(fileURL: fixture.directory.appendingPathComponent("search.cache"), clock: { clock.sample() }),
            metadataCache: .init(directory: fixture.directory.appendingPathComponent("metadata"), clock: { clock.sample() }),
            clock: { clock.sample() })
        let lookup = Task { try await provider.candidates(for: .init(discID: "disc", albumTitle: "Album", tracks: [])) }
        for _ in 0..<200 {
            if await client.hasPendingRelease { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let pending = await client.hasPendingRelease
        XCTAssertTrue(pending)
        XCTAssertEqual(try fixture.requests().count, 2)
        clock.set(TestDiscogsClock.stamp(18_000))
        await client.resume()
        do {
            _ = try await lookup.value
            XCTFail("Expired response handoff was published")
        } catch DiscogsError.resultsExpired {
            // Expected typed expiry from the provider's publication guard.
        }
    }

    func testCacheActorFreshnessDoesNotReplaceProviderReturnFreshness() async throws {
        let fixture = try DiscogsHTTPFixture()
        let cache = AudioCDMetadataCache(directory: fixture.directory.appendingPathComponent("metadata"),
            lifetime: 30 * 24 * 60 * 60, clock: { TestDiscogsClock.stamp() })
        let candidate = AudioCDMetadataCandidate(id: "discogs:42", title: "Album", artist: "Artist",
            country: nil, date: nil, tracks: [], artworkURL: nil, score: 1,
            discogsEvidence: .init(releaseID: 42, fetches: [TestDiscogsClock.stamp()]))
        let accepted = await cache.storeDiscogs([candidate], discID: "disc", fetches: [TestDiscogsClock.stamp()])
        XCTAssertTrue(accepted)
        let provider = DiscogsAudioCDMetadataProvider(
            client: DiscogsClient(session: fixture.session, tokenProvider: { XCTFail("Unexpected request"); return "synthetic" }),
            searchCache: .init(fileURL: fixture.directory.appendingPathComponent("search.cache")), metadataCache: cache,
            clock: { TestDiscogsClock.stamp(18_000) })
        do {
            _ = try await provider.candidates(for: .init(discID: "disc", tracks: []))
            XCTFail("Cached return missed provider-side expiry")
        } catch DiscogsError.resultsExpired {
            // Expected typed expiry from the provider's publication guard.
        }
        XCTAssertTrue(try fixture.requests().isEmpty)
    }

    func testFallbackRetainsEveryOriginalSearchCacheAcquisition() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(3)])
        let search = DiscogsArtworkSearchCache(fileURL: fixture.directory.appendingPathComponent("search.cache"),
            clock: { clock.sample() })
        let metadata = AudioCDMetadataCache(directory: fixture.directory.appendingPathComponent("metadata"), clock: { clock.sample() })
        let candidate = DiscogsArtworkCandidate(id: 42, title: "Album", artist: "Artist", year: nil, country: nil,
            formats: ["CD"], genres: [], styles: [], thumbnailURL: nil,
            imageURL: URL(string: "https://fixture.test/from-search.png")!,
            sourcePageURL: URL(string: "https://www.discogs.com/release/42")!, fetchedAt: TestDiscogsClock.stamp(2))
        let query = DiscogsArtworkSearchQuery(albumTitle: "Album", albumArtist: "Artist")
        let stored = await search.store([candidate], for: query,
            fetches: [TestDiscogsClock.stamp(1), TestDiscogsClock.stamp(2)])
        XCTAssertTrue(stored)
        let provider = DiscogsAudioCDMetadataProvider(client: DiscogsClient(session: fixture.session,
            clock: { clock.sample() }, tokenProvider: { "synthetic" }),
            searchCache: search, metadataCache: metadata, clock: { clock.sample() })
        let results = try await provider.candidates(for: .init(discID: "disc", albumTitle: "Album", albumArtist: "Artist", tracks: []))
        XCTAssertEqual(results.first?.artworkURL, candidate.imageURL)
        XCTAssertEqual(results.first?.discogsEvidence?.fetches,
            [TestDiscogsClock.stamp(1), TestDiscogsClock.stamp(2), TestDiscogsClock.stamp(3)])
        let storedHit = await metadata.loadDiscogs(discID: "disc")
        XCTAssertEqual(storedHit?.value, results)
        XCTAssertEqual(storedHit?.fetches, [TestDiscogsClock.stamp(1), TestDiscogsClock.stamp(2), TestDiscogsClock.stamp(3)])
        XCTAssertEqual(try fixture.requests().count, 1)
    }

    func testUnstampedCDEntriesCannotBecomeDiscogsCacheHits() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock()
        let cache = AudioCDMetadataCache(
            directory: fixture.directory.appendingPathComponent("metadata"),
            clock: { clock.sample() })
        let candidate = AudioCDMetadataCandidate(
            id: "discogs:42", title: "Album", artist: "Artist",
            country: nil, date: nil, tracks: [], artworkURL: nil, score: 1)
        let accepted = await cache.storeDiscogs(
            [candidate], discID: "disc", fetches: [TestDiscogsClock.stamp()])
        XCTAssertFalse(accepted)
        let hit = await cache.loadDiscogs(discID: "disc")
        XCTAssertNil(hit)
        // Same candidate is ordinary data to the generic MusicBrainz cache, which is not expired or wiped.
        await cache.store([candidate], discID: "ordinary")
        let ordinary = await cache.load(discID: "ordinary")
        XCTAssertEqual(ordinary, [candidate])
    }

    func testNoCDTextDoesNotWriteAnEmptyAPICache() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock()
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() }, tokenProvider: { "synthetic" })
        let folder = fixture.directory.appendingPathComponent("metadata")
        let provider = DiscogsAudioCDMetadataProvider(
            client: client,
            searchCache: DiscogsArtworkSearchCache(
                fileURL: fixture.directory.appendingPathComponent("search.cache"),
                clock: { clock.sample() }),
            metadataCache: AudioCDMetadataCache(directory: folder, clock: { clock.sample() }),
            clock: { clock.sample() })
        _ = try await provider.candidates(for: .init(discID: "same-disc", tracks: []))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: folder.appendingPathComponent("same%2Ddisc.json").path))
        let legacy = AudioCDMetadataCache(directory: folder)
        let noAPICache = await legacy.load(discID: "same-disc")
        XCTAssertNil(noAPICache)
        _ = try await provider.candidates(
            for: .init(discID: "same-disc", albumTitle: "empty", tracks: []))
        XCTAssertEqual(try fixture.requests().count, 1)
    }

    func testCDFallbackArtworkRetainsBothSearchAndReleaseAcquisitions() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock()
        let search = DiscogsArtworkSearchCache(
            fileURL: fixture.directory.appendingPathComponent("search.cache"),
            clock: { clock.sample() })
        let metadata = AudioCDMetadataCache(
            directory: fixture.directory.appendingPathComponent("metadata"),
            clock: { clock.sample() })
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() },
            tokenProvider: {
                let next = clock.sample()!.wall.timeIntervalSince1970 - 1_000 + 1
                clock.set(TestDiscogsClock.stamp(next))
                return "synthetic"
            })
        let provider = DiscogsAudioCDMetadataProvider(
            client: client, searchCache: search, metadataCache: metadata, clock: { clock.sample() })
        let query = AudioCDMetadataQuery(discID: "disc", albumTitle: "Album", tracks: [])
        let results = try await provider.candidates(for: query)
        let candidate = try XCTUnwrap(results.first)
        let evidence = try XCTUnwrap(candidate.discogsEvidence)
        XCTAssertEqual(evidence.releaseID, 42)
        XCTAssertEqual(evidence.fetches, [TestDiscogsClock.stamp(1), TestDiscogsClock.stamp(2)])
        let cached = try await provider.candidates(for: query)
        XCTAssertEqual(cached, results)
        XCTAssertEqual(cached.first?.discogsEvidence, evidence)
    }

    func testDiscogsNegativeCacheCannotUseGenericLongLifetime() async throws {
        let fixture = try DiscogsHTTPFixture()
        let clock = TestDiscogsClock()
        let client = DiscogsClient(
            session: fixture.session, clock: { clock.sample() }, tokenProvider: { "synthetic" })
        let search = DiscogsArtworkSearchCache(
            fileURL: fixture.directory.appendingPathComponent("search.cache"),
            clock: { clock.sample() })
        let metadata = AudioCDMetadataCache(
            directory: fixture.directory.appendingPathComponent("metadata"),
            lifetime: 30 * 24 * 60 * 60, clock: { clock.sample() })
        let provider = DiscogsAudioCDMetadataProvider(
            client: client, searchCache: search, metadataCache: metadata, clock: { clock.sample() })
        let query = AudioCDMetadataQuery(discID: "disc", albumTitle: "empty", tracks: [])
        let first = try await provider.candidates(for: query)
        let second = try await provider.candidates(for: query)
        XCTAssertEqual(first, [])
        XCTAssertEqual(first, second)
        XCTAssertEqual(try fixture.requests().count, 1)
        clock.set(TestDiscogsClock.stamp(18_000))
        _ = try await provider.candidates(for: query)
        XCTAssertEqual(try fixture.requests().count, 2)
    }
}
