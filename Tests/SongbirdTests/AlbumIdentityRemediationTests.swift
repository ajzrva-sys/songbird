import Foundation
import SwiftData
import Testing
@testable import SongbirdLib

@Suite("Album identity remediation", .serialized)
struct AlbumIdentityRemediationTests {
    @Test("Numbered metadata volumes form one selectable logical facet")
    @MainActor
    func numberedVolumesCollapse() async throws {
        // Given
        let identifier = try fixtureIdentifier()
        var tracks: [LibraryTrackSnapshot] = []
        var albums: [LibraryAlbumSnapshot] = []
        for volume in 1...25 {
            let albumID = UUID()
            let trackID = UUID()
            let title = "Coleção Folha: Raízes da Música Popular Brasileira, Volume \(volume): Artist \(volume)"
            tracks.append(LibraryTrackSnapshot(
                id: trackID,
                persistentIdentifier: identifier,
                title: "Track \(volume)",
                artist: "Artist \(volume)",
                album: title,
                albumArtist: "Artist \(volume)",
                trackNumber: 1,
                path: "/Music/Coleção Folha/\(String(format: "%02d", volume)) - Artist \(volume)/01.flac",
                albumID: albumID
            ))
            albums.append(LibraryAlbumSnapshot(
                id: albumID,
                persistentIdentifier: identifier,
                title: title,
                artist: "Artist \(volume)",
                trackIDs: [trackID]
            ))
        }
        let snapshot = LibrarySnapshot(revision: 1, tracks: tracks, albums: albums, playlists: [])

        // When
        let groups = try await LibraryAlbumProjectionWorker().project(snapshot)
        let projection = try await TrackTableProjectionWorker().project(
            snapshot: snapshot,
            request: TrackTableRequest(collection: .allTracks),
            albumGroups: groups
        )
        let facet = try #require(projection.facets.albums.first)
        let selected = try await TrackTableProjectionWorker().project(
            snapshot: snapshot,
            request: TrackTableRequest(
                collection: .allTracks,
                selectedAlbumID: facet.id
            ),
            albumGroups: groups
        )

        // Then
        #expect(groups.count == 1)
        #expect(groups.first?.title == "Coleção Folha: Raízes da Música Popular Brasileira")
        #expect(groups.first?.partCount == 25)
        #expect(groups.first?.collectionKind == .volume)
        #expect(projection.facets.albums.count == 1)
        #expect(facet.detail == "25 volumes · Various Artists")
        #expect(selected.rows.count == 25)
    }

    @Test("Same-title editions remain separate and show their folders")
    @MainActor
    func editionFoldersDistinguishCollisions() async throws {
        // Given
        let identifier = try fixtureIdentifier()
        let firstAlbumID = UUID()
        let secondAlbumID = UUID()
        let firstTrackID = UUID()
        let secondTrackID = UUID()
        let tracks = [
            LibraryTrackSnapshot(
                id: firstTrackID,
                persistentIdentifier: identifier,
                title: "First",
                artist: "Artist",
                album: "Heavensward Vinyl LP",
                path: "/Music/Heavensward Vinyl LP [16-bit]/01.flac",
                albumID: firstAlbumID
            ),
            LibraryTrackSnapshot(
                id: secondTrackID,
                persistentIdentifier: identifier,
                title: "Second",
                artist: "Artist",
                album: "Heavensward Vinyl LP",
                path: "/Music/Heavensward Vinyl LP [24-bit]/01.flac",
                albumID: secondAlbumID
            ),
        ]
        let albums = [
            LibraryAlbumSnapshot(
                id: firstAlbumID,
                persistentIdentifier: identifier,
                title: "Heavensward Vinyl LP",
                artist: "Artist",
                trackIDs: [firstTrackID]
            ),
            LibraryAlbumSnapshot(
                id: secondAlbumID,
                persistentIdentifier: identifier,
                title: "Heavensward Vinyl LP",
                artist: "Artist",
                trackIDs: [secondTrackID]
            ),
        ]
        let snapshot = LibrarySnapshot(revision: 1, tracks: tracks, albums: albums, playlists: [])

        // When
        let groups = try await LibraryAlbumProjectionWorker().project(snapshot)
        let projection = try await TrackTableProjectionWorker().project(
            snapshot: snapshot,
            request: TrackTableRequest(collection: .allTracks),
            albumGroups: groups
        )

        // Then
        #expect(groups.count == 2)
        #expect(Set(projection.facets.albums.compactMap(\.detail)) == Set([
            "Heavensward Vinyl LP [16-bit]",
            "Heavensward Vinyl LP [24-bit]",
        ]))
    }

    @Test("Same-folder compilation records merge without losing favorite or artwork")
    @MainActor
    func sameFolderRecordsMerge() throws {
        // Given
        let container = try makeContainer()
        let context = container.mainContext
        let firstAlbum = Album(title: "Evangelion Finally", artist: "Performer One")
        firstAlbum.artworkData = Data([1, 2, 3])
        let secondAlbum = Album(title: "Evangelion Finally", artist: "Performer Two")
        let first = Track(
            path: "/Music/Evangelion Finally/01.flac",
            title: "One",
            artist: "Performer One",
            album: "Evangelion Finally"
        )
        first.albumArtist = ""
        first.albumRelation = firstAlbum
        let second = Track(
            path: "/Music/Evangelion Finally/02.flac",
            title: "Two",
            artist: "Performer Two",
            album: "Evangelion Finally"
        )
        second.albumArtist = ""
        second.albumRelation = secondAlbum
        context.insert(firstAlbum)
        context.insert(secondAlbum)
        context.insert(first)
        context.insert(second)
        context.insert(AlbumFavorite(albumID: secondAlbum.id))
        try context.save()

        // When
        let outcome = try AlbumRelationshipReconciler.reconcile(in: context)
        try context.save()
        let storedAlbums = try context.fetch(FetchDescriptor<Album>())
        let favorites = try context.fetch(FetchDescriptor<AlbumFavorite>())

        // Then
        #expect(storedAlbums.count == 1)
        #expect(first.albumRelation?.id == second.albumRelation?.id)
        #expect(storedAlbums.first?.artist == "Various Artists")
        #expect(storedAlbums.first?.artworkData == Data([1, 2, 3]))
        #expect(favorites.map(\.albumID) == storedAlbums.map(\.id))
        #expect(outcome.reassignedTracks > 0)
    }

    @Test("One cross-folder record splits and propagates its favorite")
    @MainActor
    func crossFolderRecordSplits() throws {
        // Given
        let container = try makeContainer()
        let context = container.mainContext
        let album = Album(title: "Same Release", artist: "Artist")
        let sixteen = Track(
            path: "/Music/Same Release [16-bit]/01.flac",
            title: "Sixteen",
            artist: "Artist",
            album: "Same Release"
        )
        let twentyFour = Track(
            path: "/Music/Same Release [24-bit]/01.flac",
            title: "Twenty Four",
            artist: "Artist",
            album: "Same Release"
        )
        sixteen.albumRelation = album
        twentyFour.albumRelation = album
        context.insert(album)
        context.insert(sixteen)
        context.insert(twentyFour)
        context.insert(AlbumFavorite(albumID: album.id))
        try context.save()

        // When
        let outcome = try AlbumRelationshipReconciler.reconcile(in: context)
        try context.save()
        let storedAlbums = try context.fetch(FetchDescriptor<Album>())
        let favorites = try context.fetch(FetchDescriptor<AlbumFavorite>())

        // Then
        #expect(outcome.splitAlbums == 1)
        #expect(storedAlbums.count == 2)
        #expect(sixteen.albumRelation?.id != twentyFour.albumRelation?.id)
        #expect(storedAlbums.contains { $0.id == album.id })
        #expect(Set(favorites.map(\.albumID)) == Set(storedAlbums.map(\.id)))
    }

    @Test("Unknown albums by different performers do not merge")
    @MainActor
    func unknownAlbumsStaySeparate() throws {
        // Given
        let container = try makeContainer()
        let context = container.mainContext
        let firstAlbum = Album(title: "Unknown Album", artist: "Artist One")
        let secondAlbum = Album(title: "Unknown Album", artist: "Artist Two")
        let first = Track(path: "/Music/Loose/01.flac", title: "One", artist: "Artist One")
        let second = Track(path: "/Music/Loose/02.flac", title: "Two", artist: "Artist Two")
        first.albumRelation = firstAlbum
        second.albumRelation = secondAlbum
        context.insert(firstAlbum)
        context.insert(secondAlbum)
        context.insert(first)
        context.insert(second)
        try context.save()

        // When
        _ = try AlbumRelationshipReconciler.reconcile(in: context)
        try context.save()

        // Then
        #expect(first.albumRelation?.id != second.albumRelation?.id)
        #expect(try context.fetch(FetchDescriptor<Album>()).count == 2)
    }

    @MainActor
    private func fixtureIdentifier() throws -> PersistentIdentifier {
        let container = try makeContainer()
        let track = Track(path: "/tmp/album-identity-fixture.flac", title: "Fixture")
        container.mainContext.insert(track)
        try container.mainContext.save()
        return track.persistentModelID
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self, AlbumFavorite.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
