import Foundation
import SwiftData
import Testing
@testable import SongbirdLib

@Suite("Track metadata mutation service", .serialized)
struct TrackMetadataMutationServiceTests {
    @Test("Conflicts perform no writes, then explicit choices apply only selected fields")
    @MainActor
    func conflictIsAtomicAndChoicesAreScoped() async throws {
        let container = try makeContainer()
        let track = try insertTrack(in: container)
        let service = TrackMetadataMutationService(modelContainer: container)
        let changeSet = TrackMetadataChangeSet(
            baselines: [baseline(for: track, favorite: false)],
            edits: [.title: .text("Mine"), .rating: .number(4), .favorite: .flag(true)]
        )

        track.title = "Elsewhere"
        try container.mainContext.save()
        let first = try await service.apply(changeSet, decisions: [])
        guard case .conflicts(let conflicts) = first else {
            Issue.record("Expected a conflict")
            return
        }
        let unchanged = try fetchTrack(track.id, from: container)
        #expect(unchanged.title == "Elsewhere")
        #expect(unchanged.rating == 0)
        #expect(try favoriteIDs(in: container).isEmpty)

        let titleConflict = try #require(conflicts.first { $0.field == .title })
        let second = try await service.apply(changeSet, decisions: [
            TrackMetadataConflictDecision(
                trackID: track.id,
                field: .title,
                expectedCurrent: titleConflict.current,
                resolution: .useCurrent
            ),
        ])
        #expect(second == .saved(trackCount: 1))
        let applied = try fetchTrack(track.id, from: container)
        #expect(applied.title == "Elsewhere")
        #expect(applied.rating == 4)
        #expect(try favoriteIDs(in: container) == [track.id])
    }

    @Test("A stale conflict decision returns refreshed conflicts without mutation")
    @MainActor
    func staleDecisionRefreshesConflict() async throws {
        let container = try makeContainer()
        let track = try insertTrack(in: container)
        let service = TrackMetadataMutationService(modelContainer: container)
        let changeSet = TrackMetadataChangeSet(
            baselines: [baseline(for: track, favorite: false)],
            edits: [.title: .text("Mine"), .rating: .number(5)]
        )

        track.title = "First Current"
        try container.mainContext.save()
        guard case .conflicts(let conflicts) = try await service.apply(changeSet, decisions: []),
              let conflict = conflicts.first else {
            Issue.record("Expected initial conflict")
            return
        }
        // Returning to the opening value is still drift relative to the value
        // reviewed in the conflict sheet; the old decision must not be reused.
        track.title = "Opening"
        try container.mainContext.save()

        let outcome = try await service.apply(changeSet, decisions: [
            TrackMetadataConflictDecision(
                trackID: track.id,
                field: .title,
                expectedCurrent: conflict.current,
                resolution: .useProposed
            ),
        ])
        guard case .conflicts(let refreshed) = outcome else {
            Issue.record("Expected refreshed conflict")
            return
        }
        #expect(refreshed.first?.current == .text("Opening"))
        let unchanged = try fetchTrack(track.id, from: container)
        #expect(unchanged.title == "Opening")
        #expect(unchanged.rating == 0)
    }

    @Test("Album metadata and artwork reconcile inside one mutation boundary")
    @MainActor
    func albumAndArtworkReconcileTogether() async throws {
        let container = try makeContainer()
        let track = try insertTrack(in: container)
        let service = TrackMetadataMutationService(modelContainer: container)
        let artwork = Data([1, 2, 3, 4])
        let changeSet = TrackMetadataChangeSet(
            baselines: [baseline(for: track, favorite: false)],
            edits: [.album: .text("New Album"), .artwork: .artwork(artwork)]
        )

        #expect(try await service.apply(changeSet, decisions: []) == .saved(trackCount: 1))
        let applied = try fetchTrack(track.id, from: container)
        #expect(applied.album == "New Album")
        #expect(applied.albumRelation?.title == "New Album")
        #expect(applied.albumRelation?.artworkData == ArtworkStorage.normalized(artwork))
    }

    @Test("A missing stable target aborts the request")
    @MainActor
    func missingTargetAborts() async throws {
        let container = try makeContainer()
        let service = TrackMetadataMutationService(modelContainer: container)
        let missingID = UUID()
        let changeSet = TrackMetadataChangeSet(
            baselines: [TrackMetadataBaseline(
                trackID: missingID,
                values: [.title: .text("Opening")]
            )],
            edits: [.title: .text("Mine")]
        )

        await #expect(throws: TrackMetadataMutationError.missingTarget(missingID)) {
            _ = try await service.apply(changeSet, decisions: [])
        }
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Track.self, Album.self, Artist.self, Playlist.self, AlbumFavorite.self, TrackFavorite.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    @MainActor
    private func insertTrack(in container: ModelContainer) throws -> Track {
        let track = Track(
            path: "/Music/Old Album/01.flac",
            title: "Opening",
            artist: "Artist",
            album: "Old Album"
        )
        let album = Album(title: "Old Album", artist: "Artist")
        let artist = Artist(name: "Artist")
        track.albumArtist = "Artist"
        track.albumRelation = album
        track.artistRelation = artist
        container.mainContext.insert(album)
        container.mainContext.insert(artist)
        container.mainContext.insert(track)
        try container.mainContext.save()
        return track
    }

    @MainActor
    private func baseline(for track: Track, favorite: Bool) -> TrackMetadataBaseline {
        TrackMetadataBaseline(trackID: track.id, values: [
            .title: .text(track.title), .artist: .text(track.artist),
            .album: .text(track.album), .albumArtist: .text(track.albumArtist),
            .genre: .text(track.genre), .composer: .text(track.composer),
            .comment: .text(track.comment), .year: .number(track.year),
            .trackNumber: .number(track.trackNumber), .trackTotal: .number(track.trackTotal),
            .discNumber: .number(track.discNumber), .discTotal: .number(track.discTotal),
            .beatsPerMinute: .number(track.beatsPerMinute), .rating: .number(track.rating),
            .favorite: .flag(favorite), .artwork: .artwork(track.albumRelation?.artworkData),
        ])
    }

    @MainActor
    private func fetchTrack(_ id: UUID, from container: ModelContainer) throws -> Track {
        let context = ModelContext(container)
        return try #require(context.fetch(FetchDescriptor<Track>()).first { $0.id == id })
    }

    @MainActor
    private func favoriteIDs(in container: ModelContainer) throws -> Set<UUID> {
        let context = ModelContext(container)
        return Set(try context.fetch(FetchDescriptor<TrackFavorite>()).map(\.trackID))
    }
}
