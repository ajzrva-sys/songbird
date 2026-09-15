import Foundation
import SwiftData

enum SmartPlaylistEditorTargetResolutionError: LocalizedError, Equatable {
    case missingPlaylist

    var errorDescription: String? {
        "This smart playlist is no longer in the library. Close the editor and try again."
    }
}

/// Value-only smart-playlist state safe to retain while its editor is open.
struct SmartPlaylistEditorTarget: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let rules: SmartPlaylistRuleSet?

    @MainActor
    init(playlist: Playlist) {
        id = playlist.id
        name = playlist.name
        rules = SmartPlaylistRuleSet.decode(from: playlist.smartPlaylistRules)
    }

    init(snapshot: LibraryPlaylistSnapshot) {
        id = snapshot.id
        name = snapshot.name
        rules = snapshot.rules
    }

    @MainActor
    func resolve(in context: ModelContext) throws -> Playlist? {
        let targetID = id
        var descriptor = FetchDescriptor<Playlist>(
            predicate: #Predicate { playlist in playlist.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @MainActor
    func resolveRequired(in context: ModelContext) throws -> Playlist {
        guard let playlist = try resolve(in: context) else {
            throw SmartPlaylistEditorTargetResolutionError.missingPlaylist
        }
        return playlist
    }
}
