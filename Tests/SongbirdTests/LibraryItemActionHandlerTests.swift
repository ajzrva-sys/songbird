import SwiftData
import XCTest
@testable import SongbirdLib

@MainActor
final class LibraryItemActionHandlerTests: XCTestCase {
    func testAlbumDeletionSuppressesAutomaticReimportWithoutDeletingFiles() async throws {
        let suiteName = "songbird.explicit-removal-tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let exclusions = LibraryImportExclusionStore(suiteName: suiteName)
        let fixture = try await makeFixture(importExclusions: exclusions)
        defer { fixture.tearDown() }
        let paths = fixture.tracks.map(\.path)

        let result = fixture.actions.deleteAlbum(
            albumIDs: fixture.albumIDs,
            trackIDs: fixture.tracks.map(\.id)
        )

        if case .failure(let error) = result {
            XCTFail("Expected album deletion to succeed: \(error)")
        }
        XCTAssertTrue(paths.allSatisfy(exclusions.contains))
        XCTAssertTrue(paths.allSatisfy(FileManager.default.fileExists(atPath:)))
        XCTAssertEqual(
            try fixture.container.mainContext.fetchCount(FetchDescriptor<Track>()),
            0
        )
    }

    func testFinderAvailabilityUsesLibraryMembershipWithoutCheckingTheFile() async throws {
        let fixture = try await makeFixture(createsTemporaryFiles: false)
        defer { fixture.tearDown() }

        XCTAssertTrue(fixture.actions.canShowInFinder(trackIDs: [fixture.tracks[0].id]))
        XCTAssertTrue(fixture.actions.canRefreshMetadata(trackIDs: [fixture.tracks[0].id]))
    }

    func testShowInFinderReportsAnUnavailableSelectionWithoutRevealingIt() async throws {
        var revealedURLs: [URL] = []
        let fixture = try await makeFixture(
            createsTemporaryFiles: false,
            revealFiles: { revealedURLs = $0 }
        )
        defer {
            while LibraryStatus.shared.notices.notice != nil {
                LibraryStatus.shared.dismissCurrentNotice()
            }
            fixture.tearDown()
        }
        while LibraryStatus.shared.notices.notice != nil {
            LibraryStatus.shared.dismissCurrentNotice()
        }

        fixture.actions.showInFinder(trackIDs: [fixture.tracks[0].id])

        for _ in 0..<100 where LibraryStatus.shared.notices.notice == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(revealedURLs.isEmpty)
        XCTAssertEqual(
            LibraryStatus.shared.notices.notice?.message,
            "The selected file is unavailable."
        )
        XCTAssertEqual(LibraryStatus.shared.notices.notice?.severity, .warning)
    }

    func testShowInFinderResolvesExistingFilesBeforeRevealingThem() async throws {
        var revealedURLs: [URL] = []
        let fixture = try await makeFixture(revealFiles: { revealedURLs = $0 })
        defer { fixture.tearDown() }

        fixture.actions.showInFinder(trackIDs: [fixture.tracks[0].id])

        for _ in 0..<100 where revealedURLs.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(
            revealedURLs,
            [URL(fileURLWithPath: fixture.tracks[0].path).standardizedFileURL]
        )
    }

    func testMetadataRefreshReportsExistingUnreadableFileAsFailure() async throws {
        let fixture = try await makeFixture()
        defer {
            while LibraryStatus.shared.notices.notice != nil {
                LibraryStatus.shared.dismissCurrentNotice()
            }
            fixture.tearDown()
        }
        while LibraryStatus.shared.notices.notice != nil {
            LibraryStatus.shared.dismissCurrentNotice()
        }
        let validFixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/tone-48000-stereo-24-alac.m4a")
        let unreadableFixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Generated/corrupt-header.flac")
        try Data(contentsOf: validFixture).write(
            to: URL(fileURLWithPath: fixture.tracks[0].path),
            options: .atomic
        )
        fixture.tracks[1].path = unreadableFixture.path
        try fixture.container.mainContext.save()

        fixture.actions.refreshMetadata(trackIDs: [fixture.tracks[0].id, fixture.tracks[1].id])

        for _ in 0..<200 where LibraryStatus.shared.importProgress.value.isRunning {
            try await Task.sleep(for: .milliseconds(10))
        }
        let operation = LibraryStatus.shared.importProgress.value
        XCTAssertFalse(operation.isRunning)
        XCTAssertEqual(operation.completed, 2)
        XCTAssertEqual(operation.message, "Refreshed 1, unavailable 0, missing 0, failed 1")
        XCTAssertEqual(LibraryStatus.shared.notices.notice?.severity, .warning)
    }

    func testAlbumPlaybackCommandsPreserveOrderAndShuffleSetting() async throws {
        let fixture = try await makeFixture(relatesTracksToAlbums: false)
        let ids = fixture.tracks.map(\.id)

        fixture.actions.play(trackIDs: ids)
        XCTAssertEqual(fixture.session.queue.currentTrack?.id, ids[0])
        XCTAssertEqual(fixture.session.queue.upcomingTracks.map(\.id), Array(ids.dropFirst()))
        XCTAssertFalse(fixture.session.queue.shuffleEnabled)

        fixture.session.queue.shuffleEnabled = true
        fixture.actions.play(trackIDs: ids, shuffled: true)
        let shuffledIDs = [fixture.session.queue.currentTrack?.id].compactMap { $0 }
            + fixture.session.queue.upcomingTracks.map(\.id)
        XCTAssertEqual(Set(shuffledIDs), Set(ids))
        XCTAssertTrue(fixture.session.queue.shuffleEnabled)
        fixture.tearDown()
        try await Task.sleep(for: .milliseconds(50))
    }

    func testLargeAlbumPlaybackSkipsUnavailableLeadingTrack() async throws {
        let fixture = try await makeFixture(
            relatesTracksToAlbums: false,
            trackCount: 134,
            usesAudioCDSources: false
        )
        defer { fixture.tearDown() }
        try FileManager.default.removeItem(atPath: fixture.tracks[0].path)

        let result = fixture.actions.play(trackIDs: fixture.tracks.map(\.id))

        if case .failure(let error) = result {
            XCTFail("Expected album playback to skip its unavailable first track: \(error)")
        }
        XCTAssertEqual(fixture.session.queue.currentTrack?.id, fixture.tracks[1].id)
        XCTAssertEqual(
            fixture.session.queue.upcomingTracks.map(\.id),
            Array(fixture.tracks.dropFirst(2)).map(\.id)
        )
        XCTAssertFalse(fixture.session.queue.shuffleEnabled)
    }

    func testAlbumPlaybackWithNoAvailableTracksPreservesCurrentQueue() async throws {
        let fixture = try await makeFixture(
            relatesTracksToAlbums: false,
            usesAudioCDSources: false
        )
        defer { fixture.tearDown() }
        let current = fixture.tracks[0]
        let upcoming = fixture.tracks[1]
        fixture.session.queue.setStateForTesting(
            current: current,
            upcoming: [upcoming],
            history: []
        )
        for track in fixture.tracks {
            try FileManager.default.removeItem(atPath: track.path)
        }

        let result = fixture.actions.play(trackIDs: fixture.tracks.map(\.id))

        guard case .failure(.fileNotFound) = result else {
            XCTFail("Expected album playback to report that no track is available")
            return
        }
        XCTAssertEqual(fixture.session.queue.currentTrack?.id, current.id)
        XCTAssertEqual(fixture.session.queue.upcomingTracks.map(\.id), [upcoming.id])
    }

    func testPlaylistCommandsDeduplicateTracksAndRejectSmartPlaylistTargets() async throws {
        let fixture = try await makeFixture()
        defer { fixture.tearDown() }
        let context = fixture.container.mainContext
        let manual = Playlist(name: "Manual")
        manual.tracks = [fixture.tracks[0]]
        let smart = Playlist(name: "Smart")
        smart.smartPlaylist = true
        context.insert(manual)
        context.insert(smart)
        try context.save()
        await fixture.snapshots.refresh()

        let duplicateInput = [fixture.tracks[0].id, fixture.tracks[1].id, fixture.tracks[1].id]
        fixture.actions.addToPlaylist(trackIDs: duplicateInput, playlistID: manual.id)
        fixture.actions.addToPlaylist(trackIDs: duplicateInput, playlistID: smart.id)

        XCTAssertEqual(Set(manual.tracks.map(\.id)), Set([fixture.tracks[0].id, fixture.tracks[1].id]))
        XCTAssertEqual(manual.tracks.count, 2)
        XCTAssertTrue(smart.tracks.isEmpty)
        XCTAssertEqual(fixture.actions.manualPlaylists.map(\.id), [manual.id])
    }

    func testPlaylistLifecycleReturnsCountsAndRejectsStaleMutations() async throws {
        let fixture = try await makeFixture()
        defer { fixture.tearDown() }
        let playlist = Playlist(name: "Lifecycle")
        playlist.tracks = [fixture.tracks[0]]
        fixture.container.mainContext.insert(playlist)
        try fixture.container.mainContext.save()
        await fixture.snapshots.refresh()

        let missingID = UUID()
        let add = fixture.actions.addTracks(
            [fixture.tracks[0].id, fixture.tracks[1].id, fixture.tracks[1].id, missingID],
            toPlaylist: playlist.id
        )
        let summary = try add.get()
        XCTAssertEqual(summary, PlaylistAddSummary(
            requested: 4,
            added: 1,
            duplicateSkipped: 2,
            missing: 1
        ))
        XCTAssertEqual(Set(playlist.tracks.map(\.id)), Set([fixture.tracks[0].id, fixture.tracks[1].id]))

        if case .success = fixture.actions.renamePlaylist(
            playlistID: playlist.id,
            expectedName: "Stale Name",
            newName: "Wrong"
        ) {
            XCTFail("A stale rename must be refused")
        }
        XCTAssertEqual(playlist.name, "Lifecycle")

        let expected = PlaylistOrderStore.order(
            playlistID: playlist.id,
            membership: playlist.tracks.map(\.id)
        )
        if case .success = fixture.actions.reorderPlaylist(
            playlistID: playlist.id,
            expectedOrder: Array(expected.reversed()),
            newOrder: expected
        ) {
            XCTFail("A stale reorder must be refused")
        }
        XCTAssertEqual(
            PlaylistOrderStore.order(playlistID: playlist.id, membership: playlist.tracks.map(\.id)),
            expected
        )

        XCTAssertNoThrow(try fixture.actions.reorderPlaylist(
            playlistID: playlist.id,
            expectedOrder: expected,
            newOrder: Array(expected.reversed())
        ).get())
        XCTAssertEqual(
            PlaylistOrderStore.order(playlistID: playlist.id, membership: playlist.tracks.map(\.id)),
            Array(expected.reversed())
        )

        XCTAssertNoThrow(try fixture.actions.removeTracks(
            [fixture.tracks[0].id],
            fromPlaylist: playlist.id
        ).get())
        XCTAssertEqual(playlist.tracks.map(\.id), [fixture.tracks[1].id])
    }

    func testSystemPlaylistIsImmutableThroughSharedBoundary() async throws {
        let fixture = try await makeFixture()
        defer { fixture.tearDown() }
        let playlist = Playlist(name: "System", smart: true, systemKey: "system.test")
        fixture.container.mainContext.insert(playlist)
        try fixture.container.mainContext.save()
        await fixture.snapshots.refresh()

        if case .success = fixture.actions.renamePlaylist(
            playlistID: playlist.id,
            expectedName: "System",
            newName: "Changed"
        ) { XCTFail("System playlist rename must fail") }
        if case .success = fixture.actions.deletePlaylist(playlistID: playlist.id) {
            XCTFail("System playlist delete must fail")
        }
        XCTAssertEqual(playlist.name, "System")
        XCTAssertNotNil(fixture.snapshots.resolvePlaylist(id: playlist.id))
    }

    func testManualPlaylistPlaybackPreservesStoredOrder() async throws {
        let fixture = try await makeFixture()
        defer { fixture.tearDown() }
        let playlist = Playlist(name: "Ordered Playlist")
        playlist.tracks = [fixture.tracks[2], fixture.tracks[0], fixture.tracks[3]]
        fixture.container.mainContext.insert(playlist)
        try fixture.container.mainContext.save()
        await fixture.snapshots.refresh()
        let expected = try XCTUnwrap(
            fixture.snapshots.snapshot.playlists.first(where: { $0.id == playlist.id })
        ).trackIDs

        let result = fixture.actions.play(playlistID: playlist.id)

        if case .failure(let error) = result {
            XCTFail("Expected manual playlist playback to start: \(error)")
        }
        XCTAssertEqual(fixture.session.queue.currentTrack?.id, expected.first)
        XCTAssertEqual(fixture.session.queue.upcomingTracks.map(\.id), Array(expected.dropFirst()))
    }

    func testSmartPlaylistPlaybackResolvesCurrentRules() async throws {
        let fixture = try await makeFixture()
        defer { fixture.tearDown() }
        fixture.tracks[0].genre = "Electronic"
        fixture.tracks[1].genre = "Jazz"
        fixture.tracks[2].genre = "Electronic"
        fixture.tracks[3].genre = "Classical"
        let playlist = Playlist(name: "Electronic", smart: true)
        playlist.smartPlaylistRules = try SmartPlaylistRuleSet(conditions: [
            SmartCondition(field: .genre, op: .equals, value: "Electronic")
        ]).encode()
        fixture.container.mainContext.insert(playlist)
        try fixture.container.mainContext.save()
        await fixture.snapshots.refresh()
        let expected = fixture.snapshots.snapshot.tracks
            .filter { $0.genre == "Electronic" }
            .map(\.id)

        let result = fixture.actions.play(playlistID: playlist.id)

        if case .failure(let error) = result {
            XCTFail("Expected smart playlist playback to start: \(error)")
        }
        let queued = [fixture.session.queue.currentTrack?.id].compactMap { $0 }
            + fixture.session.queue.upcomingTracks.map(\.id)
        XCTAssertEqual(queued, expected)
    }

    func testMissingPlaylistPlaybackPreservesCurrentQueue() async throws {
        let fixture = try await makeFixture()
        defer { fixture.tearDown() }
        fixture.session.queue.setStateForTesting(
            current: fixture.tracks[0],
            upcoming: [fixture.tracks[1]],
            history: []
        )

        let result = fixture.actions.play(playlistID: UUID())

        guard case .failure(.emptySelection) = result else {
            XCTFail("Expected a missing playlist to fail as an empty selection")
            return
        }
        XCTAssertEqual(fixture.session.queue.currentTrack?.id, fixture.tracks[0].id)
        XCTAssertEqual(fixture.session.queue.upcomingTracks.map(\.id), [fixture.tracks[1].id])
    }

    func testSidebarPlaylistTargetingRetainsRequestUntilEditablePlaylistSucceeds() async throws {
        let fixture = try await makeFixture()
        defer { fixture.tearDown() }
        let context = fixture.container.mainContext
        let manual = Playlist(name: "Road Trip")
        let smart = Playlist(name: "Automatic")
        smart.smartPlaylist = true
        context.insert(manual)
        context.insert(smart)
        try context.save()
        await fixture.snapshots.refresh()

        let sourceID = "album:test-source"
        let targetTrackIDs = [fixture.tracks[0].id, fixture.tracks[1].id]
        fixture.actions.beginSidebarPlaylistTargeting(
            sourceID: sourceID,
            sourceName: "Source Album",
            trackIDs: targetTrackIDs
        )

        XCTAssertEqual(fixture.actions.sidebarPlaylistTargetRequest?.sourceID, sourceID)
        if case .success = fixture.actions.addSidebarTargetToPlaylist(playlistID: smart.id) {
            XCTFail("A smart playlist must not accept a sidebar target")
        }
        XCTAssertNotNil(fixture.actions.sidebarPlaylistTargetRequest)

        if case .failure(let error) = fixture.actions.addSidebarTargetToPlaylist(playlistID: manual.id) {
            XCTFail("Expected the manual playlist to accept the target: \(error)")
        }
        XCTAssertNil(fixture.actions.sidebarPlaylistTargetRequest)
        XCTAssertEqual(Set(manual.tracks.map(\.id)), Set(targetTrackIDs))
    }

    func testCreatingPlaylistForSidebarTargetUsesTracksAndEndsTargeting() async throws {
        let fixture = try await makeFixture()
        defer { fixture.tearDown() }
        let trackIDs = [fixture.tracks[1].id, fixture.tracks[3].id]
        fixture.actions.beginSidebarPlaylistTargeting(
            sourceID: "album:new-playlist-source",
            sourceName: "Source Album",
            trackIDs: trackIDs
        )
        fixture.actions.requestNewPlaylistForSidebarTarget()
        let request = try XCTUnwrap(fixture.actions.playlistCreationRequest)

        let result = fixture.actions.createPlaylist(name: "New Album Mix", request: request)

        if case .failure(let error) = result {
            XCTFail("Expected playlist creation to succeed: \(error)")
        }
        XCTAssertNil(fixture.actions.sidebarPlaylistTargetRequest)
        XCTAssertNil(fixture.actions.playlistCreationRequest)
        await fixture.snapshots.refresh()
        let playlist = try XCTUnwrap(fixture.actions.manualPlaylists.first { $0.name == "New Album Mix" })
        XCTAssertEqual(Set(playlist.trackIDs), Set(trackIDs))
    }

    func testMultiDiscFavoriteToggleCreatesAndRemovesEveryRecord() async throws {
        let fixture = try await makeFixture(albumCount: 2)
        defer { fixture.tearDown() }
        let albumIDs = fixture.albumIDs

        fixture.actions.setAlbumFavorite(true, albumIDs: albumIDs)
        var records = try fixture.container.mainContext.fetch(FetchDescriptor<AlbumFavorite>())
        XCTAssertEqual(Set(records.map(\.albumID)), Set(albumIDs))

        fixture.actions.setAlbumFavorite(false, albumIDs: albumIDs)
        records = try fixture.container.mainContext.fetch(FetchDescriptor<AlbumFavorite>())
        XCTAssertTrue(records.isEmpty)
    }

    func testDuplicateConsolidationMergesCatalogStateAndPreservesOccurrences() async throws {
        let suiteName = "songbird.duplicate-consolidation.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let exclusions = LibraryImportExclusionStore(suiteName: suiteName)
        let fixture = try await makeFixture(importExclusions: exclusions)
        defer { fixture.tearDown() }
        let context = fixture.container.mainContext
        let keeper = fixture.tracks[0]
        let redundant = fixture.tracks[1]
        keeper.checksum = "verified-full-sha256"
        redundant.checksum = keeper.checksum
        keeper.rating = 2
        redundant.rating = 5
        keeper.playCount = 3
        redundant.playCount = 7
        keeper.dateAdded = Date(timeIntervalSince1970: 20)
        redundant.dateAdded = Date(timeIntervalSince1970: 10)
        redundant.lastPlayed = Date(timeIntervalSince1970: 50)
        let playlist = Playlist(name: "Duplicates")
        playlist.tracks = [redundant, keeper, redundant]
        context.insert(playlist)
        context.insert(TrackFavorite(trackID: redundant.id))
        try context.save()
        await fixture.snapshots.refresh()
        fixture.session.queue.setStateForTesting(
            current: keeper,
            upcoming: [keeper, redundant],
            history: [redundant]
        )
        let queueBefore = fixture.session.queue.identitySnapshot()

        let result = await fixture.actions.consolidateDuplicateTracks(
            trackIDs: [keeper.id, redundant.id],
            keeperID: keeper.id,
            expectedChecksum: keeper.checksum
        )
        guard case .success(let outcome) = result else {
            XCTFail("Expected duplicate consolidation to succeed: \(result)")
            return
        }
        XCTAssertEqual(outcome.affectedTrackCount, 1)

        let appliedContext = ModelContext(fixture.container)
        let appliedTracks = try appliedContext.fetch(FetchDescriptor<Track>())
        let appliedKeeper = try XCTUnwrap(appliedTracks.first { $0.id == keeper.id })
        XCTAssertEqual(appliedTracks.count, 3)
        XCTAssertEqual(appliedKeeper.rating, 5)
        XCTAssertEqual(appliedKeeper.playCount, 10)
        XCTAssertEqual(appliedKeeper.dateAdded, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(appliedKeeper.lastPlayed, Date(timeIntervalSince1970: 50))
        // SwiftData relationships retain membership, not repeated occurrences.
        XCTAssertEqual(
            try appliedContext.fetch(FetchDescriptor<Playlist>())
                .first { $0.id == playlist.id }?.tracks.map(\.id),
            [keeper.id]
        )
        XCTAssertEqual(fixture.session.queue.currentTrack?.id, keeper.id)
        XCTAssertEqual(fixture.session.queue.upcomingTracks.map(\.id), [keeper.id, keeper.id])
        XCTAssertEqual(fixture.session.queue.history.map(\.id), [keeper.id])
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<TrackFavorite>()).map(\.trackID),
            [keeper.id]
        )
        XCTAssertTrue(exclusions.contains(redundant.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: redundant.path))

        let undo = await fixture.actions.undoLatestHealthMutation()
        guard case .success = undo else {
            XCTFail("Expected duplicate Undo to succeed: \(undo)")
            return
        }
        let restoredContext = ModelContext(fixture.container)
        let restoredTracks = try restoredContext.fetch(FetchDescriptor<Track>())
        let restoredKeeper = try XCTUnwrap(restoredTracks.first { $0.id == keeper.id })
        let restoredRedundant = try XCTUnwrap(restoredTracks.first { $0.id == redundant.id })
        XCTAssertEqual(restoredKeeper.rating, 2)
        XCTAssertEqual(restoredKeeper.playCount, 3)
        XCTAssertEqual(restoredRedundant.rating, 5)
        XCTAssertEqual(restoredRedundant.playCount, 7)
        XCTAssertEqual(fixture.session.queue.identitySnapshot(), queueBefore)
        XCTAssertFalse(exclusions.contains(redundant.path))
        XCTAssertTrue(try restoredContext.fetch(FetchDescriptor<TrackFavorite>())
            .contains { $0.trackID == redundant.id })
    }

    func testDuplicateConsolidationRejectsFastFingerprintCollision() async throws {
        let fixture = try await makeFixture()
        defer { fixture.tearDown() }
        let keeper = fixture.tracks[0]
        let other = fixture.tracks[1]
        keeper.checksum = "candidate-collision"
        other.checksum = keeper.checksum
        try Data([1, 2, 3]).write(to: URL(fileURLWithPath: keeper.path))
        try Data([9, 8, 7]).write(to: URL(fileURLWithPath: other.path))
        try fixture.container.mainContext.save()
        await fixture.snapshots.refresh()

        let result = await fixture.actions.consolidateDuplicateTracks(
            trackIDs: [keeper.id, other.id],
            keeperID: keeper.id,
            expectedChecksum: keeper.checksum
        )
        guard case .failure(.duplicateContentChanged) = result else {
            XCTFail("Expected byte-verification refusal: \(result)")
            return
        }
        XCTAssertNotNil(fixture.snapshots.resolveTrack(id: keeper.id))
        XCTAssertNotNil(fixture.snapshots.resolveTrack(id: other.id))
    }

    func testHealthMissingRemovalRestoresQueuePlaylistFavoriteAndExclusion() async throws {
        let suiteName = "songbird.health-removal.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let exclusions = LibraryImportExclusionStore(suiteName: suiteName)
        let fixture = try await makeFixture(
            createsTemporaryFiles: false,
            importExclusions: exclusions
        )
        defer { fixture.tearDown() }
        let target = fixture.tracks[1]
        let playlist = Playlist(name: "Health Receipt")
        playlist.tracks = [fixture.tracks[0], target]
        fixture.container.mainContext.insert(playlist)
        fixture.container.mainContext.insert(TrackFavorite(trackID: target.id))
        try fixture.container.mainContext.save()
        PlaylistOrderStore.set([target.id, fixture.tracks[0].id], playlistID: playlist.id)
        defer { PlaylistOrderStore.remove(playlistID: playlist.id) }
        await fixture.snapshots.refresh()
        fixture.session.queue.setStateForTesting(
            current: fixture.tracks[0],
            upcoming: [target, fixture.tracks[2]],
            history: [target]
        )
        let beforeQueue = fixture.session.queue.identitySnapshot()

        let applied = await fixture.actions.removeMissingCatalogRecords([
            LibraryMissingRecordRemoval(
                trackID: target.id,
                expectedPath: target.path,
                sourceRevision: fixture.snapshots.snapshot.revision
            ),
        ])
        guard case .success = applied else {
            XCTFail("Expected catalog-only removal to succeed: \(applied)")
            return
        }
        XCTAssertNil(fixture.snapshots.resolveTrack(id: target.id))
        XCTAssertTrue(exclusions.contains(target.path))
        XCTAssertFalse(fixture.session.queue.identitySnapshot().upcoming.contains { $0.trackID == target.id })

        let undone = await fixture.actions.undoLatestHealthMutation()
        guard case .success = undone else {
            XCTFail("Expected Health Undo to succeed: \(undone)")
            return
        }
        XCTAssertNotNil(fixture.snapshots.resolveTrack(id: target.id))
        XCTAssertFalse(exclusions.contains(target.path))
        XCTAssertEqual(fixture.session.queue.identitySnapshot(), beforeQueue)
        let context = ModelContext(fixture.container)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TrackFavorite>()).contains { $0.trackID == target.id })
        XCTAssertTrue(try context.fetch(FetchDescriptor<Playlist>())
            .first { $0.id == playlist.id }?.tracks.contains { $0.id == target.id } == true)
        XCTAssertEqual(
            PlaylistOrderStore.order(playlistID: playlist.id, membership: [fixture.tracks[0].id, target.id]),
            [target.id, fixture.tracks[0].id]
        )
    }

    func testHealthMissingRemovalRefusesCurrentDecoder() async throws {
        let fixture = try await makeFixture(createsTemporaryFiles: false)
        defer { fixture.tearDown() }
        let target = fixture.tracks[0]
        fixture.session.queue.setStateForTesting(current: target, upcoming: [], history: [])

        let result = await fixture.actions.removeMissingCatalogRecords([
            LibraryMissingRecordRemoval(
                trackID: target.id,
                expectedPath: target.path,
                sourceRevision: fixture.snapshots.snapshot.revision
            ),
        ])
        guard case .failure(.currentlyPlaying(let id)) = result else {
            XCTFail("Expected current decoder refusal: \(result)")
            return
        }
        XCTAssertEqual(id, target.id)
        XCTAssertNotNil(fixture.snapshots.resolveTrack(id: target.id))
    }

    func testHealthMissingRemovalUndoRefusesQueueDriftWithoutPartialRestore() async throws {
        let suiteName = "songbird.health-removal-drift.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let exclusions = LibraryImportExclusionStore(suiteName: suiteName)
        let fixture = try await makeFixture(
            createsTemporaryFiles: false,
            importExclusions: exclusions
        )
        defer { fixture.tearDown() }
        let target = fixture.tracks[1]
        fixture.session.queue.setStateForTesting(
            current: fixture.tracks[0],
            upcoming: [target],
            history: []
        )
        let applied = await fixture.actions.removeMissingCatalogRecords([
            LibraryMissingRecordRemoval(
                trackID: target.id,
                expectedPath: target.path,
                sourceRevision: fixture.snapshots.snapshot.revision
            ),
        ])
        guard case .success = applied else { return XCTFail("Apply failed: \(applied)") }
        _ = fixture.session.queue.enqueue(fixture.tracks[2...2].map { $0 })

        let undone = await fixture.actions.undoLatestHealthMutation()
        guard case .failure(.crossDomainDrift) = undone else {
            XCTFail("Expected queue drift refusal: \(undone)")
            return
        }
        XCTAssertNil(fixture.snapshots.resolveTrack(id: target.id))
        XCTAssertTrue(exclusions.contains(target.path))
        XCTAssertTrue(fixture.actions.healthUndoAvailable)
    }

    func testDiscogsGenreActionFillsMissingAndRefreshesSnapshot() async throws {
        let fixture = try await makeFixture(createsTemporaryFiles: false)
        defer { fixture.tearDown() }
        let album = try XCTUnwrap(fixture.container.mainContext.fetch(FetchDescriptor<Album>()).first)
        fixture.tracks[1].genre = "JAZZ"
        try fixture.container.mainContext.save()
        let suggestion = DiscogsGenreAlbumSuggestion(album: DiscogsArtworkAlbumTarget(album: album), genre: " jazz ",
            evidence: DiscogsContentEvidence(releaseID: 1, fetches: [TestDiscogsClock.stamp()]))
        let result = await fixture.actions.applyDiscogsGenres([suggestion], clock: { TestDiscogsClock.stamp() })
        XCTAssertEqual(try result.get().appliedAlbums, 1)
        XCTAssertTrue(fixture.tracks.allSatisfy { $0.genre == "JAZZ" })
        XCTAssertTrue(try ModelContext(fixture.container).fetch(FetchDescriptor<Track>()).allSatisfy { $0.genre == "JAZZ" })
        let expired = await fixture.actions.applyDiscogsGenres([suggestion], clock: { TestDiscogsClock.stamp(18_000) })
        guard case .failure(.remoteEvidenceExpired) = expired else { return XCTFail("Expiry must remain typed") }
    }

    func testDiscogsYearActionUsesStableMissingOnlyBoundary() async throws {
        let fixture = try await makeFixture(createsTemporaryFiles: false)
        defer { fixture.tearDown() }
        let album = try XCTUnwrap(fixture.container.mainContext.fetch(FetchDescriptor<Album>()).first)
        album.year = 0
        fixture.tracks[1].year = 2002
        try fixture.container.mainContext.save()
        let suggestion = DiscogsYearSuggestion(album: DiscogsArtworkAlbumTarget(album: album), year: 1999,
            evidence: DiscogsContentEvidence(releaseID: 1, fetches: [TestDiscogsClock.stamp()]))
        let result = await fixture.actions.applyDiscogsYears([suggestion], clock: { TestDiscogsClock.stamp() })
        XCTAssertEqual(try result.get().appliedAlbums, 1)
        XCTAssertEqual(album.year, 1999)
        XCTAssertEqual(fixture.tracks[0].year, 1999)
        XCTAssertEqual(fixture.tracks[1].year, 2002)
        let expired = await fixture.actions.applyDiscogsYears([suggestion], clock: { TestDiscogsClock.stamp(18_000) })
        guard case .failure(.remoteEvidenceExpired) = expired else { return XCTFail("Expiry must remain typed") }
    }

    func testDiscogsArtworkActionSamplesInjectedClockAndPreservesUndo() async throws {
        let fixture = try await makeFixture(createsTemporaryFiles: false)
        defer { fixture.tearDown() }
        let album = try XCTUnwrap(fixture.container.mainContext.fetch(FetchDescriptor<Album>()).first)
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let change = LibraryArtworkChange(albumID: album.id, expectedArtworkDigest: nil, imageData: image,
            discogsEvidence: DiscogsContentEvidence(releaseID: 1, fetches: [TestDiscogsClock.stamp()]))
        let result = await fixture.actions.applyArtwork([change], clock: { TestDiscogsClock.stamp() })
        guard case .success(let outcome) = result else { return XCTFail("Injected acquisition should be fresh: \(result)") }
        XCTAssertEqual(outcome.affectedAlbumCount, 1)
        XCTAssertTrue(fixture.actions.healthUndoAvailable)
        let undone = await fixture.actions.undoLatestHealthMutation()
        guard case .success = undone else { return XCTFail("Saved artwork Undo must not require provider evidence") }
        XCTAssertNil(try ModelContext(fixture.container).fetch(FetchDescriptor<Album>()).first?.artworkData)
    }

    private func makeFixture(
        albumCount: Int = 1,
        relatesTracksToAlbums: Bool = true,
        trackCount: Int = 4,
        usesAudioCDSources: Bool = true,
        createsTemporaryFiles: Bool = true,
        importExclusions: LibraryImportExclusionStore = .shared,
        revealFiles: @escaping @MainActor ([URL]) -> Void = { _ in }
    ) async throws -> ActionFixture {
        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let temporaryPaths = (1...trackCount).map {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("songbird-action-\(UUID().uuidString)-\($0).m4a")
                .path
        }
        if createsTemporaryFiles {
            for path in temporaryPaths {
                _ = FileManager.default.createFile(atPath: path, contents: Data())
            }
        }
        let tracks = zip(1...trackCount, temporaryPaths).map { index, path in
            Track(path: path, title: "Track \(index)")
        }
        let albums = (1...albumCount).map {
            Album(title: "Album Disc \($0)", artist: "Artist", year: 2001)
        }
        let albumIDs = albums.map(\.id)
        for album in albums { context.insert(album) }
        for (index, track) in tracks.enumerated() {
            track.trackNumber = index + 1
            if relatesTracksToAlbums {
                track.albumRelation = albums[index % albums.count]
            }
            if usesAudioCDSources {
                track.audioCDSource = AudioCDSource(
                    discID: DiscIdentifier("action-handler-tests"),
                    deviceID: "test-drive",
                    trackNumber: index + 1,
                    startSector: Int64(index * 75),
                    endSector: Int64((index + 1) * 75)
                )
            }
            context.insert(track)
        }
        try context.save()

        let snapshots = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await snapshots.refresh()
        let session = PlaybackSession(backend: ActionRecordingBackend())
        let navigation = LibraryNavigationCoordinator()
        let actions = LibraryItemActionHandler(
            modelContainer: container,
            playbackSession: session,
            librarySnapshots: snapshots,
            navigation: navigation,
            importExclusions: importExclusions,
            revealFiles: revealFiles
        )
        return ActionFixture(
            container: container,
            snapshots: snapshots,
            session: session,
            actions: actions,
            tracks: tracks,
            albumIDs: albumIDs,
            temporaryAudioPaths: temporaryPaths
        )
    }
}

@MainActor
private struct ActionFixture {
    let container: ModelContainer
    let snapshots: LibrarySnapshotStore
    let session: PlaybackSession
    let actions: LibraryItemActionHandler
    let tracks: [Track]
    let albumIDs: [UUID]
    let temporaryAudioPaths: [String]

    func tearDown() {
        session.engine.stop()
        session.queue.clear()
        for path in temporaryAudioPaths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}

@MainActor
private final class ActionRecordingBackend: PlayerBackend {
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var isPaused = false
    var volume: Double = 1
    var onTrackBegan: ((AudioSource?) -> Void)?
    var onTrackFinished: (() -> Void)?
    var onError: ((String) -> Void)?

    func prepare() throws {}
    func shutdown() {}
    func play(_ source: AudioSource, durationHint: TimeInterval) throws { isPlaying = true }
    func pause() { isPaused = true }
    func resume() { isPaused = false }
    func stop() { isPlaying = false }
    func seek(to time: TimeInterval) { position = time }
    func setNextSource(_ source: AudioSource?, crossfadeDuration: TimeInterval) {}
}
