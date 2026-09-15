import SwiftData
import Testing
@testable import SongbirdLib

struct DiscogsArtworkTargetStabilityTests {
    @Test("Discogs artwork targets resolve current reconciliation replacements")
    @MainActor
    func targetsResolveCurrentReplacements() throws {
        let schema = Schema(versionedSchema: SongbirdSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let originals = [
            Album(title: "Original A", artist: "Artist"),
            Album(title: "Original B", artist: "Artist"),
        ]
        for album in originals { context.insert(album) }
        try context.save()
        let albumIDs = originals.map(\.id)
        let targets = originals.map(DiscogsArtworkAlbumTarget.init(album:))

        for album in originals { context.delete(album) }
        try context.save()
        #expect(try targets[0].resolve(in: context) == nil)
        let deletedResolution = try DiscogsArtworkAlbumTarget.resolve(targets, in: context)
        #expect(deletedResolution.isEmpty)

        let replacements = zip(albumIDs, ["Replacement A", "Replacement B"]).map { id, title in
            let album = Album(title: title, artist: "Artist")
            album.id = id
            context.insert(album)
            return album
        }
        try context.save()

        let resolved = try DiscogsArtworkAlbumTarget.resolve(targets, in: context)
        #expect(resolved.map(\.persistentModelID) == replacements.map(\.persistentModelID))
        #expect(resolved.map(\.title) == replacements.map(\.title))
        let resolvedSingle = try targets[0].resolve(in: context)
        let single = try #require(resolvedSingle)
        #expect(single.persistentModelID == replacements[0].persistentModelID)
        #expect(single.title == "Replacement A")
    }

    @Test("Discogs artwork targets preserve order and deduplicate album IDs")
    @MainActor
    func targetsPreserveOrderAndDeduplicate() throws {
        let schema = Schema(versionedSchema: SongbirdSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let first = Album(title: "First", artist: "Artist")
        let second = Album(title: "Second", artist: "Artist")
        context.insert(first)
        context.insert(second)
        try context.save()

        let firstTarget = DiscogsArtworkAlbumTarget(album: first)
        let secondTarget = DiscogsArtworkAlbumTarget(album: second)
        let resolved = try DiscogsArtworkAlbumTarget.resolve(
            [secondTarget, firstTarget, secondTarget],
            in: context
        )

        #expect(resolved.map(\.id) == [second.id, first.id])
    }
}
