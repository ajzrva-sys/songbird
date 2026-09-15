import SwiftData
import XCTest
@testable import SongbirdLib

final class AlbumFavoriteMigrationTests: XCTestCase {
    func testV2StoreMigratesToV4WithoutLosingAlbums() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-v4-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appendingPathComponent("library.store")
        let albumID = UUID()

        do {
            let v2Schema = Schema(versionedSchema: SongbirdSchemaV2.self)
            let configuration = ModelConfiguration(
                schema: v2Schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: v2Schema, configurations: [configuration])
            let context = ModelContext(container)
            let album = Album(title: "Migration Album", artist: "Artist", year: 1999)
            album.id = albumID
            context.insert(album)
            try context.save()
        }

        let v4Schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let configuration = ModelConfiguration(
            schema: v4Schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: v4Schema,
            migrationPlan: SongbirdMigrationPlan.self,
            configurations: configuration
        )
        let context = ModelContext(container)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Album>()).map(\.id), [albumID])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AlbumFavorite>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrackFavorite>()), 0)

        context.insert(AlbumFavorite(albumID: albumID))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<AlbumFavorite>()).first?.albumID, albumID)
    }
}
