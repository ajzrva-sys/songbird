import Combine
import Foundation

public enum LibraryRoute: Hashable {
    case album(albumID: UUID)
    case artist(name: String)
    case genre(name: String)
    case health(category: LibraryHealthCategory)

    public var sidebarDestination: ServicePaneDestination {
        switch self {
        case .album: .albums
        case .artist: .artists
        case .genre: .genres
        case .health(let category):
            switch category {
            case .missingFiles: .ghostTracks
            case .unavailableVolumes: .unavailableTracks
            case .duplicateTracks: .duplicateTracks
            case .missingArtwork: .missingArtwork
            case .missingGenre: .missingGenre
            case .missingArtistNames: .unknownArtist
            case .missingAlbumNames: .unknownAlbum
            case .missingTrackNumber: .missingTrackNumber
            case .emptyTitles: .emptyTitles
            case .missingYear: .missingYear
            case .inconsistentArtists: .inconsistentArtists
            case .inconsistentAlbums: .inconsistentAlbums
            case .inconsistentGenres: .inconsistentGenres
            case .inconsistentAlbumArtists: .inconsistentAlbumArtists
            case .filledComments: .filledComments
            case .lowBitrate: .lowBitrate
            }
        }
    }
}

/// App-owned navigation state shared by the library, queue, and player windows.
@MainActor
public final class LibraryNavigationCoordinator: ObservableObject {
    @Published public private(set) var rootDestination: ServicePaneDestination?
    @Published public private(set) var selectedSidebarDestination: ServicePaneDestination?
    @Published public var path: [LibraryRoute] = [] {
        didSet {
            synchronizeSidebarSelection()
            LibraryViewState.saveNavigationPath(path)
        }
    }

    public var selectedRoot: ServicePaneDestination? { selectedSidebarDestination }

    /// True when the main column already presents the destination's large
    /// artwork, so the sidebar should not repeat the same image.
    public var presentsPrimaryArtwork: Bool {
        if case .album = path.last {
            return true
        }
        if case .audioCD = rootDestination, path.isEmpty {
            return true
        }
        return false
    }

    public init(selectedRoot: ServicePaneDestination? = .allTracks, restoresPersistedState: Bool = true) {
        if restoresPersistedState,
           let restored = LibraryViewState.loadRootDestination() {
            rootDestination = restored
            selectedSidebarDestination = restored
            path = LibraryViewState.loadNavigationPath()
            synchronizeSidebarSelection()
        } else {
            rootDestination = selectedRoot
            selectedSidebarDestination = selectedRoot
        }
    }

    public func selectRoot(_ destination: ServicePaneDestination?) {
        if let category = destination?.healthCategory {
            setRootDestination(.healthDashboard, sidebar: destination)
            path = [.health(category: category)]
            return
        }
        setRootDestination(destination, sidebar: destination)
        path.removeAll()
    }

    public func push(_ route: LibraryRoute, bringMainPlayerForward: Bool = false) {
        if path.last != route {
            path.append(route)
        }
        bringForwardIfNeeded(bringMainPlayerForward)
    }

    public func pop() {
        guard path.isEmpty == false else { return }
        path.removeLast()
    }

    public func showAlbum(albumID: UUID, bringMainPlayerForward: Bool = false) {
        push(.album(albumID: albumID), bringMainPlayerForward: bringMainPlayerForward)
    }

    public func showArtist(name: String, bringMainPlayerForward: Bool = false) {
        push(.artist(name: name), bringMainPlayerForward: bringMainPlayerForward)
    }

    public func showGenre(name: String, bringMainPlayerForward: Bool = false) {
        push(.genre(name: name), bringMainPlayerForward: bringMainPlayerForward)
    }

    public func showHealth(_ category: LibraryHealthCategory) {
        if rootDestination != .healthDashboard {
            setRootDestination(.healthDashboard, sidebar: selectedSidebarDestination)
        }
        path = [.health(category: category)]
    }

    private func setRootDestination(
        _ destination: ServicePaneDestination?,
        sidebar: ServicePaneDestination?
    ) {
        rootDestination = destination
        selectedSidebarDestination = sidebar
        LibraryViewState.saveRootDestination(destination)
    }

    private func synchronizeSidebarSelection() {
        selectedSidebarDestination = path.last?.sidebarDestination ?? rootDestination
    }

    private func bringForwardIfNeeded(_ bringForward: Bool) {
        guard bringForward else { return }
        NotificationCenter.default.post(name: .showMainPlayer, object: nil)
    }
}

private extension ServicePaneDestination {
    var healthCategory: LibraryHealthCategory? {
        switch self {
        case .ghostTracks: .missingFiles
        case .unavailableTracks: .unavailableVolumes
        case .duplicateTracks: .duplicateTracks
        case .missingArtwork: .missingArtwork
        case .missingGenre: .missingGenre
        case .unknownArtist: .missingArtistNames
        case .unknownAlbum: .missingAlbumNames
        case .missingTrackNumber: .missingTrackNumber
        case .emptyTitles: .emptyTitles
        case .missingYear: .missingYear
        case .inconsistentArtists: .inconsistentArtists
        case .inconsistentAlbums: .inconsistentAlbums
        case .inconsistentGenres: .inconsistentGenres
        case .inconsistentAlbumArtists: .inconsistentAlbumArtists
        case .filledComments: .filledComments
        case .lowBitrate: .lowBitrate
        default: nil
        }
    }
}
