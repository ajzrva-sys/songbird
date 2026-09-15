import AVFoundation
import Foundation

public struct DiscIdentifier: Hashable, Sendable, Identifiable {
    public let rawValue: String
    public var id: String { rawValue }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct AudioCDSource: Hashable, Sendable {
    public let discID: DiscIdentifier
    public let deviceID: String
    public let trackNumber: Int
    public let startSector: Int64
    public let endSector: Int64

    public init(
        discID: DiscIdentifier,
        deviceID: String,
        trackNumber: Int,
        startSector: Int64,
        endSector: Int64
    ) {
        self.discID = discID
        self.deviceID = deviceID
        self.trackNumber = trackNumber
        self.startSector = startSector
        self.endSector = endSector
    }

    public var duration: TimeInterval {
        TimeInterval(max(0, endSector - startSector)) / 75
    }
}

public enum DiscStatus: String, Sendable {
    case loading
    case ready
    case importing
    case ejecting
    case removed
    case unreadable
}

public struct AudioDiscTrack: Identifiable, Hashable, Sendable {
    public let id: String
    public let discID: DiscIdentifier
    public let number: Int
    public let title: String
    public let artist: String
    public let duration: TimeInterval
    public let startSector: Int64
    public let endSector: Int64
    public let source: AudioCDSource
    public let fileURL: URL?

    public init(
        discID: DiscIdentifier,
        number: Int,
        title: String,
        artist: String = "Unknown Artist",
        duration: TimeInterval,
        startSector: Int64,
        endSector: Int64,
        source: AudioCDSource,
        fileURL: URL? = nil
    ) {
        self.id = "\(discID.rawValue)-\(number)"
        self.discID = discID
        self.number = number
        self.title = title
        self.artist = artist
        self.duration = duration
        self.startSector = startSector
        self.endSector = endSector
        self.source = source
        self.fileURL = fileURL
    }
}

/// Runtime-only, provider-independent CD-Text/default strings. Safe for conservative fallback.
public struct AudioCDTrackMetadata: Hashable, Sendable {
    public let title: String
    public let artist: String
    public let album: String

    public init(title: String, artist: String, album: String) {
        self.title = title
        self.artist = artist
        self.album = album
    }

    public static func defaultMetadata(trackNumber: Int) -> Self {
        .init(title: String(format: "Track %02d", trackNumber),
              artist: "Unknown Artist", album: "Audio CD")
    }
}

/// Captured before any provider overlays metadata. Contains no device or playback identity.
public struct AudioDiscOriginalMetadata: Hashable, Sendable {
    public let title: String
    public let albumArtist: String?
    public let year: Int?
    public let tracks: [Int: AudioCDTrackMetadata]

    public init(title: String, albumArtist: String?, year: Int?, tracks: [Int: AudioCDTrackMetadata]) {
        self.title = title
        self.albumArtist = albumArtist
        self.year = year
        self.tracks = tracks
    }

    public func trackMetadata(for number: Int) -> AudioCDTrackMetadata {
        tracks[number] ?? .defaultMetadata(trackNumber: number)
    }
}

public struct AudioDisc: Identifiable, Hashable, Sendable {
    public let id: DiscIdentifier
    public let title: String
    public let albumArtist: String?
    public let year: Int?
    public let volumeURL: URL
    public let tracks: [AudioDiscTrack]
    public let artworkURL: URL?
    public let discogsEvidence: DiscogsContentEvidence?
    public let originalMetadata: AudioDiscOriginalMetadata
    public var status: DiscStatus

    public init(
        id: DiscIdentifier,
        title: String,
        albumArtist: String? = nil,
        year: Int? = nil,
        volumeURL: URL,
        tracks: [AudioDiscTrack],
        artworkURL: URL? = nil,
        status: DiscStatus = .ready,
        discogsEvidence: DiscogsContentEvidence? = nil,
        originalMetadata: AudioDiscOriginalMetadata? = nil
    ) {
        self.id = id
        self.title = title
        self.albumArtist = albumArtist
        self.year = year
        self.volumeURL = volumeURL
        self.tracks = tracks
        self.artworkURL = artworkURL
        self.status = status
        self.discogsEvidence = discogsEvidence
        // Never bless a remote title as original when a caller lacks fallback data.
        self.originalMetadata = originalMetadata ?? AudioDiscOriginalMetadata(
            title: discogsEvidence == nil ? title : "Audio CD",
            albumArtist: discogsEvidence == nil ? albumArtist : nil,
            year: discogsEvidence == nil ? year : nil,
            tracks: Dictionary(tracks.map { track in
                (track.number, discogsEvidence == nil
                    ? AudioCDTrackMetadata(title: track.title, artist: track.artist, album: title)
                    : .defaultMetadata(trackNumber: track.number))
            }, uniquingKeysWith: { first, _ in first })
        )
    }

    public func restoringOriginalMetadata() -> AudioDisc {
        let restoredTracks = tracks.map { track in
            let metadata = originalMetadata.trackMetadata(for: track.number)
            return AudioDiscTrack(discID: track.discID, number: track.number,
                title: metadata.title, artist: metadata.artist, duration: track.duration,
                startSector: track.startSector, endSector: track.endSector,
                source: track.source, fileURL: track.fileURL)
        }
        return AudioDisc(id: id, title: originalMetadata.title, albumArtist: originalMetadata.albumArtist,
            year: originalMetadata.year, volumeURL: volumeURL, tracks: restoredTracks,
            artworkURL: nil, status: status, discogsEvidence: nil, originalMetadata: originalMetadata)
    }
}

/// Pure TOC math shared by physical-media discovery and tests.
public enum AudioCDTOCParser {
    public struct Entry: Equatable, Sendable {
        public let number: Int
        public let startSector: Int64
        public let isData: Bool

        public init(number: Int, startSector: Int64, isData: Bool = false) {
            self.number = number
            self.startSector = startSector
            self.isData = isData
        }
    }

    public struct ParsedTrack: Equatable, Sendable {
        public let number: Int
        public let startSector: Int64
        public let endSector: Int64
        public var duration: TimeInterval {
            TimeInterval(endSector - startSector) / 75
        }
    }

    public static func parse(entries: [Entry], leadOutSector: Int64) -> [ParsedTrack] {
        let ordered = entries
            .filter { $0.number > 0 && $0.number < 100 }
            .sorted { $0.startSector < $1.startSector }
        guard leadOutSector > 0 else { return [] }

        return ordered.enumerated().compactMap { index, entry in
            guard !entry.isData else { return nil }
            let nextSector = index + 1 < ordered.count
                ? ordered[index + 1].startSector
                : leadOutSector
            guard entry.startSector >= 0, nextSector > entry.startSector else { return nil }
            return ParsedTrack(
                number: entry.number,
                startSector: entry.startSector,
                endSector: nextSector
            )
        }
    }
}

public extension Track {
    static let audioCDMarker = "Songbird Audio CD"

    var isAudioCDTrack: Bool {
        audioCDSource != nil || comment == Self.audioCDMarker
    }

    var audioDiscID: DiscIdentifier? { audioCDSource?.discID }

    /// Value-only selection: the owning surface supplies one sample and owns invalidation.
    func audioCDMetadata(at now: DiscogsFetchStamp?) -> AudioCDTrackMetadata {
        if let evidence = audioCDDiscogsEvidence, !evidence.isFresh(at: now) {
            return audioCDOriginalMetadata ?? .defaultMetadata(trackNumber: trackNumber)
        }
        return AudioCDTrackMetadata(title: title, artist: artist, album: album)
    }

    static func transientAudioCDTrack(
        _ track: AudioDiscTrack,
        album: String,
        artworkURL: URL? = nil,
        discogsEvidence: DiscogsContentEvidence? = nil,
        originalMetadata: AudioCDTrackMetadata? = nil
    ) -> Track {
        let item = Track(
            path: "songbird-cd://\(track.discID.rawValue)/\(track.number)",
            title: track.title,
            artist: track.artist,
            album: album
        )
        item.trackNumber = track.number
        item.duration = track.duration
        item.sampleRate = 44_100
        item.bitrate = 1_411
        item.comment = audioCDMarker
        item.audioCDSource = track.source
        item.audioCDArtworkURL = artworkURL
        item.audioCDDiscogsEvidence = discogsEvidence
        item.audioCDOriginalMetadata = originalMetadata ?? (discogsEvidence == nil
            ? AudioCDTrackMetadata(title: track.title, artist: track.artist, album: album)
            : .defaultMetadata(trackNumber: track.number))
        return item
    }
}
