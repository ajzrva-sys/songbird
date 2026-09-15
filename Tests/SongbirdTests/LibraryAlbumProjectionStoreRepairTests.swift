import Combine
import Foundation
import SwiftData
import Testing
@testable import SongbirdLib

@Suite("Album projection repair", .serialized)
@MainActor
struct LibraryAlbumProjectionStoreRepairTests {
    @Test("A superseded grouping failure cannot replace the current loaded state")
    func ignoresStaleFailure() async {
        let gate = GroupingGate()
        enum Expected: Error { case stale }
        let store = LibraryAlbumProjectionStore(project: { snapshot in
            if snapshot.revision == 1 {
                await gate.suspend()
                throw Expected.stale
            }
            return try await LibraryAlbumProjectionWorker().project(snapshot)
        })
        let first = Task {
            await store.update(from: LibrarySnapshot(revision: 1, tracks: [], albums: [], playlists: []))
        }
        await gate.waitForStart()
        await store.update(from: LibrarySnapshot(revision: 2, tracks: [], albums: [], playlists: []))
        await gate.release()
        await first.value
        #expect(store.projectionRevision == 2)
        guard case .loaded = store.state else {
            Issue.record("A stale failure replaced the current loaded projection")
            return
        }
    }

    @Test("Identical in-flight callers join one grouping and one publication")
    func coalescesIdenticalRequests() async {
        let gate = GroupingGate()
        let store = LibraryAlbumProjectionStore(project: { snapshot in
            try await gate.project(snapshot)
        })
        let snapshot = LibrarySnapshot(revision: 1, tracks: [], albums: [], playlists: [])
        var loadingCount = 0
        var loadedCount = 0
        let observer = store.$state.dropFirst().sink { state in
            switch state {
            case .loading: loadingCount += 1
            case .loaded: loadedCount += 1
            case .failed: break
            }
        }
        let first = Task { await store.update(from: snapshot) }
        await gate.waitForStart()
        var second: Task<Void, Never>?
        await withCheckedContinuation { started in
            second = Task { @MainActor in
                started.resume()
                await store.update(from: snapshot)
            }
        }
        #expect(loadingCount == 1)
        second?.cancel()
        await gate.release()
        await first.value
        await second?.value
        #expect(await gate.callCount == 1)
        #expect(loadedCount == 1)
        #expect(store.projectionRevision == 1)
        withExtendedLifetime(observer) {}
    }

    @Test("Detail derivation runs once per structure, not per header lookup or favorite change")
    func cachedDisplayDetails() async throws {
        let counter = DetailBuildCounter()
        let worker = LibraryAlbumProjectionWorker()
        let store = LibraryAlbumProjectionStore(worker: worker, detailBuilder: { groups in
            counter.increment()
            return LibraryAlbumDisplayDetail.details(for: groups)
        })
        let identifier = Track(path: "/fixture/track.mp3", title: "Fixture").persistentModelID
        let firstID = UUID()
        let secondID = UUID()
        let tracks = [
            LibraryTrackSnapshot(persistentIdentifier: identifier, title: "One", artist: "First",
                                 album: "Shared title", path: "/fixture/First edition/track.mp3", albumID: firstID),
            LibraryTrackSnapshot(persistentIdentifier: identifier, title: "Two", artist: "Second",
                                 album: "Shared title", path: "/fixture/Second edition/track.mp3", albumID: secondID),
        ]
        let albums = [
            LibraryAlbumSnapshot(id: firstID, persistentIdentifier: identifier, title: "Shared title", artist: "First", year: 2001, trackIDs: [tracks[0].id]),
            LibraryAlbumSnapshot(id: secondID, persistentIdentifier: identifier, title: "Shared title", artist: "Second", year: 2002, trackIDs: [tracks[1].id]),
        ]
        func snapshot(_ revision: Int, structure: Int, albums: [LibraryAlbumSnapshot]) -> LibrarySnapshot {
            LibrarySnapshot(revision: revision, albumStructureRevision: structure,
                            tracks: tracks.filter { track in albums.contains { $0.id == track.albumID } },
                            albums: albums, playlists: [])
        }
        await store.update(from: snapshot(1, structure: 1, albums: albums))
        let group = try #require(store.group(containing: albums[0].id))
        #expect(counter.count == 1)
        for _ in 0..<100 {
            #expect(store.displayDetail(forGroupID: group.id) == "First edition")
            #expect(store.displayDetail(forGroupID: "unknown") == nil)
        }
        #expect(counter.count == 1)
        await store.update(from: snapshot(2, structure: 1, albums: albums.map { $0.withFavorite(true) }))
        #expect(store.group(containing: albums[0].id)?.isFavorite == true)
        #expect(store.displayDetail(forGroupID: group.id) == "First edition")
        #expect(counter.count == 1)
        #expect(await worker.projectionCount() == 1)
        await store.update(from: snapshot(3, structure: 3, albums: [albums[0]]))
        #expect(store.displayDetail(forGroupID: group.id) == nil)
        #expect(counter.count == 2)
        await store.update(from: snapshot(4, structure: 4, albums: []))
        #expect(store.groups.isEmpty)
        #expect(store.displayDetail(forGroupID: group.id) == nil)
        #expect(counter.count == 3)
    }
}

/// Suspends the actual grouping dependency, not a timer. Cancellation is
/// deliberately ignored until release so stale completion paths are exercised.
private actor GroupingGate {
    private let worker = LibraryAlbumProjectionWorker()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private(set) var callCount = 0

    func project(_ snapshot: LibrarySnapshot) async throws -> [LibraryAlbumGroupSnapshot] {
        await suspend()
        return try await worker.project(snapshot)
    }

    func suspend() async {
        callCount += 1
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        if !released { await withCheckedContinuation { waiters.append($0) } }
    }

    func waitForStart() async {
        if callCount == 0 { await withCheckedContinuation { startWaiters.append($0) } }
    }

    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private final class DetailBuildCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}
