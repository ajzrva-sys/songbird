import Foundation
import SwiftData

public struct DuplicateAnalysisResult: Sendable {
    public let groupCount: Int
    public let duplicateTrackCount: Int
    public let pathsToRemove: [String]
    public let cancelled: Bool
}

private struct DuplicateTrackRecord: Sendable {
    let path: String
    let checksum: String
    let dateAdded: Date
}

private actor DuplicateAnalysisStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
    }

    func records() throws -> [DuplicateTrackRecord] {
        try context.fetch(FetchDescriptor<Track>()).map {
            DuplicateTrackRecord(
                path: $0.path,
                checksum: $0.checksum,
                dateAdded: $0.dateAdded
            )
        }
    }

    func saveChecksums(_ checksums: [String: String]) throws {
        guard !checksums.isEmpty else { return }
        let tracks = try context.fetch(FetchDescriptor<Track>())
        for track in tracks {
            if let checksum = checksums[track.path], !checksum.isEmpty {
                track.checksum = checksum
            }
        }
        try context.save()
    }

    func remove(paths: Set<String>) throws -> Int {
        guard !paths.isEmpty else { return 0 }
        let tracks = try context.fetch(FetchDescriptor<Track>())
        var removed = 0
        for track in tracks where paths.contains(track.path) {
            context.delete(track)
            removed += 1
        }
        if removed > 0 { try context.save() }
        return removed
    }
}

public enum DuplicateAnalysisService {
    private static let workerCount = 4
    private static let saveBatchSize = 250

    public static func analyze(
        container: ModelContainer,
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> DuplicateAnalysisResult {
        let store = DuplicateAnalysisStore(container: container)
        var records = try await store.records()
        let missing = records.filter { $0.checksum.isEmpty }
        var completed = 0
        await progress(0, missing.count)

        for start in stride(from: 0, to: missing.count, by: saveBatchSize) {
            if Task.isCancelled {
                return cancelledResult()
            }
            let end = min(start + saveBatchSize, missing.count)
            let batch = Array(missing[start..<end])
            let checksums = await hash(batch)
            if Task.isCancelled {
                return cancelledResult()
            }
            try await store.saveChecksums(checksums)
            completed += batch.count
            await progress(completed, missing.count)
        }

        if !missing.isEmpty {
            records = try await store.records()
        }
        var groups: [String: [DuplicateTrackRecord]] = [:]
        for record in records where !record.checksum.isEmpty {
            groups[record.checksum, default: []].append(record)
        }
        let duplicates = groups.values.filter { $0.count > 1 }
        let removals = duplicates.flatMap { group in
            group.sorted {
                if $0.dateAdded == $1.dateAdded { return $0.path < $1.path }
                return $0.dateAdded < $1.dateAdded
            }.dropFirst().map(\.path)
        }
        return DuplicateAnalysisResult(
            groupCount: duplicates.count,
            duplicateTrackCount: removals.count,
            pathsToRemove: removals,
            cancelled: false
        )
    }

    public static func removeAnalyzedDuplicates(
        _ result: DuplicateAnalysisResult,
        container: ModelContainer
    ) async throws -> Int {
        guard !result.cancelled else { return 0 }
        let store = DuplicateAnalysisStore(container: container)
        return try await store.remove(paths: Set(result.pathsToRemove))
    }

    private static func hash(
        _ records: [DuplicateTrackRecord]
    ) async -> [String: String] {
        await withTaskGroup(of: (String, String).self) { group in
            var next = 0
            var results: [String: String] = [:]

            func submit(_ index: Int) {
                let path = records[index].path
                group.addTask {
                    guard !Task.isCancelled else { return (path, "") }
                    guard case .available(let url) = FilesystemPathResolver().resolve(path) else {
                        return (path, "")
                    }
                    return (path, Track.contentChecksum(at: url.path))
                }
            }

            while next < min(workerCount, records.count) {
                submit(next)
                next += 1
            }
            while let (path, checksum) = await group.next() {
                if !checksum.isEmpty { results[path] = checksum }
                if next < records.count, !Task.isCancelled {
                    submit(next)
                    next += 1
                }
            }
            return results
        }
    }

    private static func cancelledResult() -> DuplicateAnalysisResult {
        DuplicateAnalysisResult(
            groupCount: 0,
            duplicateTrackCount: 0,
            pathsToRemove: [],
            cancelled: true
        )
    }
}
