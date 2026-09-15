import Foundation
import CoreGraphics
import SwiftData
import Testing
@testable import SongbirdLib

@Suite("Discogs transient model contracts")
@MainActor
struct DiscogsTransientPresentationTests {
    @Test("Canned Discogs UI requires signed disposable identity and matching isolated root")
    func fixtureIsolation() {
        let info: [String: Any] = ["SongbirdUITesting": true, "SongbirdUITestRoot": "/private/tmp/songbird-fixture"]
        #expect(DiscogsUsabilityFixture.eligible(bundleIdentifier: "com.songbird.player.usability.test",
            info: info, environment: [:]))
        #expect(!DiscogsUsabilityFixture.eligible(bundleIdentifier: "com.songbird.player",
            info: info, environment: [:]))
        #expect(!DiscogsUsabilityFixture.eligible(bundleIdentifier: "com.songbird.player.usability.test",
            info: [:], environment: ["SONGBIRD_UI_TESTING": "1", "SONGBIRD_UI_TEST_ROOT": "/private/tmp/songbird-fixture"]))
        #expect(!DiscogsUsabilityFixture.eligible(bundleIdentifier: "com.songbird.player.usability.test",
            info: info, environment: ["SONGBIRD_UI_TEST_ROOT": "/private/tmp/different"]))
        #expect(!DiscogsUsabilityFixture.eligible(bundleIdentifier: "com.songbird.player.usability.test",
            info: ["SongbirdUITesting": true, "SongbirdUITestRoot": "/"], environment: [:]))
    }

    @Test("System Now Playing always uses original CD text and excludes transient Discogs art")
    func conservativeSystemMetadata() {
        let track = Track(path: "fixture", title: "Remote", artist: "Remote", album: "Remote")
        let original = AudioCDTrackMetadata(title: "Original", artist: "CD Artist", album: "CD Album")
        track.audioCDOriginalMetadata = original
        track.audioCDDiscogsEvidence = .init(releaseID: 42, fetches: [TestDiscogsClock.stamp()])
        track.audioCDArtworkURL = URL(string: "https://example.test/art")
        #expect(NowPlayingCommandCenter.metadata(for: track) == original)
        #expect(NowPlayingCommandCenter.artworkReference(for: track) == nil)
        track.audioCDDiscogsEvidence = nil
        #expect(NowPlayingCommandCenter.metadata(for: track).title == "Remote")
        #expect(NowPlayingCommandCenter.artworkReference(for: track) == .remote(track.audioCDArtworkURL!))
    }

    @Test("Loaded transient images clear at expiry and reject a late publication; local images remain")
    func loadedArtworkExpiry() throws {
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let reference = ArtworkReference.discogsRemote(URL(string: "https://example.test/art")!,
            evidence: .init(releaseID: 42, fetches: [TestDiscogsClock.stamp()]))
        var loaded = ArtworkThumbnailLoadState()
        let generation = loaded.generation
        loaded.publish(image, generation: generation)
        loaded.expire(reference: reference, at: TestDiscogsClock.stamp(18_001))
        #expect(loaded.image == nil)
        loaded.publish(image, generation: generation)
        #expect(loaded.image == nil)
        loaded.publish(image, generation: loaded.generation)
        loaded.expire(reference: .missingAlbumArtwork, at: nil)
        #expect(loaded.image != nil)
    }

    @Test("Runtime CD evidence and fallback are absent after a fixture store round-trip")
    func runtimeFieldsAreNotPersistentColumns() throws {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self, AlbumFavorite.self, TrackFavorite.self])
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let track = Track(path: "/fixture/owned-track.wav", title: "Saved user title", artist: "Saved Artist", album: "Saved Album")
        let id = track.id
        track.audioCDDiscogsEvidence = .init(releaseID: 42, fetches: [TestDiscogsClock.stamp()])
        track.audioCDOriginalMetadata = .init(title: "Runtime", artist: "Runtime", album: "Runtime")
        writer.insert(track)
        try writer.save()
        let reader = ModelContext(container)
        let reloaded = try #require(reader.fetch(FetchDescriptor<Track>()).first)
        #expect(reloaded.id == id)
        #expect(reloaded.title == "Saved user title")
        #expect(reloaded.artist == "Saved Artist")
        #expect(reloaded.album == "Saved Album")
        #expect(reloaded.audioCDDiscogsEvidence == nil)
        #expect(reloaded.audioCDOriginalMetadata == nil)
        #expect(reloaded.audioCDSource == nil)
    }

    @Test("A remote constructor missing original strings fails closed to CD defaults")
    func missingOriginalUsesDefaults() {
        let id = DiscIdentifier("defaults")
        let source = AudioCDSource(discID: id, deviceID: "fixture-no-device", trackNumber: 2,
            startSector: 0, endSector: 75)
        let cdTrack = AudioDiscTrack(discID: id, number: 2, title: "Remote", artist: "Remote",
            duration: 1, startSector: 0, endSector: 75, source: source)
        let evidence = DiscogsContentEvidence(releaseID: 42, fetches: [TestDiscogsClock.stamp()])
        let disc = AudioDisc(id: id, title: "Remote", volumeURL: URL(fileURLWithPath: "/fixture"),
            tracks: [cdTrack], discogsEvidence: evidence)
        #expect(disc.restoringOriginalMetadata().title == "Audio CD")
        #expect(disc.restoringOriginalMetadata().tracks.first?.title == "Track 02")
        let track = Track.transientAudioCDTrack(cdTrack, album: "Remote", discogsEvidence: evidence)
        #expect(track.audioCDMetadata(at: nil) == .defaultMetadata(trackNumber: 2))
        #expect(track.audioCDSource == source)
    }

    @Test("Artwork resolution keys by explicit provider evidence, not the image hostname")
    func providerAwareReferenceContract() {
        let url = URL(string: "https://arbitrary-cdn.test/cover.png")!
        let track = Track(path: "fixture", title: "Unchanged")
        track.audioCDArtworkURL = url
        let evidence = DiscogsContentEvidence(releaseID: 42, fetches: [TestDiscogsClock.stamp()])
        track.audioCDDiscogsEvidence = evidence
        #expect(ArtworkReference.resolved(for: track) == .discogsRemote(url, evidence: evidence))
        track.audioCDDiscogsEvidence = nil
        #expect(ArtworkReference.resolved(for: track) == .remote(url))
        track.audioCDArtworkURL = URL(string: "https://img.discogs.com/ordinary.png")!
        #expect(ArtworkReference.resolved(for: track) == .remote(track.audioCDArtworkURL!))
    }

    @Test("Copied CD track retains evidence and original strings without changing queue identity")
    func copiedTrackFallbackContract() throws {
        let id = DiscIdentifier("fixture-disc")
        let source = AudioCDSource(discID: id, deviceID: "fixture-no-device", trackNumber: 1,
            startSector: 150, endSector: 9_150)
        let cdTrack = AudioDiscTrack(discID: id, number: 1, title: "Remote Track", artist: "Remote Artist",
            duration: 120, startSector: 150, endSector: 9_150, source: source)
        let evidence = DiscogsContentEvidence(releaseID: 42, fetches: [TestDiscogsClock.stamp()])
        let original = AudioCDTrackMetadata(title: "CD-Text Track", artist: "CD-Text Artist", album: "CD-Text Album")
        let track = Track.transientAudioCDTrack(cdTrack, album: "Remote Album",
            artworkURL: URL(string: "https://not-a-discogs-host.test/image.png"),
            discogsEvidence: evidence, originalMetadata: original)
        let queue = PlaybackQueue()
        queue.setStateForTesting(current: track, upcoming: [track, track], history: [track])
        let occurrences = queue.upcomingEntries.map(\.id)
        let trackID = track.id
        #expect(track.audioCDDiscogsEvidence == evidence)
        #expect(track.audioCDOriginalMetadata == original)
        #expect(track.audioCDMetadata(at: TestDiscogsClock.stamp()).title == "Remote Track")
        #expect(track.audioCDMetadata(at: TestDiscogsClock.stamp(18_000)) == original)
        #expect(track.audioCDMetadata(at: nil) == original)
        #expect(track.id == trackID)
        #expect(track.audioCDSource == source)
        #expect(track.duration == 120)
        #expect(queue.currentTrack === track)
        #expect(queue.upcomingEntries.map(\.id) == occurrences)
        #expect(queue.history.first === track)
        #expect(track.title == "Remote Track", "Presentation values must not mutate stored fields or Undo")
    }
}
