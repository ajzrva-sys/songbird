import Foundation
import Testing
@testable import SongbirdLib

@Suite("Library Activity", .serialized)
struct LibraryActivityTests {
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("songbird-activity-\(UUID().uuidString)")
            .appendingPathComponent("activity.json")
    }

    @MainActor
    @Test("Durable records retain outcomes and counts without persisting live messages or paths")
    func privacyAndRestart() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LibraryActivityStore(storage: LibraryActivityStorage(url: url))
        await store.load()
        let id = store.begin(kind: .metadataEdit, source: .metadata, total: 6,
                             liveMessage: "token-SECRET /Users/private/music Discogs PRIVATE RESPONSE")
        store.update(id: id, completed: 6)
        let failures = (0..<104).map {
            LibraryActivityFailure(fileName: "/Users/private/music/failure\($0).flac", category: .verificationFailed)
        }
        store.finish(id: id, status: .completedWithWarnings, severity: .warning, failures: failures,
                     counts: .init(catalogSaved: 6, filesAttempted: 6, filesSaved: 4, filesFailed: 2))
        await store.flush()
        let bytes = try Data(contentsOf: url)
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(!text.contains("SECRET"))
        #expect(!text.contains("/Users/"))
        #expect(!text.contains("PRIVATE RESPONSE"))
        let restored = LibraryActivityStore(storage: LibraryActivityStorage(url: url))
        await restored.load()
        let record = try #require(restored.records.first)
        #expect(record.id == id)
        #expect(record.status == .completedWithWarnings)
        #expect(record.counts?.catalogSaved == 6)
        #expect(record.counts?.filesSaved == 4)
        #expect(record.counts?.filesFailed == 2)
        #expect(record.failures.count == 100)
        #expect(record.failureCount == 104)
        #expect(record.failures.first?.fileName == "failure0.flac")
        #expect(restored.liveMessages.isEmpty)
        #expect(LibraryActivityFailure(fileName: "https://provider.test/response?token=SECRET", category: .unknown).fileName == "File")
        await restored.flush()
    }

    @MainActor
    @Test("Running operations become interrupted on restart and terminal rows do not resume")
    func interruptedRecovery() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LibraryActivityStore(storage: LibraryActivityStorage(url: url))
        await store.load()
        let running = store.begin(kind: .importFiles, total: 10)
        store.update(id: running, completed: 4)
        let completed = store.begin(kind: .healthCheck)
        store.finish(id: completed, status: .succeeded)
        await store.flush()
        let restored = LibraryActivityStore(storage: LibraryActivityStorage(url: url))
        await restored.load()
        #expect(restored.records.first(where: { $0.id == running })?.status == .interrupted)
        #expect(restored.records.first(where: { $0.id == running })?.completed == 4)
        #expect(restored.records.first(where: { $0.id == completed })?.status == .succeeded)
        #expect(restored.runningRecords.isEmpty)
        await restored.flush()
    }

    @MainActor
    @Test("Corrupt history remains byte identical until an explicit clear")
    func corruptionPreservation() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("unreadable original token-SECRET".utf8)
        try original.write(to: url)
        let store = LibraryActivityStore(storage: LibraryActivityStorage(url: url))
        await store.load()
        #expect(store.storageIssue == .corrupt)
        let id = store.begin(kind: .healthCheck)
        store.finish(id: id, status: .succeeded)
        await store.flush()
        #expect(try Data(contentsOf: url) == original)
        let running = store.begin(kind: .importFiles)
        await store.clearHistory()
        #expect(store.storageIssue == nil)
        #expect(store.records.map(\.id) == [running])
        #expect(try Data(contentsOf: url) != original)
        store.finish(id: running, status: .cancelled, severity: .information)
        await store.flush()
    }

    @Test("Oversized history is preserved and encoded history stays within the byte limit")
    func byteLimitAndRetention() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(repeating: 0x61, count: LibraryActivityStorage.maximumBytes + 1)
        try original.write(to: url)
        let storage = LibraryActivityStorage(url: url)
        let now = Date()
        #expect(await storage.load(now: now).issue == .corrupt)
        #expect(await storage.save([], now: now) == .corrupt)
        #expect(try Data(contentsOf: url) == original)
        var records = (0..<40).map { index -> LibraryActivityRecord in
            var record = LibraryActivityRecord(kind: .fileTagWrite, startedAt: now.addingTimeInterval(Double(-index)))
            record.status = .failed
            record.finishedAt = record.startedAt
            record.failures = (0..<100).map { _ in
                .init(fileName: String(repeating: "🐦", count: 255), category: .verificationFailed)
            }
            record.failureCount = 100
            return record
        }
        var expired = LibraryActivityRecord(kind: .healthCheck, startedAt: now.addingTimeInterval(-31 * 24 * 3600))
        expired.status = .succeeded
        expired.finishedAt = expired.startedAt
        records.append(expired)
        #expect(await storage.save(records, now: now, clearing: true) == nil)
        #expect(try Data(contentsOf: url).count <= LibraryActivityStorage.maximumBytes)
        let loaded = await LibraryActivityStorage(url: url).load(now: now)
        #expect(loaded.records.count < 40)
        #expect(!loaded.records.contains(where: { $0.id == expired.id }))
        let many = (0..<520).map { _ -> LibraryActivityRecord in
            var record = LibraryActivityRecord(kind: .healthCheck, startedAt: now)
            record.status = .succeeded
            record.finishedAt = now
            return record
        }
        #expect(LibraryActivityStorage.retained(many, now: now).count == 500)
    }

    @Test("An unreadable linked history never exposes or overwrites its target")
    func linkedHistoryPreservation() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let target = url.deletingLastPathComponent().appendingPathComponent("private.json")
        let bytes = Data("private target contents".utf8)
        try bytes.write(to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        let storage = LibraryActivityStorage(url: url)
        #expect(await storage.load(now: Date()).issue == .unavailable)
        #expect(await storage.save([], now: Date()) == .unavailable)
        #expect(try Data(contentsOf: target) == bytes)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: url.path) == target.path)
    }

    @MainActor
    @Test("Operation IDs isolate progress and cancellation and completion notices do not duplicate rows")
    func operationCorrelation() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LibraryActivityStore(storage: LibraryActivityStorage(url: url))
        let status = LibraryStatus(activity: store)
        var firstCancellation = 0
        var secondCancellation = 0
        let first = status.beginOperation(message: "First", total: 5) { firstCancellation += 1 }
        let second = status.beginOperation(message: "Second", total: 8) { secondCancellation += 1 }
        status.updateOperation(completed: 3, message: "First progressing", operationID: first)
        #expect(status.importProgress.value.completed == 0)
        #expect(store.records.first(where: { $0.id == first })?.completed == 3)
        store.cancel(id: first)
        store.cancel(id: first)
        #expect(firstCancellation == 1)
        #expect(secondCancellation == 0)
        #expect(status.importProgress.value.phase == .running)
        status.cancelImport()
        #expect(status.importProgress.value.phase == .cancelling)
        #expect(secondCancellation == 1)
        status.updateOperation(completed: 1, message: "Late work", operationID: second)
        #expect(status.importProgress.value.phase == .cancelling)
        #expect(status.importProgress.value.message == "Cancelling…")
        status.updateScan(scanned: 2, total: 8, message: "Late scan", operationID: second)
        #expect(status.importProgress.value.phase == .cancelling)
        #expect(status.importProgress.value.message == "Cancelling…")
        #expect(store.records.first(where: { $0.id == second })?.status == .cancelling)
        status.endOperation(message: "Cancelled", severity: .information, operationID: first, activityStatus: .cancelled)
        #expect(status.importProgress.value.phase == .cancelling)
        status.endOperation(message: "Cancelled", severity: .information, operationID: second, activityStatus: .cancelled)
        #expect(store.records.count == 2)
        #expect(store.records.allSatisfy { $0.status == .cancelled })
        status.showNotice("/secret/path provider RESPONSE", severity: .error, source: .metadata)
        #expect(store.records.count == 3)
        #expect(store.records.first?.title == "Metadata · Error")
        await store.flush()
        #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("secret"))
    }

    @MainActor
    @Test("Mutable result counts are normalized again at the persistence boundary")
    func resultCountBoundary() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LibraryActivityStore(storage: LibraryActivityStorage(url: url))
        var counts = LibraryActivityCounts()
        counts.catalogSaved = -10
        counts.filesAttempted = -9
        counts.filesSaved = -8
        counts.filesFailed = -7
        let id = store.begin(kind: .metadataEdit)
        store.finish(id: id, status: .succeeded, counts: counts)
        #expect(store.records.first?.counts == LibraryActivityCounts())
        await store.flush()
        let restored = await LibraryActivityStorage(url: url).load(now: Date())
        #expect(restored.issue == nil)
        #expect(restored.records.first?.counts == LibraryActivityCounts())
    }

    @MainActor
    @Test("Unactivated stores remain memory only and active records sort before recently completed work")
    func activationAndOrdering() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LibraryActivityStore(storage: LibraryActivityStorage(url: url))
        let active = store.begin(kind: .importFiles)
        let terminal = store.begin(kind: .healthCheck)
        store.finish(id: terminal, status: .succeeded)
        await Task.yield()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.records.first?.id == active)
        await store.flush()
        #expect(FileManager.default.fileExists(atPath: url.path))
        store.finish(id: active, status: .cancelled, severity: .information)
        await store.flush()
    }

    @MainActor
    @Test("Rapid progress remains live while durable progress waits for the coalescing interval")
    func progressCoalescing() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LibraryActivityStore(storage: LibraryActivityStorage(url: url))
        await store.load()
        let id = store.begin(kind: .importFiles, total: 10)
        await store.flush()
        let before = try Data(contentsOf: url)
        for index in 1...9 { store.update(id: id, completed: index, liveMessage: "\(index)") }
        await Task.yield()
        #expect(store.records.first?.completed == 9)
        #expect(try Data(contentsOf: url) == before)
        store.finish(id: id, status: .succeeded)
        await store.flush()
        let restored = await LibraryActivityStorage(url: url).load(now: Date())
        #expect(restored.records.first?.completed == 9)
        #expect(restored.records.first?.status == .succeeded)
    }
}
