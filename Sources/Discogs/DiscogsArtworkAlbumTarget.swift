import Foundation
import SwiftData

/// Value-only album identity and search metadata safe to retain across async artwork work.
struct DiscogsArtworkAlbumTarget: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let artist: String
    let year: Int
    let expectedArtworkDigest: String?

    @MainActor
    init(album: Album) {
        id = album.id
        title = album.title
        artist = album.artist
        year = album.year
        expectedArtworkDigest = LibraryArtworkChange.digest(album.artworkData)
    }

    @MainActor
    func resolve(in context: ModelContext) throws -> Album? {
        let targetID = id
        var descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { album in album.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @MainActor
    static func resolve(
        _ targets: [DiscogsArtworkAlbumTarget],
        in context: ModelContext
    ) throws -> [Album] {
        var seen = Set<UUID>()
        let orderedTargets = targets.filter { seen.insert($0.id).inserted }
        let targetIDs = orderedTargets.map(\.id)
        guard targetIDs.isEmpty == false else { return [] }

        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { album in targetIDs.contains(album.id) }
        )
        let albums = try context.fetch(descriptor)
        let albumsByID = Dictionary(
            albums.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        return orderedTargets.compactMap { albumsByID[$0.id] }
    }
}
