import SwiftData
import Foundation
import Testing
@testable import SongbirdLib

struct TrackInfoTargetStabilityTests {
    @Test("Three-way changes merge disjoint edits and report divergence")
    func threeWayMerge() {
        let id = UUID()
        let opening: [TrackMetadataField: TrackMetadataValue] = [
            .title: .text("Opening"),
            .genre: .text("Rock"),
        ]
        let titleEdit = TrackMetadataChangeSet(
            baselines: [TrackMetadataBaseline(trackID: id, values: opening)],
            edits: [.title: .text("Mine")]
        )

        #expect(titleEdit.conflicts(currentValues: [id: [
            .title: .text("Opening"),
            .genre: .text("Jazz"),
        ]]).isEmpty)

        let conflicts = titleEdit.conflicts(currentValues: [id: [
            .title: .text("Theirs"),
            .genre: .text("Rock"),
        ]])
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.opening == .text("Opening"))
        #expect(conflicts.first?.current == .text("Theirs"))
        #expect(conflicts.first?.proposed == .text("Mine"))
    }

    @Test("Current proposed values are converged, including Favorite and artwork")
    func convergedValues() {
        let id = UUID()
        let changes = TrackMetadataChangeSet(
            baselines: [TrackMetadataBaseline(
                trackID: id,
                values: [.favorite: .flag(false), .artwork: .artwork(nil)]
            )],
            edits: [.favorite: .flag(true), .artwork: .artwork(Data([1, 2, 3]))]
        )

        #expect(changes.conflicts(currentValues: [id: [
            .favorite: .flag(true),
            .artwork: .artwork(Data([1, 2, 3])),
        ]]).isEmpty)
    }

    @Test("Track Info targets resolve current reconciliation replacements")
    @MainActor
    func targetsResolveCurrentReplacements() throws {
        let schema = Schema(versionedSchema: SongbirdSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let originals = [
            Track(path: "/Original/A.flac", title: "Original A", artist: "Artist", album: "Album"),
            Track(path: "/Original/B.flac", title: "Original B", artist: "Artist", album: "Album"),
        ]
        for track in originals { context.insert(track) }
        try context.save()
        let trackIDs = originals.map(\.id)
        let targets = originals.map(TrackInfoTarget.init(track:))

        for track in originals { context.delete(track) }
        try context.save()
        #expect(targets.map(\.title) == ["Original A", "Original B"])
        let deletedResolution = try TrackInfoTarget.resolve(targets, in: context)
        #expect(deletedResolution.isEmpty)
        #expect(throws: TrackInfoTargetResolutionError.missingTracks) {
            try TrackInfoTarget.resolveAll(targets, in: context)
        }

        let replacements = zip(trackIDs, ["Replacement A", "Replacement B"]).map { id, title in
            let track = Track(
                path: "/Replacement/\(title).flac",
                title: title,
                artist: "Artist",
                album: "Album"
            )
            track.id = id
            context.insert(track)
            return track
        }
        try context.save()

        let resolved = try TrackInfoTarget.resolveAll(targets, in: context)
        #expect(resolved.map(\.persistentModelID) == replacements.map(\.persistentModelID))
        #expect(resolved.map(\.title) == ["Replacement A", "Replacement B"])
    }

    @Test("Track Info targets preserve order and deduplicate track IDs")
    @MainActor
    func targetsPreserveOrderAndDeduplicate() throws {
        let schema = Schema(versionedSchema: SongbirdSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let first = Track(path: "/First.flac", title: "First")
        let second = Track(path: "/Second.flac", title: "Second")
        context.insert(first)
        context.insert(second)
        try context.save()

        let firstTarget = TrackInfoTarget(track: first)
        let secondTarget = TrackInfoTarget(track: second)
        let resolved = try TrackInfoTarget.resolve(
            [secondTarget, firstTarget, secondTarget],
            in: context
        )

        #expect(resolved.map(\.id) == [second.id, first.id])
    }
}
