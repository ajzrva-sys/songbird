import Combine
import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import SongbirdLib

private actor FlakySnapshotBuilder: LibrarySnapshotBuilding {
    private var calls = 0

    func buildSnapshot(revision: Int) async throws -> LibrarySnapshot {
        calls += 1
        if calls > 1 { throw TestFailure.expectedFailure }
        return LibrarySnapshot(revision: revision, tracks: [], albums: [], playlists: [])
    }

    private enum TestFailure: Error { case expectedFailure }
}

private actor PatchFailingSnapshotBuilder: LibrarySnapshotBuilding {
    func buildSnapshot(revision: Int) async throws -> LibrarySnapshot {
        LibrarySnapshot(revision: revision, tracks: [], albums: [], playlists: [])
    }

    func apply(
        changeSet: LibrarySnapshotChangeSet,
        to snapshot: LibrarySnapshot,
        revision: Int
    ) async throws -> LibrarySnapshot? {
        throw PatchFailure.expected
    }

    private enum PatchFailure: Error { case expected }
}

@Suite("Immutable library projections", .serialized)
struct UIProjectionPerformanceTests {
    @Test("Album detail can render from its snapshot before full-library projection finishes")
    @MainActor
    func provisionalAlbumDetail() throws {
        let identifier = try fixtureIdentifier()
        let albumID = UUID()
        let trackID = UUID()
        let album = LibraryAlbumSnapshot(
            id: albumID,
            persistentIdentifier: identifier,
            title: "Immediate Album",
            artist: "Fast Artist",
            year: 2026,
            trackIDs: [trackID],
            isFavorite: true
        )
        let snapshot = LibrarySnapshot(
            revision: 1,
            tracks: [],
            albums: [album],
            playlists: []
        )
        let store = LibraryAlbumProjectionStore()

        let result = try #require(store.group(containing: albumID, fallback: snapshot))

        #expect(result.title == "Immediate Album")
        #expect(result.artist == "Fast Artist")
        #expect(result.trackIDs == [trackID])
        #expect(result.isFavorite)
    }

    @Test("Ten-thousand-track projection filters, sorts, totals, and indexes without selection input")
    @MainActor
    func largeProjection() async throws {
        let identifier = try fixtureIdentifier()
        let tracks = makeTracks(count: 10_000, identifier: identifier)
        let snapshot = LibrarySnapshot(
            revision: 9,
            tracks: tracks,
            albums: [],
            playlists: []
        )
        let worker = TrackTableProjectionWorker()
        let unfiltered = try await worker.project(
            snapshot: snapshot,
            request: TrackTableRequest(collection: .allTracks)
        )
        let albumID = try #require(unfiltered.facets.albums.first { $0.title == "Album 2" }?.id)
        let request = TrackTableRequest(
            collection: .allTracks,
            selectedArtist: "Artist 3",
            selectedAlbumID: albumID,
            sortColumn: .playCount,
            sortAscending: false
        )

        let projection = try await worker.project(snapshot: snapshot, request: request)

        #expect(projection.sourceRevision == 9)
        #expect(projection.rows.allSatisfy { $0.artist == "Artist 3" && $0.album == "Album 2" })
        #expect(projection.rows == projection.rows.sorted {
            if $0.playCount == $1.playCount { return $0.id.uuidString < $1.id.uuidString }
            return $0.playCount > $1.playCount
        })
        #expect(projection.totalDuration == projection.rows.reduce(0) { $0 + $1.duration })
        #expect(projection.indexByID.count == projection.rows.count)
        #expect(projection.facets.artists.count == 20)
        #expect(projection.facets.albums.count == 10)

        let invocationsBeforeSelection = await worker.projectionCount()
        if let first = projection.orderedIDs.first, let last = projection.orderedIDs.last {
            let selected = projection.selectionRange(anchorID: first, targetID: last)
            #expect(selected.count == projection.rows.count)
            #expect(projection.selectedIDsInDisplayOrder(selected) == projection.orderedIDs)
        }
        #expect(await worker.projectionCount() == invocationsBeforeSelection)
    }

    @Test("Disc Number displays and Disc and BPM sort numerically")
    @MainActor
    func discAndBPMSorting() async throws {
        let identifier = try fixtureIdentifier()
        let tracks = [
            LibraryTrackSnapshot(
                persistentIdentifier: identifier,
                title: "Ten",
                discNumber: 10,
                beatsPerMinute: 90
            ),
            LibraryTrackSnapshot(
                persistentIdentifier: identifier,
                title: "Two",
                discNumber: 2,
                beatsPerMinute: 120
            ),
        ]
        let snapshot = LibrarySnapshot(revision: 1, tracks: tracks, albums: [], playlists: [])
        let columns = TrackTableColumnPrefs.encode([
            TrackColumnPref(id: TrackSortColumn.title.rawValue, visible: true),
            TrackColumnPref(id: TrackSortColumn.discNumber.rawValue, visible: true),
        ])
        let worker = TrackTableProjectionWorker()

        let byDisc = try await worker.project(
            snapshot: snapshot,
            request: TrackTableRequest(
                collection: .allTracks,
                sortColumn: .discNumber,
                sortAscending: true,
                columnPreferencesJSON: columns
            )
        )
        #expect(byDisc.rows.map(\.discNumber) == [2, 10])
        #expect(byDisc.displayValuesByID[byDisc.rows[0].id]?.text(for: .discNumber) == "2")

        let byBPM = try await worker.project(
            snapshot: snapshot,
            request: TrackTableRequest(
                collection: .allTracks,
                sortColumn: .beatsPerMinute,
                sortAscending: true
            )
        )
        #expect(byBPM.rows.map(\.beatsPerMinute) == [90, 120])
    }

    @Test("Sort-only projection work stays on the worker and preserves presentation values")
    @MainActor
    func workerOwnedSort() async throws {
        let identifier = try fixtureIdentifier()
        let tracks = makeTracks(count: 100, identifier: identifier)
        let worker = TrackTableProjectionWorker()
        let projection = try await worker.project(
            snapshot: LibrarySnapshot(revision: 1, tracks: tracks, albums: [], playlists: []),
            request: TrackTableRequest(collection: .allTracks, sortColumn: .title)
        )

        let sorted = try await worker.sort(
            projection: projection,
            column: .playCount,
            ascending: false
        )

        #expect(await worker.sortCount() == 1)
        #expect(sorted.rows.map(\.playCount) == sorted.rows.map(\.playCount).sorted(by: >))
        #expect(sorted.displayValuesByID == projection.displayValuesByID)
        #expect(sorted.displayValuesByID[tracks[0].id]?.text(for: .duration) != nil)
    }

    @Test("A cancelled stale sort publishes nothing and leaves the previous projection usable")
    @MainActor
    func staleSortCancellation() async throws {
        let identifier = try fixtureIdentifier()
        let tracks = makeTracks(count: 10_000, identifier: identifier)
        let worker = TrackTableProjectionWorker()
        let previous = try await worker.project(
            snapshot: LibrarySnapshot(revision: 1, tracks: tracks, albums: [], playlists: []),
            request: TrackTableRequest(collection: .allTracks, sortColumn: .title)
        )

        let stale = Task {
            try await worker.sort(
                projection: previous,
                column: .playCount,
                ascending: false
            )
        }
        stale.cancel()
        do {
            _ = try await stale.value
            Issue.record("A cancelled sort must not return a publishable projection")
        } catch is CancellationError {
            // Expected: the view continues presenting `previous` until a current sort completes.
        }

        #expect(previous.orderedIDs == previous.rows.map(\.id))
        let current = try await worker.sort(
            projection: previous,
            column: .playCount,
            ascending: false
        )
        #expect(current.rows.map(\.playCount) == current.rows.map(\.playCount).sorted(by: >))
        #expect(await worker.sortCount() == 1)
    }

    @Test("Collection and facet derivation caches reuse a revision and reset for the next")
    @MainActor
    func projectionCaches() async throws {
        let identifier = try fixtureIdentifier()
        let tracks = makeTracks(count: 1_000, identifier: identifier).sorted {
            $0.dateAdded > $1.dateAdded
        }
        let worker = TrackTableProjectionWorker()
        let request = TrackTableRequest(collection: .recentlyAdded(limit: 200))
        let firstSnapshot = LibrarySnapshot(revision: 1, tracks: tracks, albums: [], playlists: [])

        let first = try await worker.project(snapshot: firstSnapshot, request: request)
        _ = try await worker.project(snapshot: firstSnapshot, request: request)

        #expect(first.rows.map(\.id) == Array(tracks.prefix(200)).map(\.id))
        #expect(await worker.collectionBuildCount() == 1)
        #expect(await worker.facetBuildCount() == 1)

        _ = try await worker.project(
            snapshot: LibrarySnapshot(revision: 2, tracks: tracks, albums: [], playlists: []),
            request: request
        )
        #expect(await worker.collectionBuildCount() == 2)
        #expect(await worker.facetBuildCount() == 2)
    }

    @Test("Album track projection skips full-library facets and preserves album order")
    @MainActor
    func fastAlbumProjection() async throws {
        let identifier = try fixtureIdentifier()
        let tracks = makeTracks(count: 10_000, identifier: identifier)
        let requestedIDs = [tracks[9_999].id, tracks[12].id, tracks[4_321].id]
        let snapshot = LibrarySnapshot(revision: 10, tracks: tracks, albums: [], playlists: [])

        let projection = try await TrackTableProjectionWorker().project(
            snapshot: snapshot,
            request: TrackTableRequest(
                collection: .orderedTrackIDs(requestedIDs),
                includesFacets: false
            )
        )

        #expect(projection.orderedIDs == requestedIDs)
        #expect(projection.facets == .empty)
    }

    @Test("Album tracks can be projected synchronously for the first rendered frame")
    @MainActor
    func immediateAlbumProjection() throws {
        // Given
        let identifier = try fixtureIdentifier()
        let tracks = makeTracks(count: 20, identifier: identifier)
        let requestedIDs = [tracks[14].id, tracks[2].id, tracks[9].id]
        let snapshot = LibrarySnapshot(
            revision: 11,
            tracks: tracks,
            albums: [],
            playlists: []
        )

        // When
        let projection = TrackTableProjection.immediateOrdered(
            snapshot: snapshot,
            trackIDs: requestedIDs,
            columnPreferencesJSON: TrackTableColumnPrefs.encode(TrackTableColumnPrefs.defaults)
        )

        // Then
        #expect(projection.sourceRevision == snapshot.revision)
        #expect(projection.orderedIDs == requestedIDs)
        #expect(projection.rows.map(\.id) == requestedIDs)
        #expect(projection.facets == .empty)
        #expect(projection.sourceWasEmpty == false)
    }

    @Test("Search and cascading facets retain their existing behavior")
    @MainActor
    func searchAndFacets() async throws {
        let identifier = try fixtureIdentifier()
        let tracks = makeTracks(count: 1_000, identifier: identifier)
        let snapshot = LibrarySnapshot(revision: 1, tracks: tracks, albums: [], playlists: [])
        let worker = TrackTableProjectionWorker()

        let searched = try await worker.project(
            snapshot: snapshot,
            request: TrackTableRequest(collection: .allTracks, searchText: "Song 999")
        )
        #expect(searched.rows.map(\.title) == ["Song 999"])

        let allTracks = try await worker.project(
            snapshot: snapshot,
            request: TrackTableRequest(collection: .allTracks)
        )
        let albumID = try #require(allTracks.facets.albums.first { $0.title == "Album 4" }?.id)
        let cascaded = try await worker.project(
            snapshot: snapshot,
            request: TrackTableRequest(
                collection: .allTracks,
                selectedArtist: "Artist 7",
                selectedAlbumID: albumID
            )
        )
        #expect(cascaded.facets.albums.count == 10)
        #expect(cascaded.facets.genres.isEmpty == false)
        #expect(cascaded.rows.allSatisfy { $0.artist == "Artist 7" && $0.album == "Album 4" })
    }

    @Test("Artist cascade groups compilation tracks by album artist")
    @MainActor
    func albumArtistCascade() async throws {
        let identifier = try fixtureIdentifier()
        let tracks = (0..<30).map { index in
            LibraryTrackSnapshot(
                persistentIdentifier: identifier,
                title: "Compilation Track \(index)",
                artist: "Performer \(index)",
                album: "Compilation",
                albumArtist: "Various Artists"
            )
        }
        let worker = TrackTableProjectionWorker()

        let projection = try await worker.project(
            snapshot: LibrarySnapshot(revision: 1, tracks: tracks, albums: [], playlists: []),
            request: TrackTableRequest(
                collection: .allTracks,
                selectedArtist: "Various Artists"
            )
        )

        #expect(projection.facets.artists == ["Various Artists"])
        #expect(projection.rows.count == 30)
    }

    @Test("Selecting multiple album facets returns tracks from every selected album")
    @MainActor
    func multipleAlbumFacets() async throws {
        let identifier = try fixtureIdentifier()
        let tracks = makeTracks(count: 1_000, identifier: identifier)
        let snapshot = LibrarySnapshot(revision: 1, tracks: tracks, albums: [], playlists: [])
        let worker = TrackTableProjectionWorker()
        let allTracks = try await worker.project(
            snapshot: snapshot,
            request: TrackTableRequest(collection: .allTracks)
        )
        let selectedFacets = allTracks.facets.albums.filter {
            $0.title == "Album 2" || $0.title == "Album 4"
        }
        #expect(selectedFacets.count == 2)

        let projection = try await worker.project(
            snapshot: snapshot,
            request: TrackTableRequest(
                collection: .allTracks,
                selectedAlbumIDs: Set(selectedFacets.map(\.id))
            )
        )

        #expect(projection.rows.isEmpty == false)
        #expect(projection.rows.allSatisfy { $0.album == "Album 2" || $0.album == "Album 4" })
        #expect(Set(projection.rows.map(\.album)) == ["Album 2", "Album 4"])
    }

    @Test("Manual playlist order and snapshot smart rules are preserved")
    @MainActor
    func playlistOrderingAndSmartRuleParity() async throws {
        let identifier = try fixtureIdentifier()
        let tracks = makeTracks(count: 12, identifier: identifier)
        let manualID = UUID()
        let smartID = UUID()
        let manualOrder = [tracks[8].id, tracks[2].id, tracks[11].id]
        let rules = SmartPlaylistRuleSet(conditions: [
            SmartCondition(field: .playCount, op: .greaterThan, value: "7"),
        ])
        let snapshot = LibrarySnapshot(
            revision: 2,
            tracks: tracks,
            albums: [],
            playlists: [
                LibraryPlaylistSnapshot(
                    id: manualID,
                    persistentIdentifier: identifier,
                    name: "Manual",
                    trackIDs: manualOrder
                ),
                LibraryPlaylistSnapshot(
                    id: smartID,
                    persistentIdentifier: identifier,
                    name: "Smart",
                    isSmart: true,
                    rules: rules
                ),
            ]
        )
        let worker = TrackTableProjectionWorker()

        let manual = try await worker.project(
            snapshot: snapshot,
            request: TrackTableRequest(collection: .playlist(manualID))
        )
        #expect(manual.orderedIDs == manualOrder)

        let smart = try await worker.project(
            snapshot: snapshot,
            request: TrackTableRequest(collection: .playlist(smartID))
        )
        #expect(Set(smart.orderedIDs) == Set(tracks.filter(rules.matches).map(\.id)))
    }

    @Test("Snapshot actor returns values and deleted models no longer resolve")
    @MainActor
    func snapshotAndResolution() async throws {
        let container = try makeContainer()
        let track = Track(path: "/tmp/snapshot.mp3", title: "Snapshot")
        container.mainContext.insert(track)
        try container.mainContext.save()
        let store = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await store.refresh()

        #expect(store.snapshot.tracks.map(\.title) == ["Snapshot"])
        #expect(store.resolveTrack(id: track.id) != nil)

        container.mainContext.delete(track)
        try container.mainContext.save()
        await store.refresh()
        #expect(store.resolveTrack(id: track.id) == nil)
        #expect(store.rebuildError == nil)
    }

    @Test("A stale album snapshot resolves its current reconciliation replacement")
    @MainActor
    func staleAlbumResolution() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let original = Album(title: "Original", artist: "Tester")
        let albumID = original.id
        context.insert(original)
        try context.save()
        let store = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await store.refresh()
        store.beginBulkUpdates()

        context.delete(original)
        try context.save()
        #expect(store.resolveAlbum(id: albumID) == nil)

        let replacement = Album(title: "Replacement", artist: "Tester")
        replacement.id = albumID
        context.insert(replacement)
        try context.save()

        let resolved = try #require(store.resolveAlbum(id: albumID))
        #expect(resolved.persistentModelID == replacement.persistentModelID)
        #expect(resolved.title == "Replacement")
    }

    @Test("Stale track snapshots exclude deletion and resolve current replacements")
    @MainActor
    func staleTrackResolution() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let original = Track(path: "/tmp/original-track.mp3", title: "Original")
        let trackID = original.id
        context.insert(original)
        try context.save()
        let store = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await store.refresh()
        store.beginBulkUpdates()

        context.delete(original)
        try context.save()
        #expect(store.resolveTrack(id: trackID) == nil)
        #expect(store.resolveTracks(ids: [trackID]).isEmpty)

        let replacement = Track(path: "/tmp/replacement-track.mp3", title: "Replacement")
        replacement.id = trackID
        context.insert(replacement)
        try context.save()

        let resolved = try #require(store.resolveTrack(id: trackID))
        let batch = store.resolveTracks(ids: [trackID, trackID])
        #expect(resolved.persistentModelID == replacement.persistentModelID)
        #expect(resolved.title == "Replacement")
        #expect(batch.map(\.persistentModelID) == [
            replacement.persistentModelID,
            replacement.persistentModelID,
        ])
    }

    @Test("Stale playlist snapshots exclude deletion and resolve current replacements")
    @MainActor
    func stalePlaylistResolution() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let original = Playlist(name: "Original")
        let playlistID = original.id
        context.insert(original)
        try context.save()
        let store = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await store.refresh()
        store.beginBulkUpdates()

        context.delete(original)
        try context.save()
        #expect(store.resolvePlaylist(id: playlistID) == nil)

        let replacement = Playlist(name: "Replacement")
        replacement.id = playlistID
        context.insert(replacement)
        try context.save()

        let resolved = try #require(store.resolvePlaylist(id: playlistID))
        #expect(resolved.persistentModelID == replacement.persistentModelID)
        #expect(resolved.name == "Replacement")
    }

    @Test("Save routing ignores unrelated entities and schedules relevant refreshes")
    @MainActor
    func saveRouting() throws {
        let container = try makeContainer()
        let store = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        container.mainContext.insert(Artist(name: "Artist only"))
        try container.mainContext.save()
        #expect(store.refreshRequestCount == 0)

        container.mainContext.insert(Track(path: "/tmp/routed.mp3", title: "Routed"))
        try container.mainContext.save()
        #expect(store.refreshRequestCount == 1)
    }

    @Test("Bounded track and favorite saves patch without a full catalog rebuild")
    @MainActor
    func boundedSnapshotPatches() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let album = Album(title: "Patch Album", artist: "Patch Artist")
        let track = Track(path: "/tmp/patch.mp3", title: "Patch Track")
        track.albumRelation = album
        album.tracks = [track]
        context.insert(album)
        context.insert(track)
        try context.save()

        let store = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await store.refresh()
        #expect(store.fullRebuildCount == 1)

        track.rating = 4
        try context.save()
        try await Task.sleep(for: .milliseconds(180))

        #expect(store.snapshot.tracksByID[track.id]?.rating == 4)
        #expect(store.snapshot.tracksByID[track.id]?.albumRating == 4)
        #expect(store.patchPublicationCount == 1)
        #expect(store.fullRebuildCount == 1)

        let trackFavorite = TrackFavorite(trackID: track.id)
        context.insert(trackFavorite)
        try context.save()
        try await Task.sleep(for: .milliseconds(180))
        #expect(store.snapshot.tracksByID[track.id]?.isLoved == true)
        #expect(store.patchPublicationCount == 2)

        let albumFavorite = AlbumFavorite(albumID: album.id)
        context.insert(albumFavorite)
        try context.save()
        try await Task.sleep(for: .milliseconds(180))
        #expect(store.snapshot.albumsByID[album.id]?.isFavorite == true)
        #expect(store.patchPublicationCount == 3)
        #expect(store.fullRebuildCount == 1)

        context.delete(trackFavorite)
        context.delete(albumFavorite)
        try context.save()
        try await Task.sleep(for: .milliseconds(180))
        #expect(store.snapshot.tracksByID[track.id]?.isLoved == false)
        #expect(store.snapshot.albumsByID[album.id]?.isFavorite == false)
        #expect(store.patchPublicationCount == 4)
        #expect(store.fullRebuildCount == 1)
    }

    @Test("Structural metadata and playlist changes patch their subsystem revisions")
    @MainActor
    func structuralSnapshotPatches() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let album = Album(title: "Original Album", artist: "Artist")
        let track = Track(path: "/tmp/structural.mp3", title: "Original Track")
        track.albumRelation = album
        album.tracks = [track]
        let playlist = Playlist(name: "Original Playlist")
        context.insert(album)
        context.insert(track)
        context.insert(playlist)
        try context.save()

        let store = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await store.refresh()
        let originalAlbumRevision = store.snapshot.albumStructureRevision
        let originalPlaylistRevision = store.snapshot.playlistRevision

        track.title = "Updated Track"
        album.artworkData = Data([0, 1, 2, 3])
        playlist.name = "Updated Playlist"
        try context.save()
        try await Task.sleep(for: .milliseconds(180))

        #expect(store.snapshot.tracksByID[track.id]?.title == "Updated Track")
        #expect(store.snapshot.albumsByID[album.id]?.artworkReference != nil)
        #expect(store.snapshot.playlistsByID[playlist.id]?.name == "Updated Playlist")
        #expect(store.snapshot.albumStructureRevision > originalAlbumRevision)
        #expect(store.snapshot.albumPresentationRevision > originalAlbumRevision)
        #expect(store.snapshot.playlistRevision > originalPlaylistRevision)
        #expect(store.patchPublicationCount == 1)
        #expect(store.fullRebuildCount == 1)

        let added = Track(path: "/tmp/added.mp3", title: "Added Track")
        added.albumRelation = album
        album.tracks.append(added)
        context.insert(added)
        try context.save()
        try await Task.sleep(for: .milliseconds(180))
        #expect(store.snapshot.tracksByID[added.id] != nil)
        #expect(store.snapshot.albumsByID[album.id]?.trackIDs.contains(added.id) == true)

        context.delete(added)
        try context.save()
        try await Task.sleep(for: .milliseconds(180))
        #expect(store.snapshot.tracksByID[added.id] == nil)
        #expect(store.snapshot.albumsByID[album.id]?.trackIDs.contains(added.id) == false)
        #expect(store.patchPublicationCount == 3)
        #expect(store.fullRebuildCount == 1)

        let addedAlbum = Album(title: "Inserted Album", artist: "Inserted Artist")
        let addedPlaylist = Playlist(name: "Inserted Playlist")
        let addedAlbumID = addedAlbum.id
        let addedPlaylistID = addedPlaylist.id
        context.insert(addedAlbum)
        context.insert(addedPlaylist)
        try context.save()
        try await Task.sleep(for: .milliseconds(180))
        #expect(store.snapshot.albumsByID[addedAlbumID]?.title == "Inserted Album")
        #expect(store.snapshot.playlistsByID[addedPlaylistID]?.name == "Inserted Playlist")

        context.delete(addedAlbum)
        context.delete(addedPlaylist)
        try context.save()
        try await Task.sleep(for: .milliseconds(180))
        #expect(store.snapshot.albumsByID[addedAlbumID] == nil)
        #expect(store.snapshot.playlistsByID[addedPlaylistID] == nil)
        #expect(store.patchPublicationCount == 5)
        #expect(store.fullRebuildCount == 1)
    }

    @Test("Oversized, invalidated, unknown, and failed patches use full rebuild policy")
    @MainActor
    func snapshotPatchFallbacks() async throws {
        let container = try makeContainer()
        let actor = LibrarySnapshotModelActor(modelContainer: container)
        let empty = LibrarySnapshot.empty
        #expect(try await actor.apply(
            changeSet: LibrarySnapshotChangeSet(invalidatedAll: true),
            to: empty,
            revision: 1
        ) == nil)
        #expect(try await actor.apply(
            changeSet: LibrarySnapshotChangeSet(isUnknown: true),
            to: empty,
            revision: 1
        ) == nil)

        let store = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await store.refresh()
        for index in 0..<257 {
            container.mainContext.insert(Track(
                path: "/tmp/oversized-\(index).mp3",
                title: "Oversized \(index)"
            ))
        }
        try container.mainContext.save()
        try await Task.sleep(for: .milliseconds(220))
        #expect(store.snapshot.tracks.count == 257)
        #expect(store.fullRebuildCount == 2)
        #expect(store.patchPublicationCount == 0)

        let failingContainer = try makeContainer()
        let failingStore = LibrarySnapshotStore(
            modelContainer: failingContainer,
            startsImmediately: false,
            snapshotBuilder: PatchFailingSnapshotBuilder()
        )
        await failingStore.refresh()
        failingContainer.mainContext.insert(Track(path: "/tmp/fallback.mp3", title: "Fallback"))
        try failingContainer.mainContext.save()
        try await Task.sleep(for: .milliseconds(180))
        #expect(failingStore.fullRebuildCount == 2)
        #expect(failingStore.patchPublicationCount == 0)
        #expect(failingStore.rebuildError == nil)
    }

    @Test("A failed rebuild preserves the last good snapshot")
    @MainActor
    func lastGoodSnapshot() async throws {
        let container = try makeContainer()
        let store = LibrarySnapshotStore(
            modelContainer: container,
            startsImmediately: false,
            snapshotBuilder: FlakySnapshotBuilder()
        )
        await store.refresh()
        let goodSnapshot = store.snapshot
        await store.refresh()

        #expect(store.snapshot == goodSnapshot)
        #expect(store.rebuildError != nil)
    }

    @Test("Album projection groups multi-disc values and retains available artwork")
    @MainActor
    func albumGrouping() async throws {
        let identifier = try fixtureIdentifier()
        let firstTrackID = UUID()
        let secondTrackID = UUID()
        let firstAlbumID = UUID()
        let secondAlbumID = UUID()
        let tracks = [
            LibraryTrackSnapshot(
                id: firstTrackID,
                persistentIdentifier: identifier,
                title: "First",
                artist: "Artist",
                album: "Collection Disc 1",
                year: 2001,
                trackNumber: 1,
                path: "/Music/Collection/Disc 1/01.m4a"
            ),
            LibraryTrackSnapshot(
                id: secondTrackID,
                persistentIdentifier: identifier,
                title: "Second",
                artist: "Artist",
                album: "Collection Disc 2",
                year: 2001,
                trackNumber: 1,
                path: "/Music/Collection/Disc 2/01.m4a"
            ),
        ]
        let albums = [
            LibraryAlbumSnapshot(
                id: firstAlbumID,
                persistentIdentifier: identifier,
                title: "Collection Disc 1",
                artist: "Artist",
                year: 2001,
                trackIDs: [firstTrackID],
                isFavorite: true
            ),
            LibraryAlbumSnapshot(
                id: secondAlbumID,
                persistentIdentifier: identifier,
                title: "Collection Disc 2",
                artist: "Artist",
                year: 2001,
                trackIDs: [secondTrackID],
                artworkReference: .album(id: secondAlbumID, persistentIdentifier: identifier)
            ),
        ]
        let groups = try await LibraryAlbumProjectionWorker().project(
            LibrarySnapshot(revision: 1, tracks: tracks, albums: albums, playlists: [])
        )

        #expect(groups.count == 1)
        #expect(groups.first?.trackIDs == [firstTrackID, secondTrackID])
        #expect(groups.first?.artworkReference != nil)
        #expect(groups.first?.year == 2001)
        #expect(groups.first?.isFavorite == false)

        let favoriteAlbums = albums.map { album in
            LibraryAlbumSnapshot(
                id: album.id,
                persistentIdentifier: album.persistentIdentifier,
                title: album.title,
                artist: album.artist,
                year: album.year,
                dateAdded: album.dateAdded,
                trackIDs: album.trackIDs,
                artworkReference: album.artworkReference,
                isFavorite: true
            )
        }
        let favoriteGroups = try await LibraryAlbumProjectionWorker().project(
            LibrarySnapshot(revision: 2, tracks: tracks, albums: favoriteAlbums, playlists: [])
        )
        #expect(favoriteGroups.first?.isFavorite == true)
    }

    @Test("Album routes resolve duplicate titles by representative album ID")
    @MainActor
    func albumRoutesUseIDs() async throws {
        let identifier = try fixtureIdentifier()
        let firstID = UUID()
        let secondID = UUID()
        let albums = [
            LibraryAlbumSnapshot(
                id: firstID,
                persistentIdentifier: identifier,
                title: "Greatest Hits",
                artist: "Artist One"
            ),
            LibraryAlbumSnapshot(
                id: secondID,
                persistentIdentifier: identifier,
                title: "Greatest Hits",
                artist: "Artist Two"
            ),
        ]

        let groups = try await LibraryAlbumProjectionWorker().project(
            LibrarySnapshot(revision: 1, tracks: [], albums: albums, playlists: [])
        )

        #expect(groups.first { $0.albumIDs.contains(firstID) }?.artist == "Artist One")
        #expect(groups.first { $0.albumIDs.contains(secondID) }?.artist == "Artist Two")
    }

    @Test("Album presentation changes redecorate without regrouping")
    @MainActor
    func albumPresentationOnlyUpdate() async throws {
        let identifier = try fixtureIdentifier()
        let albumID = UUID()
        let base = LibraryAlbumSnapshot(
            id: albumID,
            persistentIdentifier: identifier,
            title: "Presentation",
            artist: "Artist",
            isFavorite: false
        )
        let worker = LibraryAlbumProjectionWorker()
        let store = LibraryAlbumProjectionStore(worker: worker)
        await store.update(from: LibrarySnapshot(
            revision: 1,
            trackRevision: 1,
            albumStructureRevision: 1,
            albumPresentationRevision: 1,
            playlistRevision: 1,
            tracks: [],
            albums: [base],
            playlists: []
        ))

        await store.update(from: LibrarySnapshot(
            revision: 2,
            trackRevision: 1,
            albumStructureRevision: 1,
            albumPresentationRevision: 2,
            playlistRevision: 1,
            tracks: [],
            albums: [base.withFavorite(true)],
            playlists: []
        ))

        #expect(await worker.projectionCount() == 1)
        #expect(store.group(containing: albumID)?.isFavorite == true)
    }

    @Test("Playback clock changes do not publish through presentation or volume surfaces")
    @MainActor
    func narrowPlaybackSurfaces() {
        let clock = PlaybackClock()
        let volume = PlaybackVolumeState()
        let presentation = PlaybackPresentationState()
        var volumeChanges = 0
        var presentationChanges = 0
        let volumeToken = volume.objectWillChange.sink { volumeChanges += 1 }
        let presentationToken = presentation.objectWillChange.sink { presentationChanges += 1 }

        clock.update(position: 1, duration: 180)
        clock.update(position: 1, duration: 180)
        clock.update(position: 2, duration: 180)

        #expect(volumeChanges == 0)
        #expect(presentationChanges == 0)
        withExtendedLifetime((volumeToken, presentationToken)) {}
    }

    private func makeTracks(
        count: Int,
        identifier: PersistentIdentifier
    ) -> [LibraryTrackSnapshot] {
        (0..<count).map { index in
            LibraryTrackSnapshot(
                persistentIdentifier: identifier,
                title: "Song \(index)",
                artist: "Artist \(index % 20)",
                album: "Album \((index / 20) % 10)",
                genre: "Genre \((index / 200) % 5)",
                year: 1990 + (index % 30),
                trackNumber: index % 20,
                duration: TimeInterval(90 + index % 300),
                dateAdded: Date(timeIntervalSince1970: TimeInterval(index)),
                playCount: index % 17,
                rating: index.isMultiple(of: 7) ? 5 : 0
            )
        }
    }

    @MainActor
    private func fixtureIdentifier() throws -> PersistentIdentifier {
        let container = try makeContainer()
        let track = Track(path: "/tmp/fixture.mp3", title: "Fixture")
        container.mainContext.insert(track)
        try container.mainContext.save()
        return track.persistentModelID
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Track.self,
            Album.self,
            Artist.self,
            Playlist.self,
            AlbumFavorite.self,
            TrackFavorite.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

@Suite("Artwork thumbnail service", .serialized)
struct ArtworkThumbnailServiceTests {
    @Test("Packaged artwork does not evaluate the repository fallback")
    func packagedArtworkWins() {
        let expected = Data([0x53, 0x42])
        var evaluatedSwiftPackageFallback = false

        let actual = ArtworkThumbnailService.firstAvailableResourceData(
            packaged: { expected },
            swiftPackage: {
                evaluatedSwiftPackageFallback = true
                return nil
            }
        )

        #expect(actual == expected)
        #expect(evaluatedSwiftPackageFallback == false)
    }

    @Test("The bundled missing-album artwork decodes as a square thumbnail")
    @MainActor
    func missingAlbumArtwork() async throws {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let service = ArtworkThumbnailService(modelContainer: container)

        let image = await service.image(
            for: .missingAlbumArtwork,
            pointSize: CGSize(width: 160, height: 160),
            scale: 2
        )

        let thumbnail = try #require(image)
        #expect(thumbnail.width == thumbnail.height)
        #expect(thumbnail.width <= 320)
    }

    @Test("Thumbnails downsample, deduplicate in flight, obey limits, and invalidate by album")
    @MainActor
    func thumbnails() async throws {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let album = Album(title: "Artwork", artist: "Tester")
        let testFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Resources/songbird-logo.png")
        let artworkData = try Data(contentsOf: testFile)
        album.artworkData = artworkData
        container.mainContext.insert(album)
        try container.mainContext.save()
        let reference = ArtworkReference.album(
            id: album.id,
            persistentIdentifier: album.persistentModelID
        )
        let service = ArtworkThumbnailService(
            modelContainer: container,
            maximumImageCount: 2,
            maximumByteCost: 1_000_000
        )

        let images = await withTaskGroup(of: CGImage?.self, returning: [CGImage?].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await service.image(for: reference, pointSize: CGSize(width: 40, height: 40), scale: 2)
                }
            }
            var results: [CGImage?] = []
            for await image in group { results.append(image) }
            return results
        }
        #expect(images.allSatisfy { $0 != nil })
        #expect(images.compactMap { $0 }.allSatisfy { max($0.width, $0.height) <= 80 })
        #expect(await service.cacheMetrics().decodeCount == 1)

        _ = await service.image(for: reference, pointSize: CGSize(width: 30, height: 30), scale: 2)
        _ = await service.image(for: reference, pointSize: CGSize(width: 20, height: 20), scale: 2)
        #expect(await service.cacheMetrics().count <= 2)
        let logo = await service.image(
            for: .songbirdLogo,
            pointSize: CGSize(width: 24, height: 24),
            scale: 2
        )
        #expect(logo != nil)
        await service.invalidate(albumID: album.id)
        #expect(await service.cacheMetrics().count == 1)

        let remoteService = ArtworkThumbnailService(
            modelContainer: container,
            remoteArtworkLoader: { _ in artworkData }
        )
        let remote = await remoteService.image(
            for: .remote(URL(string: "https://example.invalid/cd-art.png")!),
            pointSize: CGSize(width: 32, height: 32),
            scale: 2
        )
        #expect(remote != nil)
    }

    @Test("Stale album artwork references resolve current data or fail closed")
    @MainActor
    func staleAlbumReference() async throws {
        // Given
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let original = Album(title: "Original", artist: "Tester")
        let albumID = original.id
        context.insert(original)
        try context.save()
        let staleReference = ArtworkReference.album(
            id: albumID,
            persistentIdentifier: original.persistentModelID
        )
        context.delete(original)
        try context.save()
        let service = ArtworkThumbnailService(modelContainer: container)

        // When
        let missing = await service.image(
            for: staleReference,
            pointSize: CGSize(width: 40, height: 40),
            scale: 2
        )

        // Then
        #expect(missing == nil)

        // Given
        let replacement = Album(title: "Replacement", artist: "Tester")
        replacement.id = albumID
        let testFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Resources/songbird-logo.png")
        replacement.artworkData = try Data(contentsOf: testFile)
        context.insert(replacement)
        try context.save()

        // When
        let current = await service.image(
            for: staleReference,
            pointSize: CGSize(width: 40, height: 40),
            scale: 2
        )

        // Then
        #expect(current != nil)
    }
}

@Suite("Import and maintenance cadence", .serialized)
struct ImportMaintenancePerformanceTests {
    @Test("Import progress suppresses bursts and force always publishes final state")
    func importCadence() async {
        let cadence = ImportProgressCadence()
        let first = await cadence.receive(processed: 1, total: 100)
        let burst = await cadence.receive(processed: 2, total: 100)
        let final = await cadence.receive(processed: 100, total: 100, force: true)

        #expect(first == ImportProgressCadenceDecision(publish: true, persist: true))
        #expect(burst == ImportProgressCadenceDecision(publish: false, persist: false))
        #expect(final == ImportProgressCadenceDecision(publish: true, persist: true))
    }

    @Test("Maintenance worker honors cancellation")
    @MainActor
    func maintenanceCancellation() async throws {
        let schema = Schema([Track.self, Album.self, Artist.self, Playlist.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        for index in 0..<1_000 {
            container.mainContext.insert(Track(path: "/missing/\(index).mp3", title: "\(index)"))
        }
        try container.mainContext.save()
        let service = LibraryMaintenanceService(modelContainer: container)
        let task = Task { try await service.removeMissingTracks() }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected maintenance cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }
}
