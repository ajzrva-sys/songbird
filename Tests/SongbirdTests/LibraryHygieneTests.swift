import XCTest
import SwiftData
@testable import SongbirdLib

@MainActor
final class LibraryHygieneTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self, AlbumFavorite.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    func testRemoveMissingTracks() throws {
        let context = ModelContext(container)
        let missing = Track(path: "/definitely/missing-\(UUID().uuidString).mp3", title: "Gone")
        context.insert(missing)
        try context.save()
        let removed = LibraryHygiene.removeMissingTracks(in: context)
        XCTAssertEqual(removed, 1)
    }

    func testDuplicateGroupsAndRemove() throws {
        let context = ModelContext(container)
        let a = Track(path: "/a.mp3", title: "A")
        let b = Track(path: "/b.mp3", title: "B")
        a.checksum = "same-hash"
        b.checksum = "same-hash"
        context.insert(a)
        context.insert(b)
        try context.save()
        XCTAssertEqual(LibraryHygiene.duplicateGroups(in: context).count, 1)
        let removed = LibraryHygiene.removeDuplicateTracks(in: context)
        XCTAssertEqual(removed, 1)
        let remaining = try context.fetch(FetchDescriptor<Track>())
        XCTAssertEqual(remaining.count, 1)
    }

    func testOrphanAlbumArtistCleanup() throws {
        let context = ModelContext(container)
        let album = Album(title: "Empty", artist: "Nobody")
        let artist = Artist(name: "Nobody")
        context.insert(album)
        context.insert(artist)
        try context.save()
        let result = LibraryHygiene.removeOrphanAlbumsAndArtists(in: context)
        XCTAssertEqual(result.albums, 1)
        XCTAssertEqual(result.artists, 1)
    }

    func testOrphanCleanupRemovesFavoriteForAlbumDeletedInSamePass() throws {
        let context = ModelContext(container)
        let album = Album(title: "Empty", artist: "Nobody")
        context.insert(album)
        context.insert(AlbumFavorite(albumID: album.id))
        try context.save()

        let result = LibraryHygiene.removeOrphanAlbumsAndArtists(in: context)

        XCTAssertEqual(result.albums, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AlbumFavorite>()), 0)
    }

    func testMaintenancePreviewsCountWithoutMutating() async throws {
        let context = ModelContext(container)
        let missing = Track(path: "/definitely/missing-preview-\(UUID().uuidString).mp3")
        let album = Album(title: "Empty", artist: "Nobody")
        let artist = Artist(name: "Nobody")
        context.insert(missing)
        context.insert(album)
        context.insert(artist)
        try context.save()
        let service = LibraryMaintenanceService(modelContainer: container)

        let missingPreview = try await service.previewMissingTracks()
        let orphanPreview = try await service.previewOrphanAlbumsAndArtists()

        XCTAssertEqual(missingPreview.missingTracks, 1)
        XCTAssertEqual(orphanPreview.emptyAlbums, 1)
        XCTAssertEqual(orphanPreview.emptyArtists, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Track>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Album>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Artist>()), 1)
    }

    func testMaintenancePreservesCanonicallyEquivalentExistingTrack() async throws {
        let stored = "/Volumes/music/Yelle/02 A cause des garc\u{0327}ons.m4a"
        let actual = "/Volumes/music/Yelle/02 A cause des gar\u{00E7}ons.m4a"
        let context = ModelContext(container)
        context.insert(Track(path: stored, title: "Existing"))
        try context.save()
        let service = LibraryMaintenanceService(
            modelContainer: container,
            pathResolver: fakeResolver(existingPaths: [actual])
        )

        let preview = try await service.previewMissingTracks()
        let removed = try await service.removeMissingTracks()

        XCTAssertEqual(preview.missingTracks, 0)
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Track>()), 1)
    }

    func testMaintenanceNeverCountsOrRemovesUnavailableTrackAsMissing() async throws {
        let path = "/Volumes/music/Artist/Offline.m4a"
        let context = ModelContext(container)
        context.insert(Track(path: path, title: "Unavailable"))
        try context.save()
        let resolver = FilesystemPathResolver(
            probe: { candidate in
                if candidate == "/" || candidate == "/Volumes" { return .exists }
                return .missing
            },
            directoryContents: { url in
                .success(url.path == "/" ? [Self.filesystemURL(for: "/Volumes")] : [])
            }
        )
        let service = LibraryMaintenanceService(
            modelContainer: container,
            pathResolver: resolver
        )

        let preview = try await service.previewMissingTracks()
        let removed = try await service.removeMissingTracks()

        XCTAssertEqual(preview.missingTracks, 0)
        XCTAssertEqual(preview.unavailableTracks, 1)
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Track>()), 1)
    }

    private func fakeResolver(existingPaths: [String]) -> FilesystemPathResolver {
        let existingKeys = Set(existingPaths.map(Self.scalarKey))
        var listings: [String: [URL]] = [:]

        for path in existingPaths {
            let components = (path as NSString).pathComponents
            var parentPath = "/"
            for component in components.dropFirst() {
                let childPath = (parentPath as NSString).appendingPathComponent(component)
                let child = Self.filesystemURL(for: childPath)
                let parentKey = Self.scalarKey(parentPath)
                if listings[parentKey, default: []].contains(where: {
                    Self.scalarKey($0.path) == Self.scalarKey(child.path)
                }) == false {
                    listings[parentKey, default: []].append(child)
                }
                parentPath = childPath
            }
        }
        let immutableListings = listings

        return FilesystemPathResolver(
            fileExists: { path in
                let key = Self.scalarKey(path)
                if existingKeys.contains(key) { return true }
                return existingKeys.contains { $0.hasPrefix(key + "|") }
            },
            directoryContents: { immutableListings[Self.scalarKey($0.path)] }
        )
    }

    nonisolated private static func scalarKey(_ value: String) -> String {
        value.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "|")
    }

    nonisolated private static func filesystemURL(for path: String) -> URL {
        path.withCString {
            URL(
                fileURLWithFileSystemRepresentation: $0,
                isDirectory: false,
                relativeTo: nil
            )
        }
    }
}
