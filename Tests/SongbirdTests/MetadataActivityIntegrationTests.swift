import Foundation
import SwiftData
import Testing
@testable import SongbirdLib

private actor MetadataWriterProbe {
    private(set) var calls: [[TrackMetadataField: TrackMetadataValue]] = []
    let failsSecondFile: Bool

    init(failsSecondFile: Bool = false) { self.failsSecondFile = failsSecondFile }

    func write(path: String, fields: [TrackMetadataField: TrackMetadataValue]) throws {
        calls.append(fields)
        if failsSecondFile && path.hasSuffix("02.flac") {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                userInfo: [NSLocalizedDescriptionKey: "PRIVATE_PROVIDER_RESPONSE /Private/Fixture token=secret"])
        }
    }
}

@Suite("Metadata destination and activity", .serialized)
@MainActor
struct MetadataActivityIntegrationTests {
    @Test("Favorite and Rating edits never invoke the file writer")
    func catalogOnlyFields() async throws {
        let probe = MetadataWriterProbe()
        let fixture = try await Fixture(probe: probe)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let outcome = try await fixture.actions.applyTrackMetadata(
            TrackMetadataChangeSet(baselines: fixture.baselines,
                edits: [.rating: .number(4), .favorite: .flag(true)]),
            writePolicy: .catalogAndFileTags)
        #expect(outcome == .saved(trackCount: 2))
        #expect(await probe.calls.isEmpty)
        let record = try #require(fixture.activity.records.first { $0.kind == .metadataEdit })
        #expect(record.status == .succeeded)
        #expect(record.counts?.catalogSaved == 2)
        #expect(record.counts?.filesAttempted == 0)
        #expect(!fixture.activity.records.contains { $0.kind == .fileTagWrite })
        await fixture.activity.flush()
    }

    @Test("Explicit catalog destination wins without changing saved catalog values")
    func catalogDestination() async throws {
        let probe = MetadataWriterProbe()
        let fixture = try await Fixture(probe: probe)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        _ = try await fixture.actions.applyTrackMetadata(
            TrackMetadataChangeSet(baselines: fixture.baselines, edits: [.title: .text("Edited")]),
            writePolicy: .catalogOnly)
        #expect(await probe.calls.isEmpty)
        let records = try ModelContext(fixture.container).fetch(FetchDescriptor<Track>())
        #expect(records.allSatisfy { $0.title == "Edited" })
        await fixture.activity.flush()
    }

    @Test("Partial tag failure preserves catalog success and saves filename-only result details")
    func partialFileFailure() async throws {
        let probe = MetadataWriterProbe(failsSecondFile: true)
        let fixture = try await Fixture(probe: probe)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let previousNoticeIDs = Set(LibraryStatus.shared.activity.records.map(\.id))
        let outcome = try await fixture.actions.applyTrackMetadata(
            TrackMetadataChangeSet(baselines: fixture.baselines,
                edits: [.title: .text("Edited"), .rating: .number(5)]),
            writePolicy: .catalogAndFileTags)
        #expect(outcome == .saved(trackCount: 2))
        let calls = await probe.calls
        #expect(calls.count == 2)
        #expect(calls.allSatisfy { $0[.title] == .text("Edited") && $0[.rating] == nil })
        let record = try #require(fixture.activity.records.first { $0.kind == .metadataEdit })
        #expect(record.status == .completedWithWarnings)
        #expect(record.counts == LibraryActivityCounts(catalogSaved: 2, filesAttempted: 2, filesSaved: 1, filesFailed: 1))
        #expect(record.failures == [LibraryActivityFailure(fileName: "02.flac", category: .permissionDenied)])
        #expect(!LibraryStatus.shared.activity.records.contains { notice in
            !previousNoticeIDs.contains(notice.id) && notice.kind == .notice &&
            LibraryStatus.shared.activity.liveMessages[notice.id]?.hasPrefix("Could not write tags to /Private/Fixture/02.flac:") == true
        })
        await fixture.activity.flush()
        let persisted = try String(contentsOf: fixture.historyURL, encoding: .utf8)
        #expect(persisted.contains("02.flac"))
        #expect(!persisted.contains("/Private/Fixture"))
        #expect(!persisted.contains("PRIVATE_PROVIDER_RESPONSE"))
        #expect(!persisted.contains("token=secret"))
    }

    @Test("Automatic catalog checks stay quiet and paired explicit file checks record once")
    func healthActivityScope() async throws {
        let probe = MetadataWriterProbe()
        let fixture = try await Fixture(probe: probe, includeTracks: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let health = LibraryHealthProjectionStore(snapshots: fixture.snapshots,
            activity: fixture.activity, configuredSearchRoots: { [] })
        health.check(category: .missingGenre)
        for _ in 0..<300 {
            if case .ready = health.state(for: .missingGenre) { break }
            await Task.yield()
        }
        #expect(fixture.activity.records.isEmpty)
        health.check(category: .missingFiles)
        for _ in 0..<300 {
            if case .ready = health.state(for: .missingFiles) { break }
            await Task.yield()
        }
        let records = fixture.activity.records.filter { $0.kind == .healthCheck }
        #expect(records.count == 1)
        #expect(records.first?.status == .succeeded)
        guard case .ready = health.state(for: .unavailableVolumes) else {
            Issue.record("Paired availability result did not finish")
            return
        }
        await fixture.activity.flush()
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let historyURL: URL
        let container: ModelContainer
        let snapshots: LibrarySnapshotStore
        let activity: LibraryActivityStore
        let actions: LibraryItemActionHandler
        let baselines: [TrackMetadataBaseline]

        init(probe: MetadataWriterProbe, includeTracks: Bool = true) async throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("songbird-metadata-activity-\(UUID().uuidString)")
            historyURL = root.appendingPathComponent("activity-history.json")
            activity = LibraryActivityStore(storage: LibraryActivityStorage(url: historyURL))
            await activity.load()
            let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self, AlbumFavorite.self, TrackFavorite.self])
            container = try ModelContainer(for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            let tracks = includeTracks ? (1...2).map { index in
                Track(path: "/Private/Fixture/0\(index).flac", title: "Song \(index)", artist: "Artist", album: "Album")
            } : []
            for track in tracks { container.mainContext.insert(track) }
            try container.mainContext.save()
            baselines = tracks.map { track in
                TrackMetadataBaseline(trackID: track.id,
                    values: [.title: .text(track.title), .rating: .number(0), .favorite: .flag(false)])
            }
            snapshots = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
            await snapshots.refresh()
            actions = LibraryItemActionHandler(modelContainer: container,
                playbackSession: PlaybackSession(backend: MetadataActivityBackend()),
                librarySnapshots: snapshots, navigation: LibraryNavigationCoordinator(restoresPersistedState: false),
                metadataTagWriter: { path, fields, _, _ in try await probe.write(path: path, fields: fields) },
                activity: activity, revealFiles: { _ in })
        }
    }
}

@MainActor
private final class MetadataActivityBackend: PlayerBackend {
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var isPaused = false
    var volume: Double = 1
    var onTrackBegan: ((AudioSource?) -> Void)?
    var onTrackFinished: (() -> Void)?
    var onError: ((String) -> Void)?
    func prepare() throws {}
    func shutdown() {}
    func play(_ source: AudioSource, durationHint: TimeInterval) throws {}
    func pause() {}
    func resume() {}
    func stop() {}
    func seek(to time: TimeInterval) {}
    func setNextSource(_ source: AudioSource?, crossfadeDuration: TimeInterval) {}
}
