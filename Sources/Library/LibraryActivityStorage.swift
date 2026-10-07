import Foundation

public enum LibraryActivityStorageIssue: String, Equatable, Sendable {
    case corrupt, unavailable, writeFailed
    public var message: String {
        switch self {
        case .corrupt: "Activity history could not be read. The original file is preserved. Clear History to start a new history."
        case .unavailable: "Activity history is unavailable. Current activity remains visible."
        case .writeFailed: "Activity history could not be saved. Current activity remains visible."
        }
    }
}

struct LibraryActivityLoadResult: Sendable {
    var records: [LibraryActivityRecord]
    var issue: LibraryActivityStorageIssue?
}

/// JSON encoding, reads and atomic replacement stay off the main actor.
public actor LibraryActivityStorage {
    public static let maximumBytes = 2 * 1024 * 1024
    public static let maximumTerminalRecords = 500
    public static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60
    private struct Document: Codable { let version: Int; var records: [LibraryActivityRecord] }
    private let url: URL
    private var preservedLoadIssue: LibraryActivityStorageIssue?

    public init(url: URL) {
        // Resolve directory aliases such as macOS /var -> /private/var, but keep
        // the file itself unresolved so an unexpected history symlink is refused.
        self.url = url.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent)
    }

    func load(now: Date) -> LibraryActivityLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .init(records: [], issue: nil)
        }
        do {
            guard url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else {
                preservedLoadIssue = .unavailable
                return .init(records: [], issue: .unavailable)
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= Self.maximumBytes else {
                preservedLoadIssue = .corrupt
                return .init(records: [], issue: .corrupt)
            }
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.version == 1, Self.isValid(document.records) else {
                preservedLoadIssue = .corrupt
                return .init(records: [], issue: .corrupt)
            }
            let recovered = document.records.map { record -> LibraryActivityRecord in
                var result = record
                if !result.status.isTerminal {
                    result.status = .interrupted
                    result.severity = .warning
                    result.updatedAt = now
                    result.finishedAt = now
                }
                return result
            }
            return .init(records: Self.retained(recovered, now: now), issue: nil)
        } catch is DecodingError {
            preservedLoadIssue = .corrupt
            return .init(records: [], issue: .corrupt)
        } catch {
            preservedLoadIssue = .unavailable
            return .init(records: [], issue: .unavailable)
        }
    }

    func save(_ records: [LibraryActivityRecord], now: Date, clearing: Bool = false) -> LibraryActivityStorageIssue? {
        guard preservedLoadIssue == nil || clearing else { return preservedLoadIssue }
        do {
            guard url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else {
                return .unavailable
            }
            var retained = Self.retained(records, now: now)
            var data = try JSONEncoder().encode(Document(version: 1, records: retained))
            while data.count > Self.maximumBytes,
                  let oldest = retained.lastIndex(where: { $0.status.isTerminal }) {
                retained.remove(at: oldest)
                data = try JSONEncoder().encode(Document(version: 1, records: retained))
            }
            guard data.count <= Self.maximumBytes else { return .writeFailed }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            preservedLoadIssue = nil
            return nil
        } catch {
            return .writeFailed
        }
    }

    static func retained(_ records: [LibraryActivityRecord], now: Date) -> [LibraryActivityRecord] {
        let sorted = records.sorted {
            if $0.status.isTerminal != $1.status.isTerminal { return !$0.status.isTerminal }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        var terminalCount = 0
        return sorted.filter { record in
            guard record.status.isTerminal else { return true }
            guard now.timeIntervalSince(record.finishedAt ?? record.updatedAt) <= retentionInterval,
                  terminalCount < maximumTerminalRecords else { return false }
            terminalCount += 1
            return true
        }
    }

    private static func isValid(_ records: [LibraryActivityRecord]) -> Bool {
        guard Set(records.map(\.id)).count == records.count else { return false }
        return records.allSatisfy {
            $0.completed >= 0 && $0.total >= 0 && $0.failureCount >= $0.failures.count && $0.failures.count <= 100
                && $0.startedAt.timeIntervalSinceReferenceDate.isFinite
                && $0.updatedAt.timeIntervalSinceReferenceDate.isFinite
                && $0.failures.allSatisfy { $0.fileName == LibraryActivityFailure.safeFileName($0.fileName) }
                && ($0.counts.map { $0.catalogSaved >= 0 && $0.filesAttempted >= 0 && $0.filesSaved >= 0 && $0.filesFailed >= 0 } ?? true)
        }
    }
}
