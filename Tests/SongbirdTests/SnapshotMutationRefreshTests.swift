import Foundation
import SwiftData
import Testing
@testable import SongbirdLib

@ModelActor
private actor SnapshotMutationWriter {
    func rateTrack(_ id: UUID, rating: Int) throws {
        let track = try modelContext.fetch(FetchDescriptor<Track>(
            predicate: #Predicate { $0.id == id }
        )).first!
        track.rating = rating
        try modelContext.save()
    }
}

private actor ControlledMutationSnapshotBuilder: LibrarySnapshotBuilding {
    let worker: LibrarySnapshotModelActor
    private(set) var patchCalls = 0
    private var pausePatches = false
    private var failReads = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(container: ModelContainer) {
        worker = LibrarySnapshotModelActor(modelContainer: container)
    }

    func pause() { pausePatches = true }
    func fail(_ value: Bool) { failReads = value }
    func resume() {
        pausePatches = false
        for continuation in continuations { continuation.resume() }
        continuations.removeAll()
    }

    func buildSnapshot(revision: Int) async throws -> LibrarySnapshot {
        if failReads { throw ReadFailure.expected }
        return try await worker.buildSnapshot(revision: revision)
    }

    func apply(changeSet: LibrarySnapshotChangeSet, to snapshot: LibrarySnapshot,
               revision: Int) async throws -> LibrarySnapshot? {
        patchCalls += 1
        if pausePatches { await withCheckedContinuation { continuations.append($0) } }
        if failReads { throw ReadFailure.expected }
        return try await worker.apply(changeSet: changeSet, to: snapshot, revision: revision)
    }

    private enum ReadFailure: Error { case expected }
}

@Suite("Explicit post-mutation snapshot refresh", .serialized)
struct SnapshotMutationRefreshTests {
    @Test("Real saves followed by explicit mutation refresh patch rather than rebuilding",
          arguments: [false, true])
    @MainActor
    func boundedMutationRefresh(modelActorSave: Bool) async throws {
        let container = try makeContainer()
        let track = Track(path: "/fixture/refresh.mp3", title: "Original")
        container.mainContext.insert(track)
        try container.mainContext.save()
        let store = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await store.refresh()
        let albumRevision = store.snapshot.albumStructureRevision
        if modelActorSave {
            let writer = await Task.detached {
                SnapshotMutationWriter(modelContainer: container)
            }.value
            try await writer.rateTrack(track.id, rating: 3)
            try await writer.rateTrack(track.id, rating: 5)
        } else {
            track.rating = 3
            try container.mainContext.save()
            track.rating = 5
            try container.mainContext.save()
        }
        await store.refreshAfterMutation()
        #expect(store.snapshot.tracksByID[track.id]?.rating == 5)
        #expect(store.snapshot.albumStructureRevision == albumRevision)
        #expect(store.fullRebuildCount == 1)
        #expect(store.patchPublicationCount == 1)
        try await Task.sleep(for: .milliseconds(180))
        #expect(store.fullRebuildCount == 1)
        #expect(store.patchPublicationCount == 1)
    }

    @Test("Full reads see saves made after the worker has already loaded the catalog")
    @MainActor
    func fullReadFreshness() async throws {
        let container = try makeContainer()
        let track = Track(path: "/fixture/full.mp3", title: "Before")
        container.mainContext.insert(track)
        try container.mainContext.save()
        let worker = LibrarySnapshotModelActor(modelContainer: container)
        let before = try await worker.buildSnapshot(revision: 1)
        #expect(before.tracksByID[track.id]?.title == "Before")
        track.title = "After"
        try container.mainContext.save()
        let after = try await worker.buildSnapshot(revision: 2)
        #expect(after.tracksByID[track.id]?.title == "After")
    }

    @Test("Concurrent explicit refreshes join the save patch already reading")
    @MainActor
    func joinsInFlightPatch() async throws {
        let container = try makeContainer()
        let track = Track(path: "/fixture/inflight.mp3", title: "In flight")
        container.mainContext.insert(track)
        try container.mainContext.save()
        let builder = ControlledMutationSnapshotBuilder(container: container)
        let store = LibrarySnapshotStore(
            modelContainer: container, startsImmediately: false, snapshotBuilder: builder
        )
        await store.refresh()
        await builder.pause()
        track.rating = 4
        try container.mainContext.save()
        for _ in 0..<100 {
            if await builder.patchCalls > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await builder.patchCalls == 1)
        let first = Task { await store.refreshAfterMutation() }
        let second = Task { await store.refreshAfterMutation() }
        for _ in 0..<20 { await Task.yield() }
        #expect(await builder.patchCalls == 1)
        await builder.resume()
        await first.value
        await second.value
        #expect(store.snapshot.tracksByID[track.id]?.rating == 4)
        #expect(store.fullRebuildCount == 1)
        #expect(store.patchPublicationCount == 1)
        #expect(await builder.patchCalls == 1)
    }

    @Test("Mutation refresh failures retain the good snapshot and retry pending changes")
    @MainActor
    func failedMutationRefreshRecovery() async throws {
        let container = try makeContainer()
        let track = Track(path: "/fixture/recovery.mp3", title: "Recovery")
        container.mainContext.insert(track)
        try container.mainContext.save()
        let builder = ControlledMutationSnapshotBuilder(container: container)
        let store = LibrarySnapshotStore(
            modelContainer: container, startsImmediately: false, snapshotBuilder: builder
        )
        await store.refresh()
        let good = store.snapshot
        await builder.fail(true)
        track.rating = 4
        try container.mainContext.save()
        await store.refreshAfterMutation()
        #expect(store.snapshot == good)
        #expect(store.rebuildError != nil)
        await builder.fail(false)
        await store.refreshAfterMutation()
        #expect(store.snapshot.tracksByID[track.id]?.rating == 4)
        #expect(store.rebuildError == nil)
        #expect(store.patchPublicationCount == 1)
    }

    @Test("Already-published save changes do not cause a second explicit refresh")
    @MainActor
    func joinsPublishedSave() async throws {
        let container = try makeContainer()
        let track = Track(path: "/fixture/published.mp3", title: "Published")
        container.mainContext.insert(track)
        try container.mainContext.save()
        let store = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await store.refresh()
        track.rating = 4
        try container.mainContext.save()
        for _ in 0..<100 {
            if store.patchPublicationCount == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.patchPublicationCount == 1)
        await store.refreshAfterMutation()
        #expect(store.snapshot.tracksByID[track.id]?.rating == 4)
        #expect(store.fullRebuildCount == 1)
        #expect(store.patchPublicationCount == 1)
    }

    @Test("Missing, unknown, bulk and oversized save evidence keeps the full-read fallback",
          arguments: ["missing", "unknown", "bulk", "oversized"])
    @MainActor
    func mutationFallbacks(kind: String) async throws {
        let container = try makeContainer()
        let track = Track(path: "/fixture/fallback.mp3", title: "Fallback")
        container.mainContext.insert(track)
        try container.mainContext.save()
        let store = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await store.refresh()
        switch kind {
        case "unknown":
            track.rating = 4
            try container.mainContext.save()
            NotificationCenter.default.post(name: ModelContext.didSave, object: container.mainContext)
        case "bulk":
            store.beginBulkUpdates()
            track.rating = 4
            try container.mainContext.save()
        case "oversized":
            for index in 0..<257 {
                container.mainContext.insert(Track(path: "/fixture/large-" + String(index), title: "Added"))
            }
            try container.mainContext.save()
        default:
            break // No save evidence at all: do not infer that the catalog is current.
        }
        await store.refreshAfterMutation()
        #expect(store.fullRebuildCount == 2)
        #expect(store.patchPublicationCount == 0)
        #expect(store.rebuildError == nil)
        if kind == "bulk" || kind == "unknown" {
            #expect(store.snapshot.tracksByID[track.id]?.rating == 4)
        }
        if kind == "oversized" { #expect(store.snapshot.tracks.count == 258) }
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self,
                             AlbumFavorite.self, TrackFavorite.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true),
        ])
    }
}
