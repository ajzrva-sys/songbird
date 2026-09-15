import XCTest
@testable import SongbirdLib

@MainActor
final class LibraryNavigationCoordinatorTests: XCTestCase {
    func testOpeningAlbumSelectsAlbumsRootAndUsesStableIDRoute() {
        let coordinator = LibraryNavigationCoordinator(selectedRoot: .allTracks)
        let albumID = UUID()

        coordinator.showAlbum(albumID: albumID)

        XCTAssertEqual(coordinator.selectedRoot, .albums)
        XCTAssertEqual(coordinator.path, [.album(albumID: albumID)])
        XCTAssertTrue(coordinator.presentsPrimaryArtwork)
    }

    func testPrimaryArtworkPresentationTracksAlbumAndAudioCDDestinations() {
        let coordinator = LibraryNavigationCoordinator()
        XCTAssertFalse(coordinator.presentsPrimaryArtwork)

        coordinator.showAlbum(albumID: UUID())
        XCTAssertTrue(coordinator.presentsPrimaryArtwork)

        coordinator.pop()
        XCTAssertFalse(coordinator.presentsPrimaryArtwork)

        coordinator.selectRoot(.audioCD(DiscIdentifier("disc")))
        XCTAssertTrue(coordinator.presentsPrimaryArtwork)
    }

    func testOpeningArtistAndGenrePreservesMatchingSidebarRoot() {
        let coordinator = LibraryNavigationCoordinator()

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
        let coordinator = LibraryNavigationCoordinator()
        coordinator.showAlbum(albumID: UUID())

        coordinator.selectRoot(.allTracks)

        XCTAssertEqual(coordinator.selectedRoot, .allTracks)
        XCTAssertTrue(coordinator.path.isEmpty)
    }

    func testMiniPlayerNavigationRequestsMainWindow() {
        let coordinator = LibraryNavigationCoordinator()
        let expectation = expectation(
            forNotification: .showMainPlayer,
            object: nil
        )

        coordinator.showArtist(name: "Björk", bringMainPlayerForward: true)

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(coordinator.path, [.artist(name: "Björk")])
    }
}
