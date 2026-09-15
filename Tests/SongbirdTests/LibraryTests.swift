import XCTest
@testable import SongbirdLib

final class LibraryTests: XCTestCase {
    func testTrackInitialization() {
        let track = Track(path: "/music/song.mp3", title: "Test Song")
        XCTAssertEqual(track.title, "Test Song")
        XCTAssertEqual(track.artist, "Unknown Artist")
        XCTAssertEqual(track.rating, 0)
    }

    func testAlbumInitialization() {
        let album = Album(title: "Test Album", artist: "Test Artist")
        XCTAssertEqual(album.title, "Test Album")
        XCTAssertEqual(album.artist, "Test Artist")
    }

    func testArtistInitialization() {
        let artist = Artist(name: "Test Artist")
        XCTAssertEqual(artist.name, "Test Artist")
    }

    func testPlaylistInitialization() {
        let playlist = Playlist(name: "My Playlist")
        XCTAssertEqual(playlist.name, "My Playlist")
        XCTAssertFalse(playlist.smartPlaylist)
    }
}
