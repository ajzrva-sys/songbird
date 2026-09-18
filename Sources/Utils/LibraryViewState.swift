import Foundation

/// UserDefaults-backed library UI state so reopening the window (or relaunching)
/// returns to the album the user was viewing/playing instead of list start.
public enum LibraryViewState {
    public static let rootDestinationKey = "library.viewState.rootDestination"
    public static let navigationPathKey = "library.viewState.navigationPath"
    public static let playingAlbumIDKey = "library.viewState.playingAlbumID"
    public static let playingAlbumTitleKey = "library.viewState.playingAlbumTitle"
    private static let albumGridAnchorKeyPrefix = "library.viewState.albumGridAnchor."

    // MARK: - Root destination

    public static func saveRootDestination(_ destination: ServicePaneDestination?) {
        guard let destination else {
            UserDefaults.standard.removeObject(forKey: rootDestinationKey)
            return
        }
        UserDefaults.standard.set(encode(destination), forKey: rootDestinationKey)
    }

    public static func loadRootDestination() -> ServicePaneDestination? {
        guard let raw = UserDefaults.standard.string(forKey: rootDestinationKey) else {
            return nil
        }
        return decodeDestination(raw)
    }

    // MARK: - Navigation path

    public static func saveNavigationPath(_ path: [LibraryRoute]) {
        guard path.isEmpty == false else {
            UserDefaults.standard.removeObject(forKey: navigationPathKey)
            return
        }
        let encoded = path.map(encode(route:))
        UserDefaults.standard.set(encoded, forKey: navigationPathKey)
    }

    public static func loadNavigationPath() -> [LibraryRoute] {
        guard let encoded = UserDefaults.standard.stringArray(forKey: navigationPathKey) else {
            return []
        }
        return encoded.compactMap(decode(route:))
    }

    // MARK: - Album grid anchors

    public static func albumGridAnchorKey(for scope: AlbumGridScope) -> String {
        switch scope {
        case .all:
            return albumGridAnchorKeyPrefix + "all"
        case .recentlyAdded:
            return albumGridAnchorKeyPrefix + "recentlyAdded"
        }
    }

    /// Group id (preferred) or album UUID string used to scroll a grid back into place.
    public static func saveAlbumGridAnchor(_ anchor: String?, for scope: AlbumGridScope) {
        let key = albumGridAnchorKey(for: scope)
        guard let anchor, anchor.isEmpty == false else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(anchor, forKey: key)
    }

    public static func loadAlbumGridAnchor(for scope: AlbumGridScope) -> String? {
        UserDefaults.standard.string(forKey: albumGridAnchorKey(for: scope))
    }

    // MARK: - Playing album

    public static func savePlayingAlbum(id: UUID?, title: String?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: playingAlbumIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: playingAlbumIDKey)
        }
        if let title, title.isEmpty == false {
            UserDefaults.standard.set(title, forKey: playingAlbumTitleKey)
        } else {
            UserDefaults.standard.removeObject(forKey: playingAlbumTitleKey)
        }
    }

    public static var playingAlbumID: UUID? {
        UserDefaults.standard.string(forKey: playingAlbumIDKey).flatMap(UUID.init(uuidString:))
    }

    public static var playingAlbumTitle: String? {
        UserDefaults.standard.string(forKey: playingAlbumTitleKey)
    }

    /// Resolve the grid group to scroll to: explicit anchor first, then playing album.
    static func resolveScrollGroupID(
        in projection: AlbumGridProjection,
        scope: AlbumGridScope
    ) -> String? {
        if let anchor = loadAlbumGridAnchor(for: scope) {
            if let group = projection.groups.first(where: { $0.id == anchor }) {
                return group.id
            }
            if let uuid = UUID(uuidString: anchor),
               let group = projection.groups.first(where: { $0.albumIDs.contains(uuid) }) {
                return group.id
            }
            if let group = projection.groups.first(where: { $0.title == anchor }) {
                return group.id
            }
        }
        guard let albumID = playingAlbumID else {
            if let title = playingAlbumTitle,
               let group = projection.groups.first(where: { $0.title == title }) {
                return group.id
            }
            return nil
        }
        return projection.groups.first(where: { $0.albumIDs.contains(albumID) })?.id
    }

    // MARK: - Encoding

    static func encode(_ destination: ServicePaneDestination) -> String {
        switch destination {
        case .allTracks: return "allTracks"
        case .artists: return "artists"
        case .albums: return "albums"
        case .genres: return "genres"
        case .recentlyAdded: return "recentlyAdded"
        case .topPlayed: return "topPlayed"
        case .healthDashboard: return "healthDashboard"
        case .ghostTracks: return "ghostTracks"
        case .unavailableTracks: return "unavailableTracks"
        case .duplicateTracks: return "duplicateTracks"
        case .missingGenre: return "missingGenre"
        case .missingArtwork: return "missingArtwork"
        case .unknownArtist: return "unknownArtist"
        case .unknownAlbum: return "unknownAlbum"
        case .missingTrackNumber: return "missingTrackNumber"
        case .inconsistentArtists: return "inconsistentArtists"
        case .inconsistentAlbums: return "inconsistentAlbums"
        case .emptyTitles: return "emptyTitles"
        case .missingYear: return "missingYear"
        case .lowBitrate: return "lowBitrate"
        case .inconsistentGenres: return "inconsistentGenres"
        case .filledComments: return "filledComments"
        case .inconsistentAlbumArtists: return "inconsistentAlbumArtists"
        case .queue: return "queue"
        case .playlist(let id): return "playlist:\(id.uuidString)"
        case .audioCD(let disc): return "audioCD:\(disc.id)"
        }
    }

    static func decodeDestination(_ raw: String) -> ServicePaneDestination? {
        if raw.hasPrefix("playlist:") {
            let uuidString = String(raw.dropFirst("playlist:".count))
            guard let id = UUID(uuidString: uuidString) else { return nil }
            return .playlist(id)
        }
        if raw.hasPrefix("audioCD:") {
            let discID = String(raw.dropFirst("audioCD:".count))
            guard discID.isEmpty == false else { return nil }
            return .audioCD(DiscIdentifier(discID))
        }
        switch raw {
        case "allTracks": return .allTracks
        case "artists": return .artists
        case "albums": return .albums
        case "genres": return .genres
        case "recentlyAdded": return .recentlyAdded
        case "topPlayed": return .topPlayed
        case "healthDashboard": return .healthDashboard
        case "ghostTracks": return .ghostTracks
        case "unavailableTracks": return .unavailableTracks
        case "duplicateTracks": return .duplicateTracks
        case "missingGenre": return .missingGenre
        case "missingArtwork": return .missingArtwork
        case "unknownArtist": return .unknownArtist
        case "unknownAlbum": return .unknownAlbum
        case "missingTrackNumber": return .missingTrackNumber
        case "inconsistentArtists": return .inconsistentArtists
        case "inconsistentAlbums": return .inconsistentAlbums
        case "emptyTitles": return .emptyTitles
        case "missingYear": return .missingYear
        case "lowBitrate": return .lowBitrate
        case "inconsistentGenres": return .inconsistentGenres
        case "filledComments": return .filledComments
        case "inconsistentAlbumArtists": return .inconsistentAlbumArtists
        case "queue": return .queue
        default: return nil
        }
    }

    static func encode(route: LibraryRoute) -> String {
        switch route {
        case .album(let albumID): return "album:\(albumID.uuidString)"
        case .artist(let name): return "artist:\(name)"
        case .genre(let name): return "genre:\(name)"
        case .health(let category): return "health:\(category.rawValue)"
        }
    }

    static func decode(route raw: String) -> LibraryRoute? {
        if raw.hasPrefix("album:") {
            let uuidString = String(raw.dropFirst("album:".count))
            guard let id = UUID(uuidString: uuidString) else { return nil }
            return .album(albumID: id)
        }
        if raw.hasPrefix("artist:") {
            return .artist(name: String(raw.dropFirst("artist:".count)))
        }
        if raw.hasPrefix("genre:") {
            return .genre(name: String(raw.dropFirst("genre:".count)))
        }
        if raw.hasPrefix("health:") {
            let value = String(raw.dropFirst("health:".count))
            guard let category = LibraryHealthCategory(rawValue: value) else { return nil }
            return .health(category: category)
        }
        return nil
    }
}
