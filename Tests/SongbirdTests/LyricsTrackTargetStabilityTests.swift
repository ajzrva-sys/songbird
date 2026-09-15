import SwiftData
import Testing
@testable import SongbirdLib

struct LyricsTrackTargetStabilityTests {
    @Test("Lyrics targets remain readable after track deletion and replacement")
    @MainActor
    func presentationDoesNotRetainDeletedTrack() throws {
        let schema = Schema(versionedSchema: SongbirdSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let original = Track(
            path: "/Original/Lyrics.flac",
            title: "Original Title",
            artist: "Original Artist",
            album: "Original Album"
        )
        context.insert(original)
        try context.save()
        let trackID = original.id
        let target = LyricsTrackTarget(track: original)

        context.delete(original)
        try context.save()
        #expect(target.id == trackID)
        #expect(target.title == "Original Title")
        #expect(target.artist == "Original Artist")
        #expect(target.path == "/Original/Lyrics.flac")

        let replacement = Track(
            path: "/Replacement/Lyrics.flac",
            title: "Replacement Title",
            artist: "Replacement Artist",
            album: "Replacement Album"
        )
        replacement.id = trackID
        context.insert(replacement)
        try context.save()

        let replacementTarget = LyricsTrackTarget(track: replacement)
        #expect(target.id == replacementTarget.id)
        #expect(target.title == "Original Title")
        #expect(target.path == "/Original/Lyrics.flac")
        #expect(replacementTarget.title == "Replacement Title")
        #expect(replacementTarget.path == "/Replacement/Lyrics.flac")
    }
}
