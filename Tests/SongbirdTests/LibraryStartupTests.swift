import Foundation
import SwiftData
import Testing
@testable import SongbirdLib

private actor StartupReadBuilder: LibrarySnapshotBuilding {
    var shouldFail = true
    func buildSnapshot(revision: Int) async throws -> LibrarySnapshot {
        if shouldFail { shouldFail = false; throw ReadError.unavailable }
        return LibrarySnapshot(revision: revision, tracks: [], albums: [], playlists: [])
    }
    enum ReadError: Error { case unavailable }
}

private final class StartupPathGate: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var started = false
    private var onMain = false
    var status: (started: Bool, onMain: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (started, onMain)
    }
    func resolve(_ paths: [String]) -> [String] {
        if paths == ["slow"] {
            lock.lock(); started = true; onMain = Thread.isMainThread; lock.unlock()
            _ = gate.wait(timeout: .now() + 2)
        }
        return paths
    }
    func release() { gate.signal() }
}

@Suite("Initial library loading", .serialized)
struct LibraryStartupTests {
    @Test("Unread, failed and successfully empty catalogs remain distinct")
    @MainActor
    func initialReadStates() async throws {
        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let container = try ModelContainer(for: schema, configurations:
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let store = LibrarySnapshotStore(modelContainer: container, startsImmediately: false,
                                         snapshotBuilder: StartupReadBuilder())
        guard case .loading(nil) = store.initialLoadState else {
            Issue.record("Unread library must be loading"); return
        }
        await store.refresh()
        guard case .failed(_, nil) = store.initialLoadState else {
            Issue.record("Read failure must offer recovery"); return
        }
        await store.refresh()
        guard case .loaded(let snapshot) = store.initialLoadState else {
            Issue.record("A successful empty catalog must finish loading"); return
        }
        #expect(snapshot.revision > 0)
        #expect(snapshot.tracks.isEmpty)
    }

    @Test("Slow folder checks yield the main actor and start watching after completion")
    @MainActor
    func folderChecksDoNotBlockUI() async throws {
        let gate = StartupPathGate()
        defer { gate.release() }
        var started: [[String]] = []
        let watcher = LibraryFolderWatcher(observesSystemEvents: false,
            resolvePaths: { gate.resolve($0) }, startStream: { started.append($0) })
        watcher.start(paths: ["slow"])
        try await waitUntil { gate.status.started }
        #expect(!gate.status.onMain)
        #expect(started.isEmpty)
        gate.release()
        try await waitUntil { !started.isEmpty }
        #expect(started == [["slow"]])
        watcher.stop()
    }

    @Test("A late folder check cannot undo Stop or newer folder settings", arguments: [false, true])
    @MainActor
    func staleFolderChecks(replace: Bool) async throws {
        let gate = StartupPathGate()
        defer { gate.release() }
        var started: [[String]] = []
        let watcher = LibraryFolderWatcher(observesSystemEvents: false,
            resolvePaths: { gate.resolve($0) }, startStream: { started.append($0) })
        watcher.start(paths: ["slow"])
        try await waitUntil { gate.status.started }
        if replace {
            watcher.start(paths: ["new"])
            try await waitUntil { !started.isEmpty }
        } else { watcher.stop() }
        gate.release()
        try await Task.sleep(for: .milliseconds(50))
        #expect(started == (replace ? [["new"]] : []))
        watcher.stop()
    }

    @Test("Hidden formatted columns are deferred and become available when shown")
    @MainActor
    func visibleColumnFormatting() async throws {
        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let container = try ModelContainer(for: schema, configurations:
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let track = Track(path: "/fixture/startup.wav", title: "Startup")
        container.mainContext.insert(track)
        try container.mainContext.save()
        let snapshot = try await LibrarySnapshotModelActor(modelContainer: container).buildSnapshot(revision: 1)
        let worker = TrackTableProjectionWorker()
        let initial = try await worker.project(snapshot: snapshot, request: .init(collection: .allTracks))
        #expect(initial.displayValuesByID[track.id]?.text(for: .title) == "Startup")
        #expect(initial.displayValuesByID[track.id]?.text(for: .dateAdded) == nil)
        var prefs = TrackTableColumnPrefs.defaults
        for index in prefs.indices { prefs[index].visible = true }
        let expanded = try await worker.project(snapshot: snapshot, request: .init(collection: .allTracks,
            columnPreferencesJSON: TrackTableColumnPrefs.encode(prefs)))
        let full = TrackTableDisplayValues(track: try #require(snapshot.tracks.first))
        for column in expanded.columns {
            #expect(expanded.displayValuesByID[track.id]?.text(for: column.column) == full.text(for: column.column))
        }
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(condition())
    }
}
