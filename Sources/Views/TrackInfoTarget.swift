import Foundation
import SwiftData

enum TrackInfoTargetResolutionError: LocalizedError, Equatable {
    case missingTracks

    var errorDescription: String? {
        "Some selected tracks are no longer in the library. Reopen Edit Metadata and try again."
    }
}

/// Value-only metadata safe to retain for the lifetime of an Edit Metadata window.
struct TrackInfoTarget: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let albumArtist: String
    let genre: String
    let composer: String
    let comment: String
    let year: Int
    let trackNumber: Int
    let trackTotal: Int
    let discNumber: Int
    let discTotal: Int
    let beatsPerMinute: Int
    let rating: Int
    let isLoved: Bool
    let bitrate: Int
    let sampleRate: Int
    let fileKind: String
    let artworkData: Data?
    let albumID: UUID?

    @MainActor
    init(track: Track) {
        self.init(track: track, isLoved: false)
    }

    @MainActor
    init(track: Track, isLoved: Bool) {
        id = track.id
        title = track.title
        artist = track.artist
        album = track.album
        albumArtist = track.albumArtist
        genre = track.genre
        composer = track.composer
        comment = track.comment
        year = track.year
        trackNumber = track.trackNumber
        trackTotal = track.trackTotal
        discNumber = track.discNumber
        discTotal = track.discTotal
        beatsPerMinute = track.beatsPerMinute
        rating = track.rating
        self.isLoved = isLoved
        bitrate = track.bitrate
        sampleRate = track.sampleRate
        fileKind = track.fileKind
        artworkData = track.resolvedArtworkData
        albumID = track.albumRelation?.id
    }

    @MainActor
    static func resolve(
        _ targets: [TrackInfoTarget],
        in context: ModelContext
    ) throws -> [Track] {
        var seen = Set<UUID>()
        let orderedTargets = targets.filter { seen.insert($0.id).inserted }
        let targetIDs = orderedTargets.map(\.id)
        guard targetIDs.isEmpty == false else { return [] }

        let descriptor = FetchDescriptor<Track>(
            predicate: #Predicate { track in targetIDs.contains(track.id) }
        )
        let tracks = try context.fetch(descriptor)
        let tracksByID = Dictionary(
            tracks.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        return orderedTargets.compactMap { tracksByID[$0.id] }
    }

    @MainActor
    static func resolveAll(
        _ targets: [TrackInfoTarget],
        in context: ModelContext
    ) throws -> [Track] {
        let tracks = try resolve(targets, in: context)
        guard tracks.count == Set(targets.map(\.id)).count else {
            throw TrackInfoTargetResolutionError.missingTracks
        }
        return tracks
    }
}
