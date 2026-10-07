import XCTest
@testable import SongbirdLib

@MainActor
final class AlbumGroupingTests: XCTestCase {
    func testMixedArtistDiscsAndMistaggedYearCollapseIntoOneCollection() async throws {
        let discOne = album(
            title: "Cesar Franck Edition - CD1",
            artist: "Orchestra",
            year: 2019,
            path: "/Music/Cesar Franck/CD01 - Symphonies/01.flac"
        )
        let discTwo = album(
            title: "Cesar Franck Edition - CD2",
            artist: "Soloist",
            year: 2019,
            path: "/Music/Cesar Franck/CD02 - Concertos/01.flac"
        )
        let discNine = album(
            title: "Cesar Franck Edition - 2019",
            artist: "Pianist",
            year: 2019,
            path: "/Music/Cesar Franck/CD09 - Fantaisies/01.flac"
        )

        let albums = [discNine, discTwo, discOne]
        let groups = try await groups(from: albums)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Cesar Franck Edition")
        XCTAssertEqual(groups[0].artist, "Various Artists")
        XCTAssertEqual(groups[0].discCount, 3)
        XCTAssertEqual(
            albumTitles(in: groups[0], from: albums),
            [
                "Cesar Franck Edition - CD1",
                "Cesar Franck Edition - CD2",
                "Cesar Franck Edition - 2019",
            ]
        )
    }

    func testRomanNumeralVolumesCollapseIntoOneCollection() async throws {
        let discOne = album(
            title: "Couperin: Complete Works for Harpsichord, I. L'Art de toucher",
            artist: "Carole Cerasi",
            year: 2018,
            path: "/Music/Couperin/01 - I. L'Art de toucher/01.flac"
        )
        let discNine = album(
            title: "Couperin: Complete Works for Harpsichord,IX. 21e-24e Ordres",
            artist: "Carole Cerasi",
            year: 2018,
            path: "/Music/Couperin/09 - IX. 21e-24e Ordres/01.flac"
        )
        let discTen = album(
            title: "Couperin: Complete Works for Harpsichord, X. 25e-27e Ordres",
            artist: "Carole Cerasi",
            year: 2018,
            path: "/Music/Couperin/10 - X. 25e-27e Ordres/01.flac"
        )

        let albums = [discTen, discNine, discOne]
        let groups = try await groups(from: albums)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Couperin: Complete Works for Harpsichord")
        XCTAssertEqual(groups[0].artist, "Carole Cerasi")
        XCTAssertEqual(groups[0].discCount, 3)
        XCTAssertEqual(
            albumTitles(in: groups[0], from: albums),
            [
                "Couperin: Complete Works for Harpsichord, I. L'Art de toucher",
                "Couperin: Complete Works for Harpsichord,IX. 21e-24e Ordres",
                "Couperin: Complete Works for Harpsichord, X. 25e-27e Ordres",
            ]
        )
    }

    func testSiblingDiscFoldersCollapseDespiteUnrelatedAlbumTags() async throws {
        let first = album(
            title: "Symphonies and Overtures",
            artist: "First Orchestra",
            year: 1998,
            path: "/Music/Big Composer Edition/CD 01 - Orchestral/01.flac"
        )
        let second = album(
            title: "Piano and Chamber Works",
            artist: "Second Ensemble",
            year: 2004,
            path: "/Music/Big Composer Edition/CD 02 - Chamber/01.flac"
        )

        let albums = [second, first]
        let groups = try await groups(from: albums)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Big Composer Edition")
        XCTAssertEqual(groups[0].artist, "Various Artists")
        XCTAssertEqual(groups[0].discCount, 2)
        XCTAssertEqual(
            albumTitles(in: groups[0], from: albums),
            ["Symphonies and Overtures", "Piano and Chamber Works"]
        )
    }

    func testCollectionFolderMergesMixedTitlesAndDuplicateDiscMetadata() async throws {
        let first = album(
            title: "CD17.汉宫秋月",
            artist: "群星",
            year: 1998,
            path: "/Music/Chinese Collection/CD17.汉宫秋月/FLAC/01.flac"
        )
        let sameDisc = album(
            title: "Traditional Instrumental Favorites",
            artist: "Soloist",
            year: 2004,
            path: "/Music/Chinese Collection/CD17.汉宫秋月/FLAC/02.flac"
        )
        let second = album(
            title: "CD18.霓裳曲",
            artist: "Second Ensemble",
            year: 2011,
            path: "/Music/Chinese Collection/CD18.霓裳曲/FLAC/01.flac"
        )

        let albums = [second, sameDisc, first]
        let groups = try await groups(from: albums)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Chinese Collection")
        XCTAssertEqual(groups[0].artist, "Various Artists")
        XCTAssertEqual(groups[0].partCount, 2)
        XCTAssertEqual(groups[0].discCount, 2)
        XCTAssertEqual(Set(groups[0].albumIDs), Set(albums.map(\.id)))
    }

    func testAlbumsInOrdinarySiblingFoldersRemainSeparate() async throws {
        let first = album(
            title: "First Album",
            artist: "Same Artist",
            year: 2020,
            path: "/Music/Same Artist/First Album/01.flac"
        )
        let second = album(
            title: "Second Album",
            artist: "Same Artist",
            year: 2021,
            path: "/Music/Same Artist/Second Album/01.flac"
        )

        let result = try await groups(from: [first, second])
        XCTAssertEqual(result.count, 2)
    }

    func testSameTitleAndYearDiscsFromDifferentArtistsRemainSeparate() async throws {
        let first = album(
            title: "Collected Works - CD1",
            artist: "Artist One",
            year: 2022,
            path: "/Music/Artist One/Collected Works/01.flac"
        )
        let second = album(
            title: "Collected Works - CD2",
            artist: "Artist Two",
            year: 2022,
            path: "/Music/Artist Two/Collected Works/01.flac"
        )

        let result = try await groups(from: [first, second])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.artist)), Set(["Artist One", "Artist Two"]))
    }

    func testArtistAlbumsRetainCompilationDiscsAndSeparatePhysicalEditions() async throws {
        let firstDisc = album(
            title: "Compilation - CD1", artist: "Various Artists", year: 2000,
            path: "/Music/Compilation/CD 1/01.flac"
        )
        let secondDisc = album(
            title: "Compilation - CD2", artist: "Various Artists", year: 2000,
            path: "/Music/Compilation/CD 2/01.flac"
        )
        let separateEdition = album(
            title: "Compilation", artist: "Various Artists", year: 2000,
            path: "/Music/Separate Edition/01.flac"
        )
        firstDisc.tracks[0].artist = "Performer"
        secondDisc.tracks[0].artist = "Guest"
        separateEdition.tracks[0].artist = "Performer"

        let projected = try await groups(from: [firstDisc, secondDisc, separateEdition])
        let artistAlbums = AlbumGridFilter.apply(
            to: projected, searchText: "", favoritesOnly: false, sortOrder: .title,
            scope: .artist(name: "Performer")
        )
        XCTAssertEqual(artistAlbums.count, 2)
        let collection = try XCTUnwrap(artistAlbums.first { $0.discCount == 2 })
        XCTAssertEqual(collection.artist, "Various Artists")
        XCTAssertEqual(collection.contributingArtistNames, ["Guest", "Performer"])
        XCTAssertEqual(Set(collection.albumIDs), [firstDisc.id, secondDisc.id])
        XCTAssertEqual(Set(collection.trackIDs), Set((firstDisc.tracks + secondDisc.tracks).map(\.id)))
        XCTAssertEqual(artistAlbums.first { $0.discCount == 1 }?.albumIDs, [separateEdition.id])
        XCTAssertEqual(AlbumGridFilter.apply(
            to: projected, searchText: "", favoritesOnly: false, sortOrder: .title,
            scope: .artist(name: "Guest")
        ), [collection])
    }

    private func groups(from albums: [Album]) async throws -> [LibraryAlbumGroupSnapshot] {
        let tracks = albums.flatMap(\.tracks)
        let snapshot = LibrarySnapshot(
            revision: 1,
            tracks: tracks.map {
                LibraryTrackSnapshot(track: $0, albumRating: 0, albumsWithArtwork: [])
            },
            albums: albums.map {
                LibraryAlbumSnapshot(album: $0, favoriteAlbumIDs: [])
            },
            playlists: []
        )
        return try await LibraryAlbumProjectionWorker().project(snapshot)
    }

    private func albumTitles(
        in group: LibraryAlbumGroupSnapshot,
        from albums: [Album]
    ) -> [String] {
        let titles = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0.title) })
        return group.albumIDs.compactMap { titles[$0] }
    }

    private func album(
        title: String,
        artist: String,
        year: Int,
        path: String
    ) -> Album {
        let album = Album(title: title, artist: artist, year: year)
        let track = Track(path: path, title: "Track", artist: artist, album: title)
        track.albumArtist = artist
        track.albumRelation = album
        return album
    }
}
