import Foundation
import SwiftData

public struct LibraryResetResult: Equatable, Sendable {
    public let tracks: Int
    public let albums: Int
    public let artists: Int
    public let albumFavorites: Int
    public let personalPlaylists: Int

    public init(
        tracks: Int,
        albums: Int,
        artists: Int,
        albumFavorites: Int,
        personalPlaylists: Int
    ) {
        self.tracks = tracks
        self.albums = albums
        self.artists = artists
        self.albumFavorites = albumFavorites
        self.personalPlaylists = personalPlaylists
    }
}

@MainActor
enum LibraryResetPresentation {
    static func prepare(
        queue: PlaybackQueue,
        navigation: LibraryNavigationCoordinator,
        selection: LibrarySelectionState,
        stopPlayback: () -> Void
    ) {
        stopPlayback()
        queue.clear()
        selection.updateLibrarySelection(trackID: nil, track: nil)
        navigation.selectRoot(.allTracks)
    }
}

/// Clears Songbird-owned catalog data without touching audio files, folder
/// configuration, preferences, credentials, or the open SwiftData store.
public actor LibraryResetService {
    private let container: ModelContainer
    private let importExclusions: LibraryImportExclusionStore

    public init(
        modelContainer: ModelContainer,
        importExclusions: LibraryImportExclusionStore = .shared
    ) {
        container = modelContainer
        self.importExclusions = importExclusions
    }

    public func reset() async throws -> LibraryResetResult {
        try await LibraryImportPipeline.acquireExclusiveMaintenanceAccess()
        do {
            let result = try resetCatalog()
            importExclusions.clear()
            await LibraryImportPipeline.releaseExclusiveMaintenanceAccess()
            return result
        } catch {
            await LibraryImportPipeline.releaseExclusiveMaintenanceAccess()
            throw error
        }
    }

    private func resetCatalog() throws -> LibraryResetResult {
        let context = ModelContext(container)
        let personalPlaylistPredicate = #Predicate<Playlist> { playlist in
            playlist.systemKey == nil || playlist.systemKey == ""
        }
        let result = LibraryResetResult(
            tracks: try context.fetchCount(FetchDescriptor<Track>()),
            albums: try context.fetchCount(FetchDescriptor<Album>()),
            artists: try context.fetchCount(FetchDescriptor<Artist>()),
            albumFavorites: try context.fetchCount(FetchDescriptor<AlbumFavorite>()),
            personalPlaylists: try context.fetchCount(FetchDescriptor<Playlist>(
                predicate: personalPlaylistPredicate
            ))
        )

        do {
            for favorite in try context.fetch(FetchDescriptor<AlbumFavorite>()) {
                context.delete(favorite)
            }
            for playlist in try context.fetch(FetchDescriptor<Playlist>(
                predicate: personalPlaylistPredicate
            )) {
                context.delete(playlist)
            }
            for track in try context.fetch(FetchDescriptor<Track>()) {
                context.delete(track)
            }
            for album in try context.fetch(FetchDescriptor<Album>()) {
                context.delete(album)
            }
            for artist in try context.fetch(FetchDescriptor<Artist>()) {
                context.delete(artist)
            }
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }
}
