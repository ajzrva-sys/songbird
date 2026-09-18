import Foundation
import SwiftData
import Testing
@testable import SongbirdLib

@Suite("Album-wide artwork edits", .serialized)
@MainActor
struct AlbumArtworkScopeTests {
    @Test("Editing one song updates its complete displayed album, not sibling titles")
    func oneTrackUpdatesAlbumPartitions() async throws {
        let fixture = try await Fixture(paths: [
            "/Fixture/Collection/01.flac", "/Fixture/Collection/02.flac",
            "/OtherEdition/Collection/01.flac",
        ])
        let changes = try TrackMetadataChangeSet(
            baselines: [fixture.baseline(0)],
            edits: [.title: .text("Edited selected title"), .artwork: .artwork(Self.image)]
        )
        let fullRebuilds = fixture.snapshots.fullRebuildCount
        _ = try await fixture.actions.applyTrackMetadata(changes)
        #expect(fixture.snapshots.fullRebuildCount == fullRebuilds)
        let tracks = try fixture.readTracks()
        #expect(tracks[fixture.ids[0]]?.resolvedArtworkData == Self.image)
        #expect(tracks[fixture.ids[1]]?.resolvedArtworkData == Self.image)
        #expect(tracks[fixture.ids[1]]?.title == "Song 1")
        #expect(tracks[fixture.ids[2]]?.resolvedArtworkData == nil)
        #expect(tracks[fixture.ids[2]]?.title == "Song 2")
    }

    @Test("Numbered discs share artwork while a separate edition stays untouched")
    func numberedDiscs() async throws {
        let fixture = try await Fixture(paths: [
            "/Fixture/Collection/CD 1/01.flac", "/Fixture/Collection/CD 2/01.flac",
            "/OtherEdition/Collection/01.flac",
        ])
        _ = try await fixture.actions.applyTrackMetadata(TrackMetadataChangeSet(
            baselines: [fixture.baseline(0)], edits: [.artwork: .artwork(Self.image)]
        ))
        let tracks = try fixture.readTracks()
        #expect(tracks[fixture.ids[1]]?.resolvedArtworkData == Self.image)
        #expect(tracks[fixture.ids[2]]?.resolvedArtworkData == nil)
    }

    @Test("Clearing one song's artwork clears the complete album")
    func clearAlbumArtwork() async throws {
        let fixture = try await Fixture(paths: ["/Fixture/Collection/01.flac", "/Fixture/Collection/02.flac"])
        _ = try await fixture.actions.applyTrackMetadata(TrackMetadataChangeSet(
            baselines: [fixture.baseline(0)], edits: [.artwork: .artwork(Self.image)]
        ))
        _ = try await fixture.actions.applyTrackMetadata(TrackMetadataChangeSet(
            baselines: [fixture.baseline(0)], edits: [.artwork: .artwork(nil)]
        ))
        #expect(try fixture.readTracks().values.allSatisfy { $0.resolvedArtworkData == nil })
    }

    @Test("Unlinked songs are linked within their album when artwork is added")
    func unlinkedAlbum() async throws {
        let fixture = try await Fixture(paths: [
            "/Fixture/Collection/01.flac", "/Fixture/Collection/02.flac",
        ], linked: false)
        _ = try await fixture.actions.applyTrackMetadata(TrackMetadataChangeSet(
            baselines: [fixture.baseline(0)], edits: [.artwork: .artwork(Self.image)]
        ))
        let tracks = try fixture.readTracks()
        #expect(tracks.values.allSatisfy { $0.resolvedArtworkData == Self.image })
        #expect(Set(tracks.values.compactMap { $0.albumRelation?.id }).count == 1)
    }

    @Test("Unknown albums with different performers are not merged by folder")
    func unknownAlbumBoundaries() async throws {
        let fixture = try await Fixture(paths: ["/Fixture/Music/01.flac", "/Fixture/Music/02.flac"],
                                        title: "Unknown Album", albumArtist: nil)
        _ = try await fixture.actions.applyTrackMetadata(TrackMetadataChangeSet(
            baselines: [fixture.baseline(0)], edits: [.artwork: .artwork(Self.image)]
        ))
        #expect(try fixture.readTracks()[fixture.ids[1]]?.resolvedArtworkData == nil)
    }

    @Test("A sibling artwork conflict blocks all changes and Keep Current preserves the group")
    func siblingConflictAndWriteReceipt() async throws {
        let fixture = try await Fixture(paths: ["/Fixture/Collection/01.flac", "/Fixture/Collection/02.flac"])
        let scope = try await fixture.actions.prepareTrackArtworkScope(trackIDs: [fixture.ids[0]])
        let baseline = try fixture.baseline(0)
        let context = ModelContext(fixture.container)
        let siblingID = fixture.ids[1]
        let sibling = try #require(context.fetch(FetchDescriptor<Track>(
            predicate: #Predicate { $0.id == siblingID }
        )).first)
        sibling.albumRelation?.artworkData = Self.image
        try context.save()
        let changes = TrackMetadataChangeSet(
            baselines: [baseline], edits: [.title: .text("Selected only"), .artwork: .artwork(nil)],
            artworkScope: scope
        )
        let service = TrackMetadataMutationService(modelContainer: fixture.container)
        let blocked = try await service.applyWithReceipt(changes, decisions: [])
        guard case .conflicts(let conflicts) = blocked.outcome else {
            Issue.record("Expected sibling artwork conflict")
            return
        }
        #expect(blocked.fileWrites.isEmpty)
        #expect(try fixture.readTracks()[fixture.ids[0]]?.title == "Song 0")
        #expect(conflicts.map(\.trackID) == [siblingID])
        let saved = try await service.applyWithReceipt(changes, decisions: [
            TrackMetadataConflictDecision(trackID: siblingID, field: .artwork,
                expectedCurrent: .artwork(Self.image), resolution: .useCurrent),
        ])
        #expect(saved.fileWrites.count == 1)
        #expect(saved.fileWrites.first?.fields == [.title: .text("Selected only")])
        #expect(try fixture.readTracks()[siblingID]?.resolvedArtworkData == Self.image)
    }

    @Test("Album scope rejects a moved sibling before changing selected metadata")
    func movedSiblingIsAtomic() async throws {
        let fixture = try await Fixture(paths: ["/Fixture/Collection/01.flac", "/Fixture/Collection/02.flac"])
        let scope = try await fixture.actions.prepareTrackArtworkScope(trackIDs: [fixture.ids[0]])
        let context = ModelContext(fixture.container)
        let siblingID = fixture.ids[1]
        let sibling = try #require(context.fetch(FetchDescriptor<Track>(predicate: #Predicate { $0.id == siblingID })).first)
        sibling.album = "Other Album"
        try context.save()
        let changes = try TrackMetadataChangeSet(
            baselines: [fixture.baseline(0)],
            edits: [.title: .text("Do not apply"), .artwork: .artwork(Self.image)], artworkScope: scope
        )
        let service = TrackMetadataMutationService(modelContainer: fixture.container)
        await #expect(throws: TrackMetadataMutationError.artworkScopeChanged) {
            _ = try await service.apply(changes, decisions: [])
        }
        #expect(try fixture.readTracks()[fixture.ids[0]]?.title == "Song 0")
    }

    @Test("Track-origin Discogs search expands to the same full album scope")
    func discogsTargetScope() async throws {
        let fixture = try await Fixture(paths: [
            "/Fixture/Collection/01.flac", "/Fixture/Collection/02.flac", "/Other/Collection/01.flac",
        ])
        let tracks = try fixture.readTracks()
        let first = try #require(tracks[fixture.ids[0]]?.albumRelation?.id)
        let second = try #require(tracks[fixture.ids[1]]?.albumRelation?.id)
        let scope = try await fixture.actions.canonicalArtworkAlbumIDs(containing: [first])
        #expect(Set(scope) == [first, second])
    }

    static let image = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    @MainActor
    struct Fixture {
        let container: ModelContainer
        let snapshots: LibrarySnapshotStore
        let actions: LibraryItemActionHandler
        let ids: [UUID]

        init(paths: [String], title: String = "Collection", linked: Bool = true,
             albumArtist: String? = "Various Artists") async throws {
            let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
            container = try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true),
            ])
            let context = container.mainContext
            context.autosaveEnabled = false
            var tracks: [Track] = []
            for (index, path) in paths.enumerated() {
                let track = Track(path: path, title: "Song \(index)", artist: "Performer \(index)", album: title)
                track.albumArtist = albumArtist ?? track.artist
                if linked {
                    let album = Album(title: title, artist: "Various Artists")
                    context.insert(album)
                    track.albumRelation = album
                }
                context.insert(track)
                tracks.append(track)
            }
            try context.save()
            ids = tracks.map(\.id)
            snapshots = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
            await snapshots.refresh()
            actions = LibraryItemActionHandler(
                modelContainer: container,
                playbackSession: PlaybackSession(backend: ArtworkTestBackend()),
                librarySnapshots: snapshots,
                navigation: LibraryNavigationCoordinator(restoresPersistedState: false),
                revealFiles: { _ in }
            )
        }

        func baseline(_ index: Int) throws -> TrackMetadataBaseline {
            let track = try #require(readTracks()[ids[index]])
            return TrackMetadataBaseline(trackID: track.id, values: [
                .title: .text(track.title), .artwork: .artwork(track.resolvedArtworkData),
                .album: .text(track.album), .albumArtist: .text(track.albumArtist),
            ])
        }

        func readTracks() throws -> [UUID: Track] {
            let context = ModelContext(container)
            return Dictionary(uniqueKeysWithValues:
                try context.fetch(FetchDescriptor<Track>()).map { ($0.id, $0) }
            )
        }
    }
}

@MainActor
private final class ArtworkTestBackend: PlayerBackend {
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
