import Foundation

public struct PlaybackStartRequest {
    public let tracks: [Track]
    public let startingAt: Int
    public let randomizesTracks: Bool

    public init(
        tracks: [Track],
        startingAt: Int = 0,
        randomizesTracks: Bool = false
    ) {
        self.tracks = tracks
        self.startingAt = startingAt
        self.randomizesTracks = randomizesTracks
    }
}

public enum PlaybackStartError: Error, LocalizedError, Equatable {
    case emptySelection
    case fileNotFound(String)
    case volumeUnavailable(String)
    case cancelled
    case backendRejected(String)

    public var errorDescription: String? {
        switch self {
        case .emptySelection:
            "No playable tracks were selected."
        case .fileNotFound(let path):
            "File not found: \(path)"
        case .volumeUnavailable(let message):
            message
        case .cancelled:
            "Playback request was superseded."
        case .backendRejected(let message):
            message
        }
    }
}
