import Foundation

public struct LibraryFileTagRepairRequest: Sendable {
    public let trackID: UUID
    public let path: String
    public let change: LibraryRemediationChange

    public init(trackID: UUID, path: String, change: LibraryRemediationChange) {
        self.trackID = trackID
        self.path = path
        self.change = change
    }
}

public enum LibraryFileTagRepairStatus: Equatable, Sendable {
    case written
    case alreadyPresent
    case conflict
    case failed(String)
}

public struct LibraryFileTagRepairResult: Sendable {
    public let request: LibraryFileTagRepairRequest
    public let status: LibraryFileTagRepairStatus
}

public struct LibraryFileTagRepairSummary: Sendable {
    public let results: [LibraryFileTagRepairResult]
    public var catalogError: String? = nil
    public var canceled = false
    public var written: Int { results.filter { $0.status == .written }.count }
    public var alreadyPresent: Int { results.filter { $0.status == .alreadyPresent }.count }
    public var conflicts: Int { results.filter { $0.status == .conflict }.count }
    public var failed: Int { results.filter { if case .failed = $0.status { true } else { false } }.count }
}

public struct LibraryFileTagRecoverySummary: Sendable {
    public let recovered: Int
    public let checked: Int
    public let missing: Int
    public let unavailable: Int
    public let failed: Int
    public let canceled: Bool
    public let saveError: String?
}

public struct LibraryFileArtworkRequest: Sendable {
    public let trackID: UUID
    public let albumID: UUID
    public let path: String
    public let artworkData: Data

    public init(trackID: UUID, albumID: UUID, path: String, artworkData: Data) {
        self.trackID = trackID
        self.albumID = albumID
        self.path = path
        self.artworkData = artworkData
    }
}

public struct LibraryFileArtworkResult: Sendable {
    public let request: LibraryFileArtworkRequest
    public let status: LibraryFileTagRepairStatus
}

public struct LibraryFileArtworkSummary: Sendable {
    public let results: [LibraryFileArtworkResult]
    public var canceled = false
    public var scopeError: String? = nil
    public var written: Int { results.filter { $0.status == .written }.count }
    public var preserved: Int { results.filter { $0.status == .alreadyPresent }.count }
    public var conflicts: Int { results.filter { $0.status == .conflict }.count }
    public var failed: Int { results.filter { if case .failed = $0.status { true } else { false } }.count }
}

/// Disk work stays off the main actor. Each replacement is verified while the
/// original remains intact; existing nonempty file tags are never overwritten.
public actor LibraryFileTagRepairService {
    typealias Reader = @Sendable (URL) async -> AudioMetadata?
    typealias Writer = @Sendable (String, [TrackMetadataField: TrackMetadataValue]) async throws -> Void
    typealias ArtworkWriter = @Sendable (String, Data) async throws -> Void
    private let reader: Reader
    private let writer: Writer
    private let artworkWriter: ArtworkWriter

    public init() {
        reader = { await MetadataReader.read(from: $0, detectMissingBPM: false, requireCompleteMetadata: true) }
        writer = { try await TagWriterService.writeTags(path: $0, fields: $1) }
        artworkWriter = { try await TagWriterService.writeTags(path: $0, fields: [:], artworkData: $1) }
    }

    init(reader: @escaping Reader, writer: @escaping Writer,
         artworkWriter: @escaping ArtworkWriter = {
             try await TagWriterService.writeTags(path: $0, fields: [:], artworkData: $1)
         }) {
        self.reader = reader
        self.writer = writer
        self.artworkWriter = artworkWriter
    }

    public func applyArtwork(
        _ requests: [LibraryFileArtworkRequest],
        isCanceled: @Sendable () async -> Bool = { false },
        catalogIsCurrent: @Sendable (LibraryFileArtworkRequest) async -> Bool = { _ in true },
        progress: @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async -> LibraryFileArtworkSummary {
        let grouped = Dictionary(grouping: requests, by: \.path)
        let paths = grouped.keys.sorted()
        var results: [LibraryFileArtworkResult] = []
        for path in paths {
            guard !Task.isCancelled, !(await isCanceled()),
                  let request = grouped[path]?.first else { break }
            let status: LibraryFileTagRepairStatus
            do {
                if grouped[path]!.contains(where: { $0.artworkData != request.artworkData }) {
                    status = .conflict
                } else {
                    status = try await repairArtwork(request, isCanceled: isCanceled, catalogIsCurrent: catalogIsCurrent)
                }
            } catch is CancellationError { break }
            catch { status = .failed(error.localizedDescription) }
            results.append(LibraryFileArtworkResult(request: request, status: status))
            await progress(results.count, paths.count)
        }
        return LibraryFileArtworkSummary(results: results, canceled: results.count < paths.count)
    }

    private func repairArtwork(
        _ request: LibraryFileArtworkRequest,
        isCanceled: @Sendable () async -> Bool,
        catalogIsCurrent: @Sendable (LibraryFileArtworkRequest) async -> Bool
    ) async throws -> LibraryFileTagRepairStatus {
        guard await catalogIsCurrent(request) else { return .conflict }
        let url = URL(fileURLWithPath: request.path)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let properties = try url.resourceValues(forKeys: keys)
        guard properties.isRegularFile == true, properties.isSymbolicLink != true,
              properties.fileSize != nil, properties.contentModificationDate != nil,
              let before = await reader(url), before.duration > 0, before.sampleRate > 0 else {
            throw RepairError.unreadable
        }
        // Retain even undecodable AV picture tags and empty FLAC PICTURE blocks.
        let hasFLACPicture = url.pathExtension.lowercased() == "flac" ? try Self.hasFLACPictureBlock(url) : false
        if before.artworkData != nil || before.embeddedArtworkPresent || hasFLACPicture { return .alreadyPresent }
        let signature = [UInt8](request.artworkData.prefix(4))
        guard ArtworkStorage.pixelSize(of: request.artworkData) != nil,
              signature.starts(with: [0xFF, 0xD8]) || signature == [0x89, 0x50, 0x4E, 0x47] else {
            throw RepairError.artwork
        }
        try Task.checkCancellation()
        guard !(await isCanceled()) else { throw CancellationError() }
        let folder = url.deletingLastPathComponent().appendingPathComponent(".songbird-artwork-repair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let candidate = folder.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: candidate)
        try await artworkWriter(candidate.path, request.artworkData)
        guard let after = await reader(candidate), after.tagValues == before.tagValues,
              after.artworkData == request.artworkData,
              after.sampleRate == before.sampleRate,
              abs(after.duration - before.duration) < 0.001 else { throw RepairError.verification }
        try Task.checkCancellation()
        guard !(await isCanceled()) else { throw CancellationError() }
        guard await catalogIsCurrent(request) else { return .conflict }
        try Task.checkCancellation()
        guard !(await isCanceled()) else { throw CancellationError() }
        var liveURL = URL(fileURLWithPath: request.path)
        liveURL.removeAllCachedResourceValues()
        let live = try liveURL.resourceValues(forKeys: keys)
        guard live.isRegularFile == true, live.isSymbolicLink != true,
              live.fileSize == properties.fileSize,
              live.contentModificationDate == properties.contentModificationDate else { throw RepairError.changed }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: candidate)
        return .written
    }

    /// Headers suffice to detect any existing picture without loading its payload.
    private static func hasFLACPictureBlock(_ url: URL) throws -> Bool {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard try file.read(upToCount: 4) == Data("fLaC".utf8) else { throw RepairError.unreadable }
        let end = try file.seekToEnd()
        try file.seek(toOffset: 4)
        while true {
            guard let header = try file.read(upToCount: 4), header.count == 4 else { throw RepairError.unreadable }
            let bytes = [UInt8](header)
            if bytes[0] & 0x7F == 6 { return true }
            let length = UInt64(bytes[1]) << 16 | UInt64(bytes[2]) << 8 | UInt64(bytes[3])
            let next = try file.offset() + length
            guard next <= end else { throw RepairError.unreadable }
            if bytes[0] & 0x80 != 0 { return false }
            try file.seek(toOffset: next)
        }
    }

    public func apply(
        _ requests: [LibraryFileTagRepairRequest],
        isCanceled: @Sendable () async -> Bool = { false },
        progress: @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async -> LibraryFileTagRepairSummary {
        var results: [LibraryFileTagRepairResult] = []
        for request in requests {
            let canceled = await isCanceled()
            guard !Task.isCancelled, !canceled else { break }
            let status: LibraryFileTagRepairStatus
            do { status = try await repair(request) }
            catch { status = .failed(error.localizedDescription) }
            results.append(LibraryFileTagRepairResult(request: request, status: status))
            await progress(results.count, requests.count)
        }
        return LibraryFileTagRepairSummary(results: results, canceled: results.count < requests.count)
    }

    private func repair(_ request: LibraryFileTagRepairRequest) async throws -> LibraryFileTagRepairStatus {
        guard request.trackID == request.change.target.trackID else { throw RepairError.unreadable }
        let url = URL(fileURLWithPath: request.path)
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true,
              properties.fileSize != nil, properties.contentModificationDate != nil,
              let field = Self.metadataField(request.change.target.field),
              let proposed = Self.proposedValue(request.change, field: field),
              let before = await reader(url), before.duration > 0, before.sampleRate > 0 else {
            throw RepairError.unreadable
        }
        let current = before.tagValues[field]
        if current == proposed { return .alreadyPresent }
        guard Self.isMissing(current, field: field) else { return .conflict }
        try Task.checkCancellation()

        // Preserve the original filename so an untagged title fallback remains stable.
        let folder = url.deletingLastPathComponent().appendingPathComponent(".songbird-tag-repair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let candidate = folder.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: candidate)
        var fields = [field: proposed]
        // The writer packs number + total together. Never zero the unchanged half.
        if field == .trackNumber { fields[.trackTotal] = .number(before.trackTotal) }
        if field == .discNumber { fields[.discTotal] = .number(before.discTotal) }
        try await writer(candidate.path, fields)
        guard let after = await reader(candidate) else { throw RepairError.verification }
        var expected = before.tagValues
        expected[field] = proposed
        // The reader derives an unknown album artist from the track artist.
        // Changing that fallback does not create an ALBUMARTIST/aart file tag.
        if field == .artist, before.albumArtist == "Unknown Artist" {
            expected[.albumArtist] = proposed
        }
        guard after.tagValues == expected,
              after.artworkData == before.artworkData,
              after.embeddedArtworkPresent == before.embeddedArtworkPresent,
              after.sampleRate == before.sampleRate,
              abs(after.duration - before.duration) < 0.001 else {
            throw RepairError.verification
        }
        try Task.checkCancellation()
        var liveURL = URL(fileURLWithPath: request.path)
        liveURL.removeAllCachedResourceValues()
        let live = try liveURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard live.fileSize == properties.fileSize,
              live.contentModificationDate == properties.contentModificationDate else {
            throw RepairError.changed
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: candidate)
        return .written
    }

    static func metadataField(_ field: LibraryHealthField) -> TrackMetadataField? {
        switch field {
        case .artist: .artist
        case .album: .album
        case .albumArtist: .albumArtist
        case .genre: .genre
        case .year: .year
        case .trackNumber: .trackNumber
        default: nil
        }
    }

    private static func proposedValue(_ change: LibraryRemediationChange, field: TrackMetadataField) -> TrackMetadataValue? {
        let value = change.proposedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .year, .trackNumber:
            guard let number = Int(value), number > 0 else { return nil }
            guard field == .year ? number <= 9999 : number <= 65535 else { return nil }
            return .number(number)
        case .artist, .albumArtist:
            guard !value.isEmpty, value.caseInsensitiveCompare("Unknown Artist") != .orderedSame else { return nil }
            return .text(value)
        case .album:
            guard !value.isEmpty, value.caseInsensitiveCompare("Unknown Album") != .orderedSame else { return nil }
            return .text(value)
        case .genre:
            let normalized = GenreMetadata.normalized(value)
            return normalized.isEmpty ? nil : .text(normalized)
        case .title:
            return value.isEmpty ? nil : .text(value)
        default: return nil
        }
    }

    private static func isMissing(_ value: TrackMetadataValue?, field: TrackMetadataField) -> Bool {
        switch value {
        case .number(let number): return number <= 0
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return true }
            if field == .artist || field == .albumArtist {
                return trimmed.caseInsensitiveCompare("Unknown Artist") == .orderedSame
            }
            return field == .album && trimmed.caseInsensitiveCompare("Unknown Album") == .orderedSame
        default: return false
        }
    }

    private enum RepairError: LocalizedError {
        case unreadable, verification, changed, artwork
        var errorDescription: String? {
            switch self {
            case .unreadable: "The file or proposed tag could not be read reliably."
            case .verification: "The saved copy did not preserve the expected tags, artwork and audio properties. The original was retained."
            case .changed: "The original file changed during repair. It was retained."
            case .artwork: "The saved library cover is not a readable JPEG or PNG image. The file was retained."
            }
        }
    }
}

extension AudioMetadata {
    var tagValues: [TrackMetadataField: TrackMetadataValue] {
        [.title: .text(title), .artist: .text(artist), .album: .text(album),
         .albumArtist: .text(albumArtist), .genre: .text(genre), .composer: .text(composer),
         .comment: .text(comment), .year: .number(year), .trackNumber: .number(trackNumber),
         .trackTotal: .number(trackTotal), .discNumber: .number(discNumber),
         .discTotal: .number(discTotal), .beatsPerMinute: .number(beatsPerMinute)]
    }
}

actor LibraryFileTagRecoveryWorker {
    func readBatch(paths: [String]) async -> [(String, TrackMetadataRefreshOutcome, AudioMetadata?)] {
        await withTaskGroup(of: (String, TrackMetadataRefreshOutcome, AudioMetadata?).self) { group in
            for path in paths {
                group.addTask {
                    let (outcome, metadata) = await self.read(path: path)
                    return (path, outcome, metadata)
                }
            }
            var results: [(String, TrackMetadataRefreshOutcome, AudioMetadata?)] = []
            for await result in group { results.append(result) }
            return results
        }
    }

    func read(path: String) async -> (TrackMetadataRefreshOutcome, AudioMetadata?) {
        switch await FileAvailabilityWorker().resolve(path: path) {
        case .available(let url):
            guard let metadata = await MetadataReader.read(from: url, detectMissingBPM: false),
                  metadata.duration > 0, metadata.sampleRate > 0 else { return (.unreadable, nil) }
            return (.refreshed, metadata)
        case .missing: return (.fileMissing, nil)
        case .unavailable: return (.fileUnavailable, nil)
        }
    }
}
