import XCTest
@testable import SongbirdLib

@MainActor
final class LibraryNavigationCoordinatorTests: XCTestCase {
    private var defaultsSuite: UserDefaults!

    override func setUp() {
        super.setUp()
        clearViewStateKeys()
    }

    override func tearDown() {
        clearViewStateKeys()
        super.tearDown()
    }

    private func clearViewStateKeys() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: LibraryViewState.rootDestinationKey)
        defaults.removeObject(forKey: LibraryViewState.navigationPathKey)
        defaults.removeObject(forKey: LibraryViewState.playingAlbumIDKey)
        defaults.removeObject(forKey: LibraryViewState.playingAlbumTitleKey)
        defaults.removeObject(forKey: LibraryViewState.albumGridAnchorKey(for: .all))
        defaults.removeObject(forKey: LibraryViewState.albumGridAnchorKey(for: .recentlyAdded(limit: 100)))
    }

    func testOpeningAlbumSelectsAlbumsRootAndUsesStableIDRoute() {
        let coordinator = LibraryNavigationCoordinator(selectedRoot: .allTracks, restoresPersistedState: false)
        let albumID = UUID()

        coordinator.showAlbum(albumID: albumID)

        XCTAssertEqual(coordinator.selectedRoot, .albums)
        XCTAssertEqual(coordinator.path, [.album(albumID: albumID)])
        XCTAssertTrue(coordinator.presentsPrimaryArtwork)
    }

    func testPrimaryArtworkPresentationTracksAlbumAndAudioCDDestinations() {
        let coordinator = LibraryNavigationCoordinator(restoresPersistedState: false)
        XCTAssertFalse(coordinator.presentsPrimaryArtwork)

        coordinator.showAlbum(albumID: UUID())
        XCTAssertTrue(coordinator.presentsPrimaryArtwork)

        coordinator.pop()
        XCTAssertFalse(coordinator.presentsPrimaryArtwork)

        coordinator.selectRoot(.audioCD(DiscIdentifier("disc")))
        XCTAssertTrue(coordinator.presentsPrimaryArtwork)
    }

    func testOpeningArtistAndGenrePreservesMatchingSidebarRoot() {
        let coordinator = LibraryNavigationCoordinator(restoresPersistedState: false)

        coordinator.showArtist(name: "Nina Simone")
        XCTAssertEqual(coordinator.selectedRoot, .artists)
        XCTAssertEqual(coordinator.path, [.artist(name: "Nina Simone")])

        coordinator.showGenre(name: "Jazz")
        XCTAssertEqual(coordinator.selectedRoot, .genres)
        XCTAssertEqual(
            coordinator.path,
            [.artist(name: "Nina Simone"), .genre(name: "Jazz")]
        )

        coordinator.pop()
        XCTAssertEqual(coordinator.selectedRoot, .artists)
        XCTAssertEqual(coordinator.path, [.artist(name: "Nina Simone")])
    }

    func testSelectingSidebarRootClearsDetailPath() {
        let coordinator = LibraryNavigationCoordinator(restoresPersistedState: false)
        coordinator.showAlbum(albumID: UUID())

        coordinator.selectRoot(.allTracks)

        XCTAssertEqual(coordinator.selectedRoot, .allTracks)
        XCTAssertTrue(coordinator.path.isEmpty)
    }

    func testMiniPlayerNavigationRequestsMainWindow() {
        let coordinator = LibraryNavigationCoordinator(restoresPersistedState: false)
        let expectation = expectation(
            forNotification: .showMainPlayer,
            object: nil
        )

        coordinator.showArtist(name: "Björk", bringMainPlayerForward: true)

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(coordinator.path, [.artist(name: "Björk")])
    }

    func testNavigationStateSurvivesCoordinatorRecreation() {
        let albumID = UUID()
        do {
            let coordinator = LibraryNavigationCoordinator(restoresPersistedState: false)
            coordinator.selectRoot(.recentlyAdded)
            coordinator.showAlbum(albumID: albumID)
            XCTAssertEqual(coordinator.rootDestination, .recentlyAdded)
            XCTAssertEqual(coordinator.path, [.album(albumID: albumID)])
        }

        let restored = LibraryNavigationCoordinator(selectedRoot: .allTracks, restoresPersistedState: true)
        XCTAssertEqual(restored.rootDestination, .recentlyAdded)
        XCTAssertEqual(restored.path, [.album(albumID: albumID)])
        XCTAssertEqual(restored.selectedRoot, .albums)
    }

    func testAlbumGridAnchorAndPlayingAlbumPersistAndResolve() {
        let albumID = UUID()
        let group = LibraryAlbumGroupSnapshot(
            id: "group-1",
            title: "浴佛偈",
            artist: "佛光山梵呗赞颂团",
            year: 2020,
            dateAdded: Date(),
            albumIDs: [albumID],
            trackIDs: [UUID()],
            artworkReference: nil,
            discCount: 1,
            isFavorite: false
        )
        let projection = AlbumGridProjection(
            request: AlbumGridProjectionRequest(
                sourceRevision: 1,
                searchText: "",
                favoritesOnly: false,
                sortOrder: .recentlyAdded,
                scope: .recentlyAdded(limit: 100)
            ),
            groups: [group],
            orderedIDs: [group.id],
            groupsByID: [group.id: group],
            displayDetails: [:]
        )

        LibraryViewState.savePlayingAlbum(id: albumID, title: group.title)
        LibraryViewState.saveAlbumGridAnchor(albumID.uuidString, for: .recentlyAdded(limit: 100))

        XCTAssertEqual(LibraryViewState.playingAlbumID, albumID)
        XCTAssertEqual(
            LibraryViewState.loadAlbumGridAnchor(for: .recentlyAdded(limit: 100)),
            albumID.uuidString
        )
        XCTAssertEqual(
            LibraryViewState.resolveScrollGroupID(in: projection, scope: .recentlyAdded(limit: 100)),
            group.id
        )

        LibraryViewState.saveAlbumGridAnchor(nil, for: .recentlyAdded(limit: 100))
        XCTAssertEqual(
            LibraryViewState.resolveScrollGroupID(in: projection, scope: .recentlyAdded(limit: 100)),
            group.id,
            "Playing album alone should still resolve the grid group"
        )
    }

    func testDestinationAndRouteRoundTrip() {
        let playlistID = UUID()
        let albumID = UUID()
        let destinations: [ServicePaneDestination] = [
            .allTracks,
            .albums,
            .recentlyAdded,
            .queue,
            .playlist(playlistID),
            .audioCD(DiscIdentifier("disc-1")),
        ]
        for destination in destinations {
            let encoded = LibraryViewState.encode(destination)
            XCTAssertEqual(LibraryViewState.decodeDestination(encoded), destination)
        }

        let routes: [LibraryRoute] = [
            .album(albumID: albumID),
            .artist(name: "戶川純ユニット"),
            .genre(name: "Buddhist Chant"),
            .health(category: .missingFiles),
        ]
        for route in routes {
            let encoded = LibraryViewState.encode(route: route)
            XCTAssertEqual(LibraryViewState.decode(route: encoded), route)
        }
    }
}
