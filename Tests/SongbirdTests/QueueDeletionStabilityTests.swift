import SwiftData
import Testing
@testable import SongbirdLib

struct QueueDeletionStabilityTests {
    @Test("Saved track deletion removes every queue occurrence")
    @MainActor
    func savedTrackDeletionRemovesQueueOccurrences() throws {
        let schema = Schema(versionedSchema: SongbirdSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let track = Track(path: "/tmp/queue-deletion.mp3", title: "Delete Me")
        let trackID = track.id
        context.insert(track)
        try context.save()

        let queue = PlaybackQueue()
        queue.setStateForTesting(
            current: track,
            upcoming: [track, track],
            history: [track]
        )

        context.delete(track)
        try context.save()

        #expect(queue.removeTracks(trackIDs: [trackID]))
        #expect(queue.currentEntry?.id == nil)
        #expect(queue.upcomingEntries.isEmpty)
        #expect(queue.historyEntries.isEmpty)
    }
}
