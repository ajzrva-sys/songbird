import AppKit
import Foundation
import SwiftData
import Testing
@testable import SongbirdLib

struct RealLibraryRemediatorTests {
    @Test("Discogs confidence requires matching album and artist")
    @MainActor
    func confidenceRequiresAlbumAndArtist() {
        let candidate = makeCandidate(title: "Crystal Castles - (III)")
        #expect(RealLibraryRemediator.isHighConfidence(
            candidate: candidate,
            albumTitle: "(III)",
            albumArtist: "Crystal Castles"
        ))
        #expect(RealLibraryRemediator.isHighConfidence(
            candidate: candidate,
            albumTitle: "Crystal",
            albumArtist: "Another Artist"
        ) == false)
    }

    @Test("Various Artists matches use the album title")
    @MainActor
    func variousArtistsUsesTitle() {
        #expect(RealLibraryRemediator.isHighConfidence(
            candidate: makeCandidate(title: "Dance Classics 2026"),
            albumTitle: "Dance Classics 2026",
            albumArtist: "Various Artists"
        ))
    }

    @Test("Fuzzy confidence accepts edition suffixes but rejects wrong releases")
    @MainActor
    func fuzzyConfidenceIsConservative() {
        #expect(RealLibraryRemediator.isFuzzyConfidence(
            candidate: makeCandidate(title: "Bob Dylan - Blonde On Blonde"),
            albumTitle: "Blonde On Blonde (US Mono)",
            albumArtist: "Bob Dylan"
        ))
        #expect(RealLibraryRemediator.isFuzzyConfidence(
            candidate: makeCandidate(title: "Bob Marley & The Wailers - Legend"),
            albumTitle: "Kaya (2013 Remaster)",
            albumArtist: "Bob Marley & The Wailers"
        ) == false)
        #expect(RealLibraryRemediator.isFuzzyConfidence(
            candidate: makeCandidate(title: "Various - Global Underground Select 2"),
            albumTitle: "Global Underground: Select #3",
            albumArtist: "Various Artists"
        ) == false)
        #expect(RealLibraryRemediator.isFuzzyConfidence(
            candidate: makeCandidate(title: "Band Of Horses - CeaseTo Begin"),
            albumTitle: "Cease to Begin (Japan Import)",
            albumArtist: "Band of Horses"
        ))
        #expect(RealLibraryRemediator.isFuzzyConfidence(
            candidate: makeCandidate(title: "Lusine - Push EP"),
            albumTitle: "Push EP",
            albumArtist: "L'usine"
        ))
        #expect(RealLibraryRemediator.isFuzzyConfidence(
            candidate: makeCandidate(title: "Red Velvet - Queendom"),
            albumTitle: "Queendom - The 6th Mini Album",
            albumArtist: "Red Velvet"
        ))
        #expect(RealLibraryRemediator.isFuzzyConfidence(
            candidate: makeCandidate(title: "Rone - Apache"),
            albumTitle: "Apache - EP",
            albumArtist: "Rone"
        ))
    }

    @Test("Track numbers are parsed only from clear prefixes")
    @MainActor
    func parsesClearTrackNumbers() {
        #expect(RealLibraryRemediator.parsedTrackNumber(from: "01 - Opening") == 1)
        #expect(RealLibraryRemediator.parsedTrackNumber(from: "08 Homeland") == 8)
        #expect(RealLibraryRemediator.parsedTrackNumber(from: "1-04 Finale") == 4)
        #expect(RealLibraryRemediator.parsedTrackNumber(from: "01-27-Scriabin") == 27)
        #expect(RealLibraryRemediator.parsedTrackNumber(from: "01 1993 (Nacht)") == 1)
        #expect(RealLibraryRemediator.parsedTrackNumber(from: "Track 12 Finale") == 12)
        #expect(RealLibraryRemediator.parsedTrackNumber(from: "Part IV_ Psalm") == 4)
        #expect(RealLibraryRemediator.parsedTrackNumber(from: "1984") == nil)
    }

    @Test("Track-list matching removes only trailing mix and edit labels")
    @MainActor
    func trackCoreIsConservative() {
        #expect(RealLibraryRemediator.trackCore("Atrapa - Mixed") == "Atrapa")
        #expect(RealLibraryRemediator.trackCore("Australia (Edit)") == "Australia")
        #expect(RealLibraryRemediator.trackCore("Take Words in Return - C2 Vocal Remix")
            == "Take Words in Return - C2 Vocal Remix")
    }

    @Test("Release years are parsed only from packaging-style folder markers")
    @MainActor
    func parsesConservativeFolderYears() {
        #expect(RealLibraryRemediator.parsedFolderYear(
            from: "/Music/Artist/Artist - 2019 - Album [FLAC]/01 Song.m4a"
        ) == 2019)
        #expect(RealLibraryRemediator.parsedFolderYear(
            from: "/Music/Artist/Album (2013) [FLAC]/01 Song.m4a"
        ) == 2013)
        #expect(RealLibraryRemediator.parsedFolderYear(
            from: "/Music/Artist/Album - 2015 [24-96]/01 Song.m4a"
        ) == 2015)
        #expect(RealLibraryRemediator.parsedFolderYear(
            from: "/Music/Artist/Live 1994-10-31/01 Song.m4a"
        ) == nil)
        #expect(RealLibraryRemediator.parsedRemasterYear(from: "Kaya (2013 Remaster)") == 2013)
        #expect(RealLibraryRemediator.parsedRemasterYear(from: "Live in Japan 1985") == nil)
    }

    @Test("Large sequential filename prefixes normalize only when gap-free")
    @MainActor
    func normalizesSequentialFilenamePrefixes() {
        #expect(RealLibraryRemediator.normalizedSequentialTrackNumbers(
            [1_001, 1_002, 1_003]
        ) == [1, 2, 3])
        #expect(RealLibraryRemediator.normalizedSequentialTrackNumbers(
            [1_001, 1_003]
        ) == nil)
        #expect(RealLibraryRemediator.normalizedSequentialTrackNumbers(
            [1_001, 1_001]
        ) == nil)
        #expect(RealLibraryRemediator.normalizedSequentialTrackNumbers(
            [1, 2, 3]
        ) == nil)
    }

    @Test("Apple catalog matching requires exact album and artist identity")
    @MainActor
    func appleCatalogMatchingIsExact() {
        let candidate = AppleCatalogCandidate(
            collectionId: 1,
            artistName: "Valentina Lisitsa",
            collectionName: "Nuances",
            releaseDate: "2015-01-01T00:00:00Z",
            primaryGenreName: "Classical",
            artworkUrl100: URL(string: "https://example.com/100x100bb.jpg")
        )
        #expect(RealLibraryRemediator.isExactAppleCatalogMatch(
            candidate: candidate,
            albumTitle: "Nuances",
            albumArtist: "Valentina Lisitsa",
            isCompilation: false
        ))
        #expect(RealLibraryRemediator.isExactAppleCatalogMatch(
            candidate: candidate,
            albumTitle: "Nuances II",
            albumArtist: "Valentina Lisitsa",
            isCompilation: false
        ) == false)
        #expect(RealLibraryRemediator.isExactAppleCatalogMatch(
            candidate: candidate,
            albumTitle: "Nuances",
            albumArtist: "Another Artist",
            isCompilation: false
        ) == false)
    }

    @Test("BPM verification fills only an empty value from valid evidence")
    @MainActor
    func acceptsOnlyMissingValidBPM() {
        #expect(RealLibraryRemediator.acceptedMissingBPM(
            current: 0,
            tagged: 124,
            detected: 130
        ) == 124)
        #expect(RealLibraryRemediator.acceptedMissingBPM(
            current: 0,
            tagged: 0,
            detected: 130
        ) == 130)
        #expect(RealLibraryRemediator.acceptedMissingBPM(
            current: 110,
            tagged: 124,
            detected: 130
        ) == nil)
        #expect(RealLibraryRemediator.acceptedMissingBPM(
            current: 0,
            tagged: 1_000,
            detected: 0
        ) == nil)
    }

    @Test("Identifier metadata repair is scoped, complete, and idempotent")
    @MainActor
    func repairsIdentifierMetadataWithUnanimousEvidence() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let corruptValue = UUID().uuidString.lowercased()
        let album = Album(title: "Example Album", artist: corruptValue)
        let first = Track(path: "/tmp/\(UUID().uuidString).m4a", title: "One", artist: "Example Artist", album: album.title)
        let second = Track(path: "/tmp/\(UUID().uuidString).m4a", title: "Two", artist: "Example Artist", album: album.title)
        first.albumArtist = corruptValue
        second.albumArtist = corruptValue
        first.albumRelation = album
        second.albumRelation = album
        context.insert(album)
        context.insert(first)
        context.insert(second)
        try context.save()

        let proposals = try RealLibraryRemediator.previewIdentifierMetadataRepairs(in: context)
        #expect(proposals == [IdentifierMetadataRepairProposal(
            albumID: album.id,
            albumTitle: "Example Album",
            corruptValue: corruptValue,
            replacement: "Example Artist",
            trackFields: 2,
            albumFields: 1
        )])

        let report = try RealLibraryRemediator.applyIdentifierMetadataRepairs(
            in: context,
            expectedProposals: proposals
        )
        #expect(report.albumsUpdated == 1)
        #expect(report.tracksUpdated == 2)
        #expect(report.fieldsUpdated == 3)
        #expect(album.artist == "Example Artist")
        #expect(first.albumArtist == "Example Artist")
        #expect(second.albumArtist == "Example Artist")
        #expect(try RealLibraryRemediator.previewIdentifierMetadataRepairs(in: context).isEmpty)
    }

    @Test("Identifier metadata repair refuses ambiguous or partial evidence")
    @MainActor
    func refusesAmbiguousIdentifierMetadata() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let corruptValue = UUID().uuidString

        let mixedAlbum = Album(title: "Mixed", artist: corruptValue)
        let mixedFirst = Track(path: "/tmp/\(UUID().uuidString).m4a", artist: "Artist One", album: mixedAlbum.title)
        let mixedSecond = Track(path: "/tmp/\(UUID().uuidString).m4a", artist: "Artist Two", album: mixedAlbum.title)
        mixedFirst.albumArtist = corruptValue
        mixedSecond.albumArtist = corruptValue
        mixedFirst.albumRelation = mixedAlbum
        mixedSecond.albumRelation = mixedAlbum

        let partialAlbum = Album(title: "Partial", artist: corruptValue)
        let corruptTrack = Track(path: "/tmp/\(UUID().uuidString).m4a", artist: "Artist", album: partialAlbum.title)
        let validTrack = Track(path: "/tmp/\(UUID().uuidString).m4a", artist: "Artist", album: partialAlbum.title)
        corruptTrack.albumArtist = corruptValue
        validTrack.albumArtist = "Artist"
        corruptTrack.albumRelation = partialAlbum
        validTrack.albumRelation = partialAlbum

        for model in [mixedAlbum, partialAlbum] { context.insert(model) }
        for track in [mixedFirst, mixedSecond, corruptTrack, validTrack] { context.insert(track) }
        try context.save()

        #expect(try RealLibraryRemediator.previewIdentifierMetadataRepairs(in: context).isEmpty)
    }

    @Test("Delayed expired artwork leaves every album and track field unchanged")
    @MainActor
    func expiredDownloadIsTransactional() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let (album, track) = try makeDiscogsAlbum(in: context)
        let originalID = album.id
        let originalDate = album.dateAdded
        let clock = TestDiscogsClock()
        let candidate = makeCandidate(title: "Artist - Album")
        let client = RemediationClientFixture(candidate: candidate, download: { evidence in
            #expect(evidence == candidate.evidence)
            await Task.yield()
            clock.set(TestDiscogsClock.stamp(DiscogsFreshness.maximumAge))
            throw DiscogsError.resultsExpired
        })
        let cache = makeCache(clock: clock)
        var saves = 0
        var dependencies = DiscogsRemediationDependencies(client: client, cache: cache, clock: { clock.sample() })
        dependencies.save = { saves += 1; try $0.save() }
        let report = try await RealLibraryRemediator.applyDiscogsEvidence(in: context, dependencies: dependencies)
        #expect(report.failures == 1)
        #expect(report.genresFilled == 0)
        #expect(report.trackYearsFilled == 0)
        #expect(report.albumYearsFilled == 0)
        #expect(report.artworkFilled == 0)
        #expect(saves == 0)
        #expect(album.id == originalID && album.title == "Album" && album.artist == "Artist")
        #expect(album.dateAdded == originalDate && album.year == 0 && album.artworkData == nil)
        #expect(track.genre.isEmpty && track.year == 0 && track.trackNumber == 0 && track.trackTotal == 0)
        #expect(track.title == "One" && track.artist == "Artist" && track.album == "Album")
        #expect(track.albumRelation?.id == album.id)
        #expect(context.hasChanges == false)
    }

    @Test("Successful normalization cannot renew expired search evidence")
    @MainActor
    func normalizationExpiryIsTransactional() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let (album, track) = try makeDiscogsAlbum(in: context)
        let clock = TestDiscogsClock()
        let cache = makeCache(clock: clock)
        let candidate = makeCandidate(title: "Artist - Album")
        var dependencies = DiscogsRemediationDependencies(
            client: RemediationClientFixture(candidate: candidate), cache: cache, clock: { clock.sample() })
        var normalized = false
        dependencies.normalize = { data in
            #expect(album.year == 0 && track.year == 0 && track.genre.isEmpty && album.artworkData == nil)
            await Task.yield()
            normalized = true
            clock.set(TestDiscogsClock.stamp(DiscogsFreshness.maximumAge))
            return data
        }
        dependencies.save = { _ in Issue.record("Expired evidence must not reach save") }
        let report = try await RealLibraryRemediator.applyDiscogsEvidence(in: context, dependencies: dependencies)
        #expect(normalized)
        #expect(report.failures == 1)
        #expect(report.genresFilled == 0 && report.albumYearsFilled == 0 && report.trackYearsFilled == 0 && report.artworkFilled == 0)
        #expect(album.year == 0 && track.year == 0 && track.genre.isEmpty && album.artworkData == nil)
        #expect(context.hasChanges == false)
    }

    @Test("Final save failure rolls back Discogs fields and propagates the persistence error")
    @MainActor
    func finalSaveFailureRollsBack() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let (album, track) = try makeDiscogsAlbum(in: context)
        let clock = TestDiscogsClock()
        var dependencies = DiscogsRemediationDependencies(
            client: RemediationClientFixture(candidate: makeCandidate(title: "Artist - Album")),
            cache: makeCache(clock: clock), clock: { clock.sample() })
        dependencies.normalize = { $0 }
        var saves = 0
        dependencies.save = { _ in
            saves += 1
            #expect(album.year == 2026 && track.genre == "Electronic" && track.year == 2026)
            #expect(album.artworkData == Data([1, 2, 3]))
            throw RemediationFixtureError.saveFailed
        }
        do {
            _ = try await RealLibraryRemediator.applyDiscogsEvidence(in: context, dependencies: dependencies)
            Issue.record("Save failure must propagate")
        } catch RemediationFixtureError.saveFailed {} catch { throw error }
        #expect(saves == 1)
        #expect(album.year == 0)
        #expect(track.year == 0)
        #expect(track.genre.isEmpty)
        #expect(album.artworkData == nil)
        #expect(context.hasChanges == false)
        let persisted = try #require(ModelContext(container).fetch(FetchDescriptor<Album>()).first)
        #expect(persisted.year == 0 && persisted.artworkData == nil)
    }

    @Test("Cache envelope acquisitions survive download and normalization")
    @MainActor
    func cacheEnvelopeIsNotRenewed() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let (album, track) = try makeDiscogsAlbum(in: context)
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(DiscogsFreshness.maximumAge - 1)])
        let cache = makeCache(clock: clock)
        let candidate = makeCandidate(title: "Artist - Album", fetchedAt: TestDiscogsClock.stamp(100))
        let originalFetches = [TestDiscogsClock.stamp(), candidate.fetchedAt]
        #expect(await cache.store([candidate], for: .init(albumTitle: "Album", albumArtist: "Artist"), fetches: originalFetches))
        let client = RemediationClientFixture(candidate: candidate, download: { evidence in
            #expect(Set(evidence.fetches) == Set(originalFetches))
            return Data([1, 2, 3])
        })
        var dependencies = DiscogsRemediationDependencies(client: client, cache: cache, clock: { clock.sample() })
        dependencies.normalize = { data in
            clock.set(TestDiscogsClock.stamp(DiscogsFreshness.maximumAge))
            return data
        }
        dependencies.save = { _ in Issue.record("Old cache acquisition must guard save") }
        let report = try await RealLibraryRemediator.applyDiscogsEvidence(in: context, dependencies: dependencies)
        #expect(report.cacheHits == 1 && report.networkSearches == 0 && report.failures == 1)
        #expect(album.year == 0 && track.year == 0 && track.genre.isEmpty && album.artworkData == nil)
        #expect(context.hasChanges == false)
    }

    @Test("Expiry at the final save guard restores fields and stays typed")
    @MainActor
    func expiryImmediatelyBeforeSaveRollsBack() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let (album, track) = try makeDiscogsAlbum(in: context)
        let clock = TestDiscogsClock()
        let cache = makeCache(clock: clock)
        let candidate = makeCandidate(title: "Artist - Album")
        #expect(await cache.store([candidate], for: .init(albumTitle: "Album", albumArtist: "Artist"), fetches: [candidate.fetchedAt]))
        var dependencies = DiscogsRemediationDependencies(
            client: RemediationClientFixture(candidate: candidate), cache: cache,
            clock: { TestDiscogsClock.stamp(album.year == 0 ? 0 : DiscogsFreshness.maximumAge) })
        dependencies.save = { _ in Issue.record("Expired evidence must not reach final save") }
        do {
            _ = try await RealLibraryRemediator.applyDiscogsEvidence(in: context, allowNetwork: false, dependencies: dependencies)
            Issue.record("Final save expiry must stay typed")
        } catch DiscogsError.resultsExpired {} catch { throw error }
        #expect(album.year == 0 && track.year == 0 && track.genre.isEmpty && album.artworkData == nil)
        #expect(context.hasChanges == false)
    }

    @Test("Track-number batches keep original search acquisitions across throttling")
    @MainActor
    func trackNumbersRejectSearchExpiryDuringThrottle() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let (_, first) = try makeDiscogsAlbum(in: context, title: "Album A")
        let (_, second) = try makeDiscogsAlbum(in: context, title: "Album B")
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(DiscogsFreshness.maximumAge - 1)])
        let cache = makeCache(clock: clock)
        for title in ["Album A", "Album B"] {
            let candidate = makeCandidate(title: "Artist - " + title)
            #expect(await cache.store([candidate], for: .init(albumTitle: title, albumArtist: "Artist"), fetches: [candidate.fetchedAt]))
        }
        let calls = RemediationCallLog()
        let release = makeRelease(fetchedAt: TestDiscogsClock.stamp(DiscogsFreshness.maximumAge - 1))
        let client = RemediationClientFixture(candidate: makeCandidate(title: "Unused"), release: { id in
            await calls.record(id)
            return release
        })
        var dependencies = DiscogsRemediationDependencies(client: client, cache: cache, clock: { clock.sample() })
        var sleeps = 0
        dependencies.sleep = { _ in
            sleeps += 1
            clock.set(TestDiscogsClock.stamp(DiscogsFreshness.maximumAge))
        }
        let report = try await RealLibraryRemediator.applyDiscogsTrackNumbers(in: context, dependencies: dependencies)
        #expect(sleeps == 1)
        #expect(await calls.values() == [1])
        #expect(report.trackNumbersFilled == 1 && report.failures == 1)
        #expect(first.trackNumber == 1 && first.trackTotal == 1)
        #expect(second.trackNumber == 0 && second.trackTotal == 0)
        #expect(context.hasChanges == false)
    }

    @Test("Track numbers validate both original acquisitions after release await", arguments: ["search", "release"])
    @MainActor
    func trackNumbersRejectDelayedEvidence(expired: String) async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let (_, track) = try makeDiscogsAlbum(in: context)
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(100)])
        let cache = makeCache(clock: clock)
        let candidate = makeCandidate(title: "Artist - Album", fetchedAt: TestDiscogsClock.stamp(expired == "search" ? 0 : 100))
        #expect(await cache.store([candidate], for: .init(albumTitle: "Album", albumArtist: "Artist"), fetches: [candidate.fetchedAt]))
        let release = makeRelease(fetchedAt: TestDiscogsClock.stamp(expired == "release" ? 0 : 100))
        let client = RemediationClientFixture(candidate: candidate, release: { _ in
            await Task.yield()
            clock.set(TestDiscogsClock.stamp(DiscogsFreshness.maximumAge))
            return release
        })
        var dependencies = DiscogsRemediationDependencies(client: client, cache: cache, clock: { clock.sample() })
        dependencies.save = { _ in Issue.record("Expired tracklist cannot reach save") }
        let report = try await RealLibraryRemediator.applyDiscogsTrackNumbers(in: context, dependencies: dependencies)
        #expect(report.failures == 1 && report.trackNumbersFilled == 0)
        #expect(track.trackNumber == 0 && track.trackTotal == 0)
        #expect(context.hasChanges == false)
    }

    @Test("Tracklist commit failure restores every number and total", arguments: [false, true])
    @MainActor
    func trackNumberCommitFailureRollsBack(expireBeforeSave: Bool) async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let (_, track) = try makeDiscogsAlbum(in: context)
        let clock = TestDiscogsClock()
        let cache = makeCache(clock: clock)
        let candidate = makeCandidate(title: "Artist - Album")
        #expect(await cache.store([candidate], for: .init(albumTitle: "Album", albumArtist: "Artist"), fetches: [candidate.fetchedAt]))
        let release = makeRelease(fetchedAt: candidate.fetchedAt)
        let client = RemediationClientFixture(candidate: candidate, release: { _ in release })
        var dependencies = DiscogsRemediationDependencies(client: client, cache: cache, clock: {
            TestDiscogsClock.stamp(expireBeforeSave && track.trackNumber > 0 ? DiscogsFreshness.maximumAge : 0)
        })
        var saves = 0
        dependencies.save = { _ in
            saves += 1
            throw RemediationFixtureError.saveFailed
        }
        let report = try await RealLibraryRemediator.applyDiscogsTrackNumbers(in: context, dependencies: dependencies)
        #expect(report.failures == 1 && report.trackNumbersFilled == 0)
        #expect(saves == (expireBeforeSave ? 0 : 1))
        #expect(track.trackNumber == 0 && track.trackTotal == 0)
        #expect(context.hasChanges == false)
    }

    @Test("Delayed maintenance does not apply to replacement track identities", arguments: ["artwork", "trackNumbers"])
    @MainActor
    func replacementTargetsAreNotMutated(flow: String) async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let (album, track) = try makeDiscogsAlbum(in: context)
        let other = Album(title: "Other", artist: "Artist", year: 1984)
        context.insert(other)
        try context.save()
        let replacement = Track(path: "/tmp/" + UUID().uuidString + ".m4a", title: "One", artist: "Artist", album: "Album")
        // Even a reused public UUID is not the same persistent target.
        replacement.id = track.id
        let replace: @MainActor @Sendable () throws -> Void = {
            track.albumRelation = other
            replacement.albumRelation = album
            context.insert(replacement)
            try context.save()
        }
        let clock = TestDiscogsClock()
        let cache = makeCache(clock: clock)
        let candidate = makeCandidate(title: "Artist - Album")
        #expect(await cache.store([candidate], for: .init(albumTitle: "Album", albumArtist: "Artist"), fetches: [candidate.fetchedAt]))
        let release = makeRelease(fetchedAt: candidate.fetchedAt)
        let client = RemediationClientFixture(candidate: candidate, release: { _ in
            await Task.yield()
            try replace()
            return release
        })
        var dependencies = DiscogsRemediationDependencies(client: client, cache: cache, clock: { clock.sample() })
        dependencies.normalize = { data in
            await Task.yield()
            try replace()
            return data
        }
        dependencies.save = { _ in Issue.record("Replacement target must not be saved") }
        let report: DiscogsLibraryRemediationReport
        if flow == "artwork" {
            report = try await RealLibraryRemediator.applyDiscogsEvidence(in: context, dependencies: dependencies)
        } else {
            report = try await RealLibraryRemediator.applyDiscogsTrackNumbers(in: context, dependencies: dependencies)
        }
        #expect(report.failures == 1)
        #expect(replacement.trackNumber == 0 && replacement.trackTotal == 0 && replacement.genre.isEmpty && replacement.year == 0)
        #expect(track.trackNumber == 0 && track.genre.isEmpty && track.year == 0)
        #expect(album.artworkData == nil && album.year == 0 && other.year == 1984)
        #expect(context.hasChanges == false)
    }

    @Test("Artwork checks freshness before download and after successful bytes", arguments: ["unavailable", "expired", "download"])
    @MainActor
    func artworkAcquisitionBoundaries(boundary: String) async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let (album, track) = try makeDiscogsAlbum(in: context)
        let cacheClock = TestDiscogsClock()
        let cache = makeCache(clock: cacheClock)
        let candidate = makeCandidate(title: "Artist - Album")
        #expect(await cache.store([candidate], for: .init(albumTitle: "Album", albumArtist: "Artist"), fetches: [candidate.fetchedAt]))
        let clock = TestDiscogsClock([boundary == "unavailable" ? nil : TestDiscogsClock.stamp(boundary == "expired" ? DiscogsFreshness.maximumAge : 0)])
        let client = RemediationClientFixture(candidate: candidate, download: { _ in
            #expect(boundary == "download", "Unusable metadata must not start an image request")
            await Task.yield()
            clock.set(TestDiscogsClock.stamp(DiscogsFreshness.maximumAge))
            return Data([1, 2, 3])
        })
        var dependencies = DiscogsRemediationDependencies(client: client, cache: cache, clock: { clock.sample() })
        dependencies.normalize = { data in Issue.record("Expired bytes must not enter normalization"); return data }
        dependencies.save = { _ in Issue.record("Expired bytes must not reach save") }
        let report = try await RealLibraryRemediator.applyDiscogsEvidence(in: context, dependencies: dependencies)
        #expect(report.failures == 1 && report.artworkFilled == 0)
        #expect(album.year == 0 && track.year == 0 && track.genre.isEmpty && album.artworkData == nil)
        #expect(context.hasChanges == false)
    }

    @Test("Transient audit emits canonical source links and original freshness evidence")
    @MainActor
    func auditIncludesSourceAndFreshness() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = try makeDiscogsAlbum(in: context)
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(100)])
        let cache = makeCache(clock: clock)
        let candidate = makeCandidate(title: "Someone Else - Elsewhere")
        #expect(await cache.store([candidate], for: .init(albumTitle: "Album", albumArtist: "Artist"), fetches: [candidate.fetchedAt]))
        let dependencies = DiscogsRemediationDependencies(
            client: RemediationClientFixture(candidate: candidate), cache: cache, clock: { clock.sample() })
        let items = try await RealLibraryRemediator.auditDiscogsEvidence(in: context, dependencies: dependencies)
        let item = try #require(items.first)
        #expect(item.candidateTitles == [candidate.title])
        #expect(item.candidates.count == 1)
        guard let audit = item.candidates.first else { return }
        #expect(audit.sourcePageURL?.absoluteString == "https://www.discogs.com/release/1")
        #expect(audit.evidence == candidate.evidence)
        #expect(audit.checkedAt == TestDiscogsClock.stamp(100) && audit.isFresh)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        let details = try #require(json["candidates"] as? [[String: Any]])
        #expect(details.first?["sourcePageURL"] as? String == "https://www.discogs.com/release/1")
        #expect(details.first?["isFresh"] as? Bool == true)
        #expect(context.hasChanges == false)
    }

    @Test("Audit drops early results that expire while later cache lookups finish")
    @MainActor
    func auditRevalidatesCompletedBatch() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = try makeDiscogsAlbum(in: context, title: "Album A")
        _ = try makeDiscogsAlbum(in: context, title: "Album B")
        let cacheClock = TestDiscogsClock()
        let cache = makeCache(clock: cacheClock)
        let candidate = makeCandidate(title: "Someone Else - Elsewhere")
        for title in ["Album A", "Album B"] {
            #expect(await cache.store([candidate], for: .init(albumTitle: title, albumArtist: "Artist"), fetches: [candidate.fetchedAt]))
        }
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(), TestDiscogsClock.stamp(DiscogsFreshness.maximumAge)])
        let dependencies = DiscogsRemediationDependencies(
            client: RemediationClientFixture(candidate: candidate), cache: cache, clock: { clock.sample() })
        let items = try await RealLibraryRemediator.auditDiscogsEvidence(in: context, dependencies: dependencies)
        #expect(items.isEmpty)
        #expect(context.hasChanges == false)
    }

    @Test("Prepared maintenance rechecks freshness before the first assignment", arguments: ["artwork", "trackNumbers"])
    @MainActor
    func expiryBeforeAssignmentsDoesNotTouchModels(flow: String) async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let (album, track) = try makeDiscogsAlbum(in: context)
        let clock = TestDiscogsClock()
        let cache = makeCache(clock: clock)
        let candidate = makeCandidate(title: "Artist - Album")
        #expect(await cache.store([candidate], for: .init(albumTitle: "Album", albumArtist: "Artist"), fetches: [candidate.fetchedAt]))
        let release = makeRelease(fetchedAt: candidate.fetchedAt)
        let client = RemediationClientFixture(candidate: candidate, release: { _ in release })
        var samples = 0
        var dependencies = DiscogsRemediationDependencies(client: client, cache: cache, clock: {
            samples += 1
            if samples == 3 {
                #expect(context.hasChanges == false, "Expiry after preparation must precede assignments")
                #expect(album.year == 0 && track.trackNumber == 0 && track.genre.isEmpty)
            }
            return TestDiscogsClock.stamp(samples >= 3 ? DiscogsFreshness.maximumAge : 0)
        })
        dependencies.save = { _ in Issue.record("Expired prepared batch cannot save") }
        do {
            if flow == "artwork" {
                _ = try await RealLibraryRemediator.applyDiscogsEvidence(in: context, allowNetwork: false, dependencies: dependencies)
            } else {
                let report = try await RealLibraryRemediator.applyDiscogsTrackNumbers(in: context, dependencies: dependencies)
                #expect(report.trackNumbersFilled == 0 && report.failures == 1)
            }
        } catch DiscogsError.resultsExpired {} catch { throw error }
        #expect(samples == 3)
        #expect(context.hasChanges == false)
        #expect(album.year == 0 && track.year == 0 && track.genre.isEmpty && track.trackNumber == 0)
    }

    @Test("Release identity must match the selected search evidence")
    @MainActor
    func trackNumbersRejectMismatchedRelease() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let (_, track) = try makeDiscogsAlbum(in: context)
        let clock = TestDiscogsClock()
        let cache = makeCache(clock: clock)
        let candidate = makeCandidate(title: "Artist - Album")
        #expect(await cache.store([candidate], for: .init(albumTitle: "Album", albumArtist: "Artist"), fetches: [candidate.fetchedAt]))
        let release = makeRelease(fetchedAt: candidate.fetchedAt, id: 99)
        let client = RemediationClientFixture(candidate: candidate, release: { _ in release })
        var dependencies = DiscogsRemediationDependencies(client: client, cache: cache, clock: { clock.sample() })
        dependencies.save = { _ in Issue.record("Mismatched release cannot save") }
        let report = try await RealLibraryRemediator.applyDiscogsTrackNumbers(in: context, dependencies: dependencies)
        #expect(report.trackNumbersFilled == 0 && report.failures == 1)
        #expect(track.trackNumber == 0 && track.trackTotal == 0 && context.hasChanges == false)
    }

    @Test("Fresh acquisition uses real artwork normalization and preserves filled local values")
    @MainActor
    func freshEvidenceUsesRealNormalizationAndMissingOnlyUpdates() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let (album, first) = try makeDiscogsAlbum(in: context)
        album.year = 1984
        first.year = 1985
        first.genre = "Local Genre"
        let second = Track(path: "/tmp/" + UUID().uuidString + ".m4a", title: "Two", artist: "Artist", album: "Album")
        second.albumRelation = album
        context.insert(second)
        try context.save()
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(.red, atX: x, y: y) } }
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let candidate = makeCandidate(title: "Artist - Album")
        let client = RemediationClientFixture(candidate: candidate, download: { _ in png })
        let clock = TestDiscogsClock()
        let cache = makeCache(clock: clock)
        let dependencies = DiscogsRemediationDependencies(client: client, cache: cache, clock: { clock.sample() })
        let report = try await RealLibraryRemediator.applyDiscogsEvidence(in: context, dependencies: dependencies)
        #expect(report.networkSearches == 1 && report.failures == 0)
        #expect(report.artworkFilled == 1 && report.genresFilled == 1 && report.trackYearsFilled == 1 && report.albumYearsFilled == 0)
        #expect(album.year == 1984 && first.year == 1985 && first.genre == "Local Genre")
        #expect(second.year == 2026 && second.genre == "Electronic")
        #expect(ArtworkStorage.pixelSize(of: try #require(album.artworkData)) != nil)
        #expect(context.hasChanges == false)
        let savedContext = ModelContext(container)
        let saved = try #require(savedContext.fetch(FetchDescriptor<Album>()).first)
        #expect(saved.year == 1984 && saved.artworkData == album.artworkData)
        let hit = try #require(await cache.candidates(for: .init(albumTitle: "Album", albumArtist: "Artist")))
        #expect(hit.fetches == [candidate.fetchedAt] && hit.value == [candidate])
    }

    @Test("Transport and invalid-image failures cannot leave partial album changes", arguments: [false, true])
    @MainActor
    func imageFailureLeavesFieldsUnchanged(transportFailure: Bool) async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let (album, track) = try makeDiscogsAlbum(in: context)
        let clock = TestDiscogsClock()
        let client = RemediationClientFixture(candidate: makeCandidate(title: "Artist - Album"), download: { _ in
            if transportFailure { throw DiscogsError.imageDownloadFailed }
            return Data("not an image".utf8)
        })
        let dependencies = DiscogsRemediationDependencies(client: client, cache: makeCache(clock: clock), clock: { clock.sample() })
        let report = try await RealLibraryRemediator.applyDiscogsEvidence(in: context, dependencies: dependencies)
        #expect(report.failures == 1 && report.artworkFilled == 0 && report.genresFilled == 0 && report.albumYearsFilled == 0 && report.trackYearsFilled == 0)
        #expect(album.year == 0 && album.artworkData == nil && track.genre.isEmpty && track.year == 0)
        #expect(context.hasChanges == false)
    }

    @Test("Fresh cache-only metadata applies without image or network access")
    @MainActor
    func cacheOnlyMetadataRetainsAcquisition() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let (album, track) = try makeDiscogsAlbum(in: context)
        let clock = TestDiscogsClock()
        let cache = makeCache(clock: clock)
        let candidate = makeCandidate(title: "Artist - Album")
        #expect(await cache.store([candidate], for: .init(albumTitle: "Album", albumArtist: "Artist"), fetches: [candidate.fetchedAt]))
        let client = RemediationClientFixture(candidate: candidate, download: { _ in
            Issue.record("Cache-only cannot download"); throw DiscogsError.imageDownloadFailed
        })
        let dependencies = DiscogsRemediationDependencies(client: client, cache: cache, clock: { clock.sample() })
        let report = try await RealLibraryRemediator.applyDiscogsEvidence(in: context, allowNetwork: false, dependencies: dependencies)
        #expect(report.cacheHits == 1 && report.networkSearches == 0 && report.failures == 0)
        #expect(album.year == 2026 && track.year == 2026 && track.genre == "Electronic" && album.artworkData == nil)
        #expect(context.hasChanges == false)
    }

    @Test("Audit emission revalidation removes stale titles and unavailable clocks")
    @MainActor
    func auditEmissionRevalidatesOriginalAcquisitions() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = try makeDiscogsAlbum(in: context)
        let clock = TestDiscogsClock()
        let cache = makeCache(clock: clock)
        let candidate = makeCandidate(title: "Someone Else - Elsewhere")
        #expect(await cache.store([candidate], for: .init(albumTitle: "Album", albumArtist: "Artist"), fetches: [candidate.fetchedAt]))
        let dependencies = DiscogsRemediationDependencies(client: RemediationClientFixture(candidate: candidate), cache: cache, clock: { clock.sample() })
        let items = try await RealLibraryRemediator.auditDiscogsEvidence(in: context, dependencies: dependencies)
        let item = try #require(items.first)
        let fresh = try #require(item.revalidated(at: TestDiscogsClock.stamp(100)))
        #expect(fresh.candidates.first?.evidence == candidate.evidence)
        #expect(fresh.candidates.first?.checkedAt == TestDiscogsClock.stamp(100))
        #expect(item.revalidated(at: TestDiscogsClock.stamp(DiscogsFreshness.maximumAge)) == nil)
        #expect(item.revalidated(at: nil) == nil)
        #expect(item.revalidated(at: TestDiscogsClock.stamp(-1)) == nil)
        #expect(item.revalidated(at: TestDiscogsClock.stamp(1, boot: "other-boot")) == nil)
    }

    private func makeRelease(fetchedAt: DiscogsFetchStamp, id: Int = 1) -> DiscogsReleaseMetadata {
        DiscogsReleaseMetadata(id: id, title: "Album", artist: "Artist", year: 2026,
                               country: nil, formats: [], tracks: [.init(number: 1, title: "One", duration: nil)],
                               artworkURL: nil, fetchedAt: fetchedAt)
    }

    @MainActor
    private func makeDiscogsAlbum(in context: ModelContext, title: String = "Album") throws -> (Album, Track) {
        let album = Album(title: title, artist: "Artist")
        let track = Track(path: "/tmp/" + UUID().uuidString + ".m4a", title: "One", artist: "Artist", album: title)
        track.albumRelation = album
        context.insert(album)
        context.insert(track)
        try context.save()
        return (album, track)
    }

    private func makeCache(clock: TestDiscogsClock) -> DiscogsArtworkSearchCache {
        let directory = ProcessInfo.processInfo.environment["SONGBIRD_UI_TEST_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        return DiscogsArtworkSearchCache(fileURL: directory
            .appendingPathComponent("remediation-cache-" + UUID().uuidString + ".json"), clock: { clock.sample() })
    }

    private func makeCandidate(title: String, fetchedAt: DiscogsFetchStamp = TestDiscogsClock.stamp()) -> DiscogsArtworkCandidate {
        DiscogsArtworkCandidate(
            id: 1,
            title: title,
            artist: "",
            year: 2026,
            country: nil,
            formats: ["Album"],
            genres: ["Electronic"],
            styles: [],
            thumbnailURL: nil,
            imageURL: URL(string: "https://example.com/image.jpg")!,
            sourcePageURL: URL(string: "https://example.com/release")!,
            fetchedAt: fetchedAt
        )
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

private actor RemediationCallLog {
    private var ids: [Int] = []
    func record(_ id: Int) { ids.append(id) }
    func values() -> [Int] { ids }
}

private enum RemediationFixtureError: Error { case saveFailed }

private struct RemediationClientFixture: DiscogsRemediationClient {
    let candidate: DiscogsArtworkCandidate
    var download: @Sendable (DiscogsContentEvidence) async throws -> Data = { _ in Data([1, 2, 3]) }
    var release: @MainActor @Sendable (Int) async throws -> DiscogsReleaseMetadata = { _ in throw DiscogsError.noResults }

    func search(_ query: DiscogsArtworkSearchQuery, page: Int) async throws -> DiscogsSearchPage {
        DiscogsSearchPage(candidates: [candidate], page: page, totalPages: 1, fetchedAt: candidate.fetchedAt)
    }

    func downloadImage(from url: URL, evidence: DiscogsContentEvidence) async throws -> Data {
        try await download(evidence)
    }

    func releaseMetadata(id: Int) async throws -> DiscogsReleaseMetadata {
        try await release(id)
    }
}
