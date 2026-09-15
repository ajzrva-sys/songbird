import AppKit
import Foundation
import Testing
@testable import SongbirdLib

@Suite("Optical disc metadata ownership")
@MainActor
struct OpticalDiscMetadataFreshnessTests {
    @Test("Expired selection cannot replace original CD-Text")
    func expiredSelectionIsRejected() async throws {
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(18_000)])
        let access = FixtureDiscAccess([Self.descriptor])
        let service = OpticalDiscService(access: access, ejector: FixtureDiscEjector(),
            metadataProvider: FixtureCDMetadata([]), startsObserving: false, clock: { clock.sample() })
        await service.refresh()
        let original = try #require(service.discs.first)
        service.setImporting(true, discID: original.id)
        service.selectMetadata(Self.candidate(), for: original.id)
        #expect(service.discs.first?.title == "CD-Text Album")
        #expect(service.discs.first?.tracks == original.tracks)
        #expect(service.discs.first?.status == .importing)
    }

    @Test("Owned metadata expires without a CD view and restores CD-Text while importing")
    func ownedMetadataRestoresFallback() async throws {
        let clock = TestDiscogsClock()
        let service = OpticalDiscService(access: FixtureDiscAccess([Self.descriptor]),
            ejector: FixtureDiscEjector(), metadataProvider: FixtureCDMetadata([Self.candidate()]),
            startsObserving: false, clock: { clock.sample() })
        await service.refresh()
        let loaded = try #require(service.discs.first)
        #expect(loaded.title == "Remote Album")
        service.setImporting(true, discID: loaded.id)
        clock.set(TestDiscogsClock.stamp(18_000))
        service.revalidateMetadata()
        let expired = try #require(service.discs.first)
        #expect(expired.title == "CD-Text Album")
        #expect(expired.albumArtist == "CD-Text Artist")
        #expect(expired.tracks.first?.title == "CD-Text Track")
        #expect(expired.artworkURL == nil)
        #expect(expired.year == nil)
        #expect(expired.id == loaded.id)
        #expect(expired.volumeURL == loaded.volumeURL)
        #expect(expired.tracks.map(\.source) == loaded.tracks.map(\.source))
        #expect(expired.tracks.map(\.id) == loaded.tracks.map(\.id))
        #expect(expired.status == .importing)
        #expect(service.metadataCandidates[expired.id] == nil)
    }

    @Test("Empty refresh and removal clear previously loaded candidate arrays")
    func refreshClearsCandidates() async throws {
        let access = FixtureDiscAccess([Self.descriptor])
        let metadata = FixtureCDMetadata([Self.candidate()])
        let service = OpticalDiscService(access: access, ejector: FixtureDiscEjector(),
            metadataProvider: metadata, startsObserving: false, clock: { TestDiscogsClock.stamp() })
        await service.refresh()
        #expect(service.metadataCandidates.count == 1)
        await metadata.set([])
        await service.refresh()
        #expect(service.metadataCandidates.isEmpty)
        #expect(service.discs.first?.title == "CD-Text Album")
        await metadata.set([Self.candidate()])
        await service.refresh()
        await access.set([])
        await service.refresh()
        #expect(service.discs.isEmpty)
        #expect(service.metadataCandidates.isEmpty)
    }

    @Test("A delayed old metadata generation cannot resurrect a removed disc's candidates")
    func lateMetadataAfterRemovalIsIgnored() async throws {
        let access = FixtureDiscAccess([Self.descriptor])
        let metadata = ControlledCDMetadata()
        let service = OpticalDiscService(access: access, ejector: FixtureDiscEjector(),
            metadataProvider: metadata, startsObserving: false, clock: { TestDiscogsClock.stamp() })
        let old = Task { await service.refresh() }
        for _ in 0..<200 {
            if await metadata.count == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await metadata.count == 1)
        await access.set([])
        await service.refresh()
        await metadata.complete(0, with: [Self.candidate()])
        await old.value
        #expect(service.discs.isEmpty)
        #expect(service.metadataCandidates.isEmpty)
        #expect(!service.isRefreshing)
        #expect(service.lastError == nil)
    }

    @Test("Service-owned timer restores metadata while no view exists")
    func timerOwnsExpiry() async throws {
        let clock = TestDiscogsClock()
        let service = OpticalDiscService(access: FixtureDiscAccess([Self.descriptor]),
            ejector: FixtureDiscEjector(), metadataProvider: FixtureCDMetadata([Self.candidate()]),
            startsObserving: false, clock: { clock.sample() }, expirySleep: { _ in
                clock.set(TestDiscogsClock.stamp(18_000))
                try await Task.sleep(for: .milliseconds(1))
            })
        await service.refresh()
        for _ in 0..<200 {
            if service.discs.first?.title == "CD-Text Album" { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(service.discs.first?.title == "CD-Text Album")
        #expect(service.metadataCandidates.isEmpty)
    }

    @Test("Wake and application activation revalidate owned metadata immediately")
    func lifecycleOwnsExpiry() async throws {
        for notification in [NSWorkspace.didWakeNotification, NSApplication.didBecomeActiveNotification] {
            let clock = TestDiscogsClock()
            let center = NotificationCenter()
            let service = OpticalDiscService(access: FixtureDiscAccess([Self.descriptor]),
                ejector: FixtureDiscEjector(), metadataProvider: FixtureCDMetadata([Self.candidate()]),
                startsObserving: false, clock: { clock.sample() },
                workspaceNotifications: center, applicationNotifications: center)
            await service.refresh()
            #expect(service.discs.first?.title == "Remote Album")
            clock.set(nil)
            center.post(name: notification, object: nil)
            for _ in 0..<200 {
                if service.discs.first?.title == "CD-Text Album" { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(service.discs.first?.title == "CD-Text Album")
            #expect(service.metadataCandidates.isEmpty)
        }
    }

    @Test("Disabled observation does not discover physical media or perform metadata lookup")
    func startsObservingFalseIsInert() async throws {
        let access = FixtureDiscAccess([Self.descriptor])
        let service = OpticalDiscService(access: access, ejector: FixtureDiscEjector(),
            metadataProvider: FixtureCDMetadata([]), startsObserving: false)
        try await Task.sleep(for: .milliseconds(180))
        #expect(await access.count == 0)
        #expect(service.discs.isEmpty)
        #expect(!service.isRefreshing)
    }

    @Test("Stale discovery cannot overwrite a newer generation or its refresh status")
    func staleDiscoveryIsIgnored() async throws {
        let access = ControlledDiscDiscovery()
        let service = OpticalDiscService(access: access, ejector: FixtureDiscEjector(),
            metadataProvider: FixtureCDMetadata([]), startsObserving: false)
        let first = Task { await service.refresh() }
        for _ in 0..<200 {
            if await access.count == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let second = Task { await service.refresh() }
        for _ in 0..<200 {
            if await access.count == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await access.count == 2)
        await access.complete(0, with: [Self.descriptor])
        await first.value
        #expect(service.isRefreshing, "Old defer must not end the newer refresh")
        #expect(service.discs.isEmpty)
        await access.complete(1, with: [])
        await second.value
        #expect(!service.isRefreshing)
        #expect(service.discs.isEmpty)
    }

    @Test("Delayed provider results are filtered before service publication")
    func delayedProviderExpiry() async throws {
        let clock = TestDiscogsClock()
        let metadata = ControlledCDMetadata()
        let service = OpticalDiscService(access: FixtureDiscAccess([Self.descriptor]), ejector: FixtureDiscEjector(),
            metadataProvider: metadata, startsObserving: false, clock: { clock.sample() })
        let refresh = Task { await service.refresh() }
        for _ in 0..<200 {
            if await metadata.count == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await metadata.count == 1)
        clock.set(TestDiscogsClock.stamp(18_000))
        await metadata.complete(0, with: [Self.candidate()])
        await refresh.value
        #expect(service.discs.first?.title == "CD-Text Album")
        #expect(service.metadataCandidates.isEmpty)
    }

    @Test("Clock rollback and boot change restore defaults but leave MusicBrainz usable")
    func invalidClockPreservesOrdinaryProvider() async throws {
        for now in [TestDiscogsClock.stamp(-1), TestDiscogsClock.stamp(1, boot: "another-boot")] {
            let clock = TestDiscogsClock()
            let ordinary = AudioCDMetadataCandidate(id: "musicbrainz:fixture", title: "Ordinary", artist: "Artist",
                country: nil, date: nil, tracks: [], artworkURL: URL(string: "https://fixture.test/ordinary.png"), score: 1)
            let service = OpticalDiscService(access: FixtureDiscAccess([Self.descriptor]), ejector: FixtureDiscEjector(),
                metadataProvider: FixtureCDMetadata([Self.candidate(), ordinary]), startsObserving: false,
                clock: { clock.sample() })
            await service.refresh()
            clock.set(now)
            service.revalidateMetadata()
            #expect(service.discs.first?.title == "CD-Text Album")
            #expect(service.metadataCandidates.values.first == [ordinary])
            service.selectMetadata(ordinary, for: try #require(service.discs.first?.id))
            #expect(service.discs.first?.title == "Ordinary")
            #expect(service.discs.first?.discogsEvidence == nil)
            #expect(service.discs.first?.artworkURL == ordinary.artworkURL)
        }
    }

    @Test("Switching away from Discogs cannot launder unfilled remote track titles into ordinary metadata")
    func switchingProviderUsesOriginalTrackFallback() async throws {
        let service = OpticalDiscService(access: FixtureDiscAccess([Self.descriptor]), ejector: FixtureDiscEjector(),
            metadataProvider: FixtureCDMetadata([Self.candidate()]), startsObserving: false,
            clock: { TestDiscogsClock.stamp() })
        await service.refresh()
        let loaded = try #require(service.discs.first)
        #expect(loaded.tracks.first?.title == "Remote Track")
        let ordinary = AudioCDMetadataCandidate(id: "musicbrainz:partial", title: "Ordinary Album", artist: "Ordinary Artist",
            country: nil, date: nil, tracks: [], artworkURL: nil, score: 1)
        service.selectMetadata(ordinary, for: loaded.id)
        #expect(service.discs.first?.title == "Ordinary Album")
        #expect(service.discs.first?.tracks.first?.title == "CD-Text Track")
        #expect(service.discs.first?.discogsEvidence == nil)
        #expect(service.discs.first?.tracks.map(\.source) == loaded.tracks.map(\.source))
    }

    static var descriptor: OpticalDiscDescriptor {
        .init(deviceID: "fixture-no-device", registryID: 1,
            entries: [.init(number: 1, startSector: 150)], leadOutSector: 9_150,
            cdText: .init(albumTitle: "CD-Text Album", albumArtist: "CD-Text Artist",
                trackTitles: [1: "CD-Text Track"], trackArtists: [:]))
    }
    static func candidate(stamp: DiscogsFetchStamp = TestDiscogsClock.stamp()) -> AudioCDMetadataCandidate {
        .init(id: "discogs:42", title: "Remote Album", artist: "Remote Artist", country: "US", date: "2001",
            tracks: [.init(number: 1, title: "Remote Track", artist: "Remote Artist")],
            artworkURL: URL(string: "https://example.test/cover.png"), score: 100,
            discogsEvidence: .init(releaseID: 42, fetches: [stamp]))
    }
}

actor FixtureDiscAccess: OpticalDiscAccessing {
    private var values: [OpticalDiscDescriptor]
    private(set) var count = 0
    init(_ values: [OpticalDiscDescriptor]) { self.values = values }
    func set(_ values: [OpticalDiscDescriptor]) { self.values = values }
    func discover() async throws -> [OpticalDiscDescriptor] { count += 1; return values }
}
struct FixtureDiscEjector: OpticalDiscEjecting {
    func eject(deviceID: String) async throws {}
}
actor FixtureCDMetadata: AudioCDMetadataProviding {
    private var values: [AudioCDMetadataCandidate]
    init(_ values: [AudioCDMetadataCandidate]) { self.values = values }
    func set(_ values: [AudioCDMetadataCandidate]) { self.values = values }
    func candidates(for query: AudioCDMetadataQuery) async throws -> [AudioCDMetadataCandidate] { values }
}
