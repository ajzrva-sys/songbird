import Foundation
import Testing
@testable import SongbirdLib

@Suite("Audio CD sector playback and metadata")
struct AudioCDFeatureTests {
    @Test("Transient CD tracks retain their metadata artwork location")
    func transientArtworkLocation() {
        let discID = DiscIdentifier("artwork-disc")
        let source = AudioCDSource(
            discID: discID,
            deviceID: "mock-drive",
            trackNumber: 1,
            startSector: 0,
            endSector: 75
        )
        let discTrack = AudioDiscTrack(
            discID: discID,
            number: 1,
            title: "Track",
            duration: 1,
            startSector: 0,
            endSector: 75,
            source: source
        )
        let artworkURL = URL(string: "https://example.test/cover.jpg")!

        let track = Track.transientAudioCDTrack(
            discTrack,
            album: "Album",
            artworkURL: artworkURL
        )

        #expect(track.audioCDArtworkURL == artworkURL)
    }

    @Test("MusicBrainz disc ID uses the standard 99-offset digest")
    func discIDVector() {
        let id = MusicBrainzDiscID.calculate(
            entries: [
                .init(number: 1, startSector: 150),
                .init(number: 2, startSector: 4_650),
            ],
            leadOutSector: 9_150
        )
        #expect(id == "x6C2sps8jxMg2bu8HODV.4uV7G4-")
    }

    @Test("CD-Text title and performer packs are decoded")
    func cdTextParsing() {
        var data = Data(repeating: 0, count: 4)
        data.append(cdTextPack(type: 0x80, track: 0, text: "Album"))
        data.append(cdTextPack(type: 0x81, track: 0, text: "Artist"))
        data.append(cdTextPack(type: 0x80, track: 1, text: "Opening"))

        let text = AudioCDTextParser.parse(data)
        #expect(text.albumTitle == "Album")
        #expect(text.albumArtist == "Artist")
        #expect(text.trackTitles[1] == "Opening")
    }

    @Test("macOS little-endian CDDA stereo samples reach the PCM ring buffer")
    func cddaConversion() throws {
        let discID = DiscIdentifier("test-disc")
        let source = AudioCDSource(
            discID: discID,
            deviceID: "mock-drive",
            trackNumber: 1,
            startSector: 0,
            endSector: 1
        )
        let reader = try AudioCDReader(
            source: source,
            sampleRate: 44_100,
            sectorReader: ConstantSectorReader(left: 16_384, right: -16_384)
        )
        try reader.prime(minimumFrames: 588)

        var left: Float = 0
        var right: Float = 0
        #expect(reader.ringBuffer.readStereoFrame(left: &left, right: &right))
        #expect(abs(left - 0.5) < 0.0001)
        #expect(abs(right + 0.5) < 0.0001)
        #expect(reader.state == .idle || reader.state == .eof)
    }

    @Test("CDDA sample-rate conversion remains continuous across sector reads")
    func cddaResamplingContinuity() throws {
        let source = AudioCDSource(
            discID: DiscIdentifier("resample-disc"),
            deviceID: "mock-drive",
            trackNumber: 1,
            startSector: 0,
            endSector: 160
        )
        let reader = try AudioCDReader(
            source: source,
            sampleRate: 48_000,
            bufferSeconds: 4,
            sectorReader: SineSectorReader()
        )
        try reader.prime(minimumFrames: Int(reader.totalOutputFrames))

        var previous: Float?
        var maximumJump: Float = 0
        var frames = 0
        var left: Float = 0
        var right: Float = 0
        while reader.ringBuffer.readStereoFrame(left: &left, right: &right) {
            if let previous { maximumJump = max(maximumJump, abs(left - previous)) }
            previous = left
            frames += 1
        }
        #expect(abs(frames - Int(reader.totalOutputFrames)) < 200)
        #expect(maximumJump < 0.25)
    }

    @Test("Cancelling an in-flight optical read does not block the caller")
    func cddaCancellationIsNonblocking() throws {
        let readStarted = DispatchSemaphore(value: 0)
        let source = AudioCDSource(
            discID: DiscIdentifier("slow-disc"),
            deviceID: "slow-drive",
            trackNumber: 1,
            startSector: 0,
            endSector: 150
        )
        let reader = try AudioCDReader(
            source: source,
            sampleRate: 44_100,
            sectorReader: SlowSectorReader(started: readStarted)
        )
        reader.start()
        #expect(readStarted.wait(timeout: .now() + 1) == .success)

        let started = ContinuousClock.now
        reader.stop()
        let elapsed = started.duration(to: .now)
        #expect(elapsed < .milliseconds(50))
    }

    @Test("MusicBrainz candidates prefer exact official releases")
    func metadataRanking() async throws {
        let json = """
        {"releases":[
          {"id":"loose","title":"Loose","status":"Bootleg","artist-credit":[{"name":"Band"}],"media":[{"tracks":[{"position":1,"title":"One"}]}]},
          {"id":"exact","title":"Exact","status":"Official","country":"US","date":"2020","artist-credit":[{"name":"Band"}],"media":[{"tracks":[{"position":1,"title":"One"},{"position":2,"recording":{"title":"Two"}}]}]}
        ]}
        """
        let response = HTTPURLResponse(
            url: URL(string: "https://musicbrainz.org")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-cd-test-\(UUID().uuidString)")
        let client = MusicBrainzCDMetadataClient(
            contactURL: URL(string: "https://example.test/songbird"),
            http: MockMusicBrainzHTTP(data: Data(json.utf8), response: response),
            cache: AudioCDMetadataCache(directory: temp)
        )
        let candidates = try await client.candidates(discID: "disc", trackCount: 2)
        let first = try #require(candidates.first)
        #expect(first.id == "exact")
        #expect(first.tracks.map(\.title) == ["One", "Two"])
        try? FileManager.default.removeItem(at: temp)
    }

    @Test("MusicBrainz identifies Songbird with a configured contact email")
    func metadataEmailUserAgent() async throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://musicbrainz.org")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-cd-agent-test-\(UUID().uuidString)")
        let client = MusicBrainzCDMetadataClient(
            contact: "ajzrva@gmail.com",
            http: UserAgentCheckingHTTP(
                expected: "Songbird/0.1 (ajzrva@gmail.com)",
                data: Data(#"{"releases":[]}"#.utf8),
                response: response
            ),
            cache: AudioCDMetadataCache(directory: temp)
        )

        _ = try await client.candidates(discID: "disc", trackCount: 1)
        try? FileManager.default.removeItem(at: temp)
    }

    @Test("MusicBrainz empty results are cached across disc reinsertion")
    func metadataNegativeCaching() async throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://musicbrainz.org")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let http = CountingMusicBrainzHTTP(
            data: Data(#"{"releases":[]}"#.utf8),
            response: response
        )
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-cd-negative-cache-test-\(UUID().uuidString)")
        let client = MusicBrainzCDMetadataClient(
            contact: "ajzrva@gmail.com",
            http: http,
            cache: AudioCDMetadataCache(directory: temp)
        )

        #expect(try await client.candidates(discID: "missing-disc", trackCount: 1).isEmpty)
        #expect(try await client.candidates(discID: "missing-disc", trackCount: 1).isEmpty)
        #expect(await http.requestCount() == 1)
        try? FileManager.default.removeItem(at: temp)
    }

    @Test("Discogs fallback caches release matches by disc ID")
    func discogsFallbackCaching() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-discogs-cd-test-\(UUID().uuidString)")
        let imageURL = URL(string: "https://example.test/cover.jpg")!
        let client = MockDiscogsCDClient(
            searchPage: DiscogsSearchPage(
                candidates: [DiscogsArtworkCandidate(
                    id: 42,
                    title: "Artist - Album",
                    artist: "Artist",
                    year: 2001,
                    country: "US",
                    formats: ["CD"],
                    genres: ["Rock"],
                    styles: ["Alternative Rock"],
                    thumbnailURL: imageURL,
                    imageURL: imageURL,
                    sourcePageURL: URL(string: "https://discogs.com/release/42")!,
                    fetchedAt: TestDiscogsClock.stamp()
                )],
                page: 1,
                totalPages: 1,
                fetchedAt: TestDiscogsClock.stamp()
            ),
            release: DiscogsReleaseMetadata(
                id: 42,
                title: "Album",
                artist: "Artist",
                year: 2001,
                country: "US",
                formats: ["CD"],
                tracks: [
                    .init(number: 1, title: "First", duration: 180),
                    .init(number: 2, title: "Second", duration: 200),
                ],
                artworkURL: imageURL,
                fetchedAt: TestDiscogsClock.stamp()
            )
        )
        let provider = DiscogsAudioCDMetadataProvider(
            client: client,
            searchCache: DiscogsArtworkSearchCache(
                fileURL: temp.appendingPathComponent("search.json"),
                clock: { TestDiscogsClock.stamp() }
            ),
            metadataCache: AudioCDMetadataCache(
                directory: temp.appendingPathComponent("metadata"),
                clock: { TestDiscogsClock.stamp() }
            ),
            clock: { TestDiscogsClock.stamp() }
        )
        let query = AudioCDMetadataQuery(
            discID: "discogs-disc",
            albumTitle: "Album",
            albumArtist: "Artist",
            tracks: [
                .init(number: 1, duration: 181),
                .init(number: 2, duration: 199),
            ]
        )

        let first = try await provider.candidates(for: query)
        let second = try await provider.candidates(for: query)
        #expect(first == second)
        #expect(first.first?.id == "discogs:42")
        #expect(first.first?.tracks.map(\.title) == ["First", "Second"])
        #expect(await client.requestCounts() == [1, 1])
        try? FileManager.default.removeItem(at: temp)
    }

    @Test("Discogs fallback is skipped without usable CD-Text")
    func discogsFallbackRequiresCDText() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-discogs-empty-test-\(UUID().uuidString)")
        let client = MockDiscogsCDClient(searchPage: .init(candidates: [], page: 1, totalPages: 1, fetchedAt: TestDiscogsClock.stamp()))
        let provider = DiscogsAudioCDMetadataProvider(
            client: client,
            searchCache: DiscogsArtworkSearchCache(
                fileURL: temp.appendingPathComponent("search.json"),
                clock: { TestDiscogsClock.stamp() }
            ),
            metadataCache: AudioCDMetadataCache(
                directory: temp.appendingPathComponent("metadata"),
                clock: { TestDiscogsClock.stamp() }
            ),
            clock: { TestDiscogsClock.stamp() }
        )
        let query = AudioCDMetadataQuery(
            discID: "unknown-disc",
            albumTitle: "Audio CD",
            albumArtist: "Unknown Artist",
            tracks: [.init(number: 1, duration: 180)]
        )

        #expect(try await provider.candidates(for: query).isEmpty)
        #expect(try await provider.candidates(for: query).isEmpty)
        #expect(await client.requestCounts() == [0, 0])
        try? FileManager.default.removeItem(at: temp)
    }

    @Test("Provider must not return an expired release merely because cache refused storage")
    func expiredProviderPublication() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(18_000)])
        let stale = TestDiscogsClock.stamp()
        let image = URL(string: "https://example.test/cover.png")!
        let client = MockDiscogsCDClient(
            searchPage: .init(candidates: [.init(
                id: 42, title: "Artist - Album", artist: "Artist", year: nil, country: nil,
                formats: ["CD"], genres: [], styles: [], thumbnailURL: nil, imageURL: image,
                sourcePageURL: URL(string: "https://www.discogs.com/release/42")!, fetchedAt: stale
            )], page: 1, totalPages: 1, fetchedAt: stale),
            release: .init(id: 42, title: "Album", artist: "Artist", year: nil, country: nil,
                formats: ["CD"], tracks: [], artworkURL: image, fetchedAt: stale)
        )
        let provider = DiscogsAudioCDMetadataProvider(
            client: client,
            searchCache: .init(fileURL: directory.appendingPathComponent("search.json"), clock: { clock.sample() }),
            metadataCache: .init(directory: directory, clock: { clock.sample() }),
            clock: { clock.sample() }
        )
        do {
            let returned = try await provider.candidates(for: .init(discID: "disc", albumTitle: "Album", tracks: []))
            #expect(returned.isEmpty, "Expired provider content must not be published")
        } catch DiscogsError.resultsExpired {
            // Typed expiry is recoverable by a deliberate refresh.
        }
    }

    private func cdTextPack(type: UInt8, track: UInt8, text: String) -> Data {
        var bytes = [UInt8](repeating: 0, count: 18)
        bytes[0] = type
        bytes[1] = track
        for (offset, byte) in text.utf8.prefix(12).enumerated() { bytes[4 + offset] = byte }
        return Data(bytes)
    }
}

@MainActor
@Suite("Audio CD queue lifecycle")
struct AudioCDQueueLifecycleTests {
    @Test("Reordering Up Next replaces the backend's preloaded next track")
    func reorderedQueueRefreshesPreload() async throws {
        // Given
        let queue = PlaybackQueue()
        let current = makeTrack(disc: "current", number: 1)
        let first = makeTrack(disc: "first", number: 1)
        let second = makeTrack(disc: "second", number: 1)
        let third = makeTrack(disc: "third", number: 1)
        queue.setStateForTesting(
            current: current,
            upcoming: [first, second, third],
            history: []
        )
        let backend = RecordingBackend()
        let engine = PlaybackEngine(queue: queue, backend: backend)
        _ = engine.play(current)
        let thirdEntry = try #require(
            queue.upcomingEntries.first(where: { $0.track === third })
        )

        // When
        #expect(queue.moveUpcoming(entryID: thirdEntry.id, offset: -2))
        await Task.yield()
        await Task.yield()

        // Then
        #expect(queue.peekNext() === third)
        #expect(backend.nextSource == third.audioCDSource.map(AudioSource.audioCD))
    }

    @Test("Explicit Play restarts a stopped current track and is idempotent while playing")
    func explicitPlayIsStateAware() {
        // Given
        let queue = PlaybackQueue()
        let backend = RecordingBackend()
        let engine = PlaybackEngine(queue: queue, backend: backend)
        let track = makeTrack(disc: "current", number: 1)
        queue.setStateForTesting(current: track, upcoming: [], history: [])
        engine.stop()

        // When
        engine.playIfPossible()
        engine.playIfPossible()

        // Then
        #expect(backend.playCount == 1)
        #expect(backend.isPlaying)
        #expect(engine.status == .playing)
        #expect(queue.currentTrack === track)
    }

    @Test("Play from a stopped state starts the next queued track")
    func stoppedPlayStartsQueue() {
        let queue = PlaybackQueue()
        let backend = RecordingBackend()
        let engine = PlaybackEngine(queue: queue, backend: backend)
        let track = makeTrack(disc: "queued", number: 1)
        queue.enqueue([track])

        engine.togglePlayPause()

        #expect(queue.currentTrack === track)
        #expect(backend.isPlaying)
        #expect(engine.status == .playing)
    }

    @Test("Removing one disc preserves another disc's queue and playback")
    func discScopedRemoval() {
        let queue = PlaybackQueue()
        let backend = RecordingBackend()
        let engine = PlaybackEngine(queue: queue, backend: backend)
        let first = makeTrack(disc: "first", number: 1)
        let second = makeTrack(disc: "second", number: 1)
        queue.setStateForTesting(
            current: second,
            upcoming: [first, second],
            history: [first, second]
        )

        engine.removeAudioCDTracks(for: [DiscIdentifier("first")], reportRemoval: true)

        #expect(queue.currentTrack === second)
        #expect(queue.upcomingTracks == [second])
        #expect(queue.history == [second])
        #expect(backend.stopCount == 0)
    }

    @Test("Ejecting the playing disc releases its stream immediately")
    func ejectReleasesPlayingDiscImmediately() {
        let queue = PlaybackQueue()
        let backend = RecordingBackend()
        let engine = PlaybackEngine(queue: queue, backend: backend)
        let track = makeTrack(disc: "playing", number: 1)
        queue.setStateForTesting(current: track, upcoming: [], history: [])

        engine.removeAudioCDTracks(for: [DiscIdentifier("playing")], reportRemoval: false)

        #expect(queue.currentTrack == nil)
        #expect(backend.immediateStopCount == 1)
        #expect(backend.stopCount == 0)
    }

    private func makeTrack(disc: String, number: Int) -> Track {
        let id = DiscIdentifier(disc)
        let source = AudioCDSource(
            discID: id,
            deviceID: "drive-\(disc)",
            trackNumber: number,
            startSector: 0,
            endSector: 75
        )
        let track = Track(path: "songbird-cd://\(disc)/\(number)", title: "Track")
        track.audioCDSource = source
        return track
    }
}

private struct ConstantSectorReader: AudioCDSectorReading {
    let left: Int16
    let right: Int16

    func readSectors(deviceID: String, firstSector: Int64, count: Int) throws -> Data {
        var data = Data(capacity: count * 2_352)
        for _ in 0..<(count * 588) {
            data.append(UInt8(truncatingIfNeeded: UInt16(bitPattern: left)))
            data.append(UInt8(truncatingIfNeeded: UInt16(bitPattern: left) >> 8))
            data.append(UInt8(truncatingIfNeeded: UInt16(bitPattern: right)))
            data.append(UInt8(truncatingIfNeeded: UInt16(bitPattern: right) >> 8))
        }
        return data
    }
}

private struct SineSectorReader: AudioCDSectorReading {
    func readSectors(deviceID: String, firstSector: Int64, count: Int) throws -> Data {
        var data = Data(capacity: count * 2_352)
        let firstFrame = Int(firstSector) * 588
        for frame in 0..<(count * 588) {
            let phase = 2 * Double.pi * 1_000 * Double(firstFrame + frame) / 44_100
            let value = Int16(sin(phase) * 16_000)
            let bits = UInt16(bitPattern: value)
            for _ in 0..<2 {
                data.append(UInt8(truncatingIfNeeded: bits))
                data.append(UInt8(truncatingIfNeeded: bits >> 8))
            }
        }
        return data
    }
}

private struct SlowSectorReader: AudioCDSectorReading {
    let started: DispatchSemaphore

    func readSectors(deviceID: String, firstSector: Int64, count: Int) throws -> Data {
        started.signal()
        Thread.sleep(forTimeInterval: 0.25)
        return try ConstantSectorReader(left: 0, right: 0)
            .readSectors(deviceID: deviceID, firstSector: firstSector, count: count)
    }
}

private struct MockMusicBrainzHTTP: MusicBrainzHTTPClient {
    let data: Data
    let response: HTTPURLResponse

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (data, response)
    }
}

private struct UserAgentCheckingHTTP: MusicBrainzHTTPClient {
    let expected: String
    let data: Data
    let response: HTTPURLResponse

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.value(forHTTPHeaderField: "User-Agent") == expected else {
            throw MusicBrainzError.invalidResponse
        }
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        guard components?.queryItems?.first(where: { $0.name == "inc" })?.value
                == "recordings+artist-credits" else {
            throw MusicBrainzError.invalidResponse
        }
        return (data, response)
    }
}

private actor CountingMusicBrainzHTTP: MusicBrainzHTTPClient {
    let data: Data
    let response: HTTPURLResponse
    private var count = 0

    init(data: Data, response: HTTPURLResponse) {
        self.data = data
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        count += 1
        return (data, response)
    }

    func requestCount() -> Int { count }
}

private actor MockDiscogsCDClient: DiscogsCDSearching {
    let searchPage: DiscogsSearchPage
    let release: DiscogsReleaseMetadata?
    private var searchRequests = 0
    private var releaseRequests = 0

    init(searchPage: DiscogsSearchPage, release: DiscogsReleaseMetadata? = nil) {
        self.searchPage = searchPage
        self.release = release
    }

    func search(_ query: DiscogsArtworkSearchQuery, page: Int) async throws -> DiscogsSearchPage {
        searchRequests += 1
        return searchPage
    }

    func releaseMetadata(id: Int) async throws -> DiscogsReleaseMetadata {
        releaseRequests += 1
        guard let release else { throw DiscogsError.noResults }
        return release
    }

    func requestCounts() -> [Int] { [searchRequests, releaseRequests] }
}

@MainActor
private final class RecordingBackend: PlayerBackend {
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var isPaused = false
    var volume: Double = 1
    var onTrackBegan: ((AudioSource?) -> Void)?
    var onTrackFinished: (() -> Void)?
    var onError: ((String) -> Void)?
    var stopCount = 0
    var immediateStopCount = 0
    var playCount = 0
    var nextSource: AudioSource?

    func prepare() throws {}
    func shutdown() {}
    func play(_ source: AudioSource, durationHint: TimeInterval) throws {
        playCount += 1
        isPlaying = true
    }
    func pause() { isPaused = true }
    func resume() { isPaused = false }
    func stop() { stopCount += 1; isPlaying = false }
    func stopImmediately() { immediateStopCount += 1; isPlaying = false }
    func seek(to time: TimeInterval) { position = time }
    func setNextSource(_ source: AudioSource?, crossfadeDuration: TimeInterval) {
        nextSource = source
    }
}
