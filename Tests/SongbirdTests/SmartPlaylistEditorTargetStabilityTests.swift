import SwiftData
import Testing
@testable import SongbirdLib

struct SmartPlaylistEditorTargetStabilityTests {
    @Test("Smart Playlist editor targets resolve current replacements")
    @MainActor
    func targetsResolveCurrentReplacements() throws {
        let schema = Schema(versionedSchema: SongbirdSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let original = Playlist(name: "Original Rules", smart: true)
        original.smartPlaylistRules = try SmartPlaylistRuleSet(conditions: [
            SmartCondition(field: .genre, op: .contains, value: "Jazz"),
        ]).encode()
        context.insert(original)
        try context.save()
        let playlistID = original.id
        let modelTarget = SmartPlaylistEditorTarget(playlist: original)
        let snapshotTarget = SmartPlaylistEditorTarget(
            snapshot: LibraryPlaylistSnapshot(playlist: original)
        )

        context.delete(original)
        try context.save()
        #expect(modelTarget.name == "Original Rules")
        #expect(snapshotTarget.rules?.conditions.first?.value == "Jazz")
        #expect(try modelTarget.resolve(in: context) == nil)
        #expect(try snapshotTarget.resolve(in: context) == nil)
        #expect(throws: SmartPlaylistEditorTargetResolutionError.missingPlaylist) {
            try snapshotTarget.resolveRequired(in: context)
        }

        let replacement = Playlist(name: "Replacement Rules", smart: true)
        replacement.id = playlistID
        context.insert(replacement)
        try context.save()

        let modelResolved = try modelTarget.resolveRequired(in: context)
        let snapshotResolved = try snapshotTarget.resolveRequired(in: context)
        #expect(modelResolved.persistentModelID == replacement.persistentModelID)
        #expect(snapshotResolved.persistentModelID == replacement.persistentModelID)
    }
}
