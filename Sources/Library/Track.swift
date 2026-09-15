import Foundation
import SwiftData
import CryptoKit

@Model
public final class Track {
    public var id: UUID
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var genre: String = ""
    public var composer: String = ""
    public var comment: String = ""
    public var year: Int = 0
    public var trackNumber: Int = 0
    public var trackTotal: Int = 0
    public var discNumber: Int = 0
    public var discTotal: Int = 0
    public var beatsPerMinute: Int = 0
    public var duration: TimeInterval = 0
    public var fileSize: Int64 = 0
    @Attribute(.unique) public var path: String = ""
    public var dateAdded: Date = Date()
    public var dateModified: Date = Date()
    public var lastPlayed: Date?
    public var playCount: Int = 0
    /// Favorite state stored as 0 (off) or 5 (on) for schema compatibility.
    public var rating: Int = 0
    public var bitrate: Int = 0
    public var sampleRate: Int = 0
    /// Reserved schema slot; artwork is stored canonically on `Album`.
    public var artworkData: Data?
    public var checksum: String = ""
    /// Runtime-only source information for tracks backed by removable media.
    @Transient public var audioCDSource: AudioCDSource?
    /// Runtime-only cover location supplied by optical-disc metadata.
    @Transient public var audioCDArtworkURL: URL?
    /// Runtime-only acquisitions and CD-Text/default fallback; never persisted or backfilled.
    @Transient public var audioCDDiscogsEvidence: DiscogsContentEvidence?
    @Transient public var audioCDOriginalMetadata: AudioCDTrackMetadata?

    @Relationship(inverse: \Album.tracks)
    var albumRelation: Album?

    @Relationship(inverse: \Artist.tracks)
    var artistRelation: Artist?

    public var fileKind: String {
        (path as NSString).pathExtension.uppercased()
    }

    /// Canonical artwork for display and system now-playing metadata.
    public var resolvedArtworkData: Data? {
        albumRelation?.artworkData
    }

    public init(path: String, title: String = "", artist: String = "Unknown Artist",
         album: String = "Unknown Album") {
        self.id = UUID()
        self.path = Self.standardizedPath(path)
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = artist
        self.genre = ""
        self.composer = ""
        self.comment = ""
        self.year = 0
        self.trackNumber = 0
        self.trackTotal = 0
        self.discNumber = 0
        self.discTotal = 0
        self.beatsPerMinute = 0
        self.duration = 0
        self.fileSize = 0
        self.dateAdded = Date()
        self.dateModified = Date()
        self.playCount = 0
        self.rating = 0
        self.bitrate = 0
        self.sampleRate = 0
        self.checksum = ""
        self.audioCDSource = nil
        self.audioCDArtworkURL = nil
    }

    public static func standardizedPath(_ path: String) -> String {
        // Clean syntactic components without normalizing Unicode. The value in
        // SwiftData must retain the exact spelling returned by the filesystem.
        (path as NSString).standardizingPath
    }

    public static func fileSignature(at path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64,
              let mtime = attrs[.modificationDate] as? Date else {
            return ""
        }
        return "\(size)-\(Int(mtime.timeIntervalSince1970))"
    }

    public static func contentChecksum(at path: String) -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else { return fileSignature(at: path) }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunk = 64 * 1024
        // Hash first + last chunk for speed on large files.
        if let head = try? handle.read(upToCount: chunk) {
            hasher.update(data: head)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        if size > Int64(chunk) {
            try? handle.seek(toOffset: UInt64(max(0, size - Int64(chunk))))
            if let tail = try? handle.read(upToCount: chunk) {
                hasher.update(data: tail)
            }
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined() + "-\(size)"
    }
}
