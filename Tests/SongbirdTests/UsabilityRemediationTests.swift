import AppKit
import Foundation
import Testing
@testable import SongbirdLib

@Suite("Global usability remediation", .serialized)
struct UsabilityRemediationTests {
    @Test("Destination summaries ignore inactive owners and clear only their owner")
    @MainActor
    func destinationSummaryOwnership() {
        let state = LibrarySummaryState()
        let tracks = LibraryContentSummaryOwner()
        let albums = LibraryContentSummaryOwner()

        state.activate(owner: tracks)
        state.update(owner: tracks, summary: .tracks(count: 9, duration: 90))
        #expect(state.summary == .tracks(count: 9, duration: 90))

        state.activate(owner: albums, initial: .albums(albumCount: 0, trackCount: 0))
        state.update(owner: tracks, summary: .tracks(count: 99, duration: 999))
        #expect(state.summary == .albums(albumCount: 0, trackCount: 0))

        state.clear(owner: tracks)
        #expect(state.summary == .albums(albumCount: 0, trackCount: 0))
        state.clear(owner: albums)
        #expect(state.summary == .none)
    }

    @Test("Destination summary wording reflects its content type")
    func destinationSummaryFormatting() {
        #expect(LibraryContentSummary.tracks(count: 0, duration: 0).text == "0 tracks · 0:00")
        #expect(LibraryContentSummary.albums(albumCount: 5, trackCount: 14).text == "5 albums · 14 tracks")
        #expect(LibraryContentSummary.healthDetail(findingCount: 3, affectedTrackCount: 8).text == "3 findings · 8 affected tracks")
    }

    @Test("Filter browser heights snap to complete rows")
    func filterHeightSnapping() {
        #expect(CascadeFilterHeightPolicy.resolve(requested: 80, maximum: 400) == 78)
        #expect(CascadeFilterHeightPolicy.resolve(requested: 134, maximum: 400) == 134)
        #expect(CascadeFilterHeightPolicy.resolve(requested: 120, maximum: 400) == 134)
        #expect(CascadeFilterHeightPolicy.resolve(requested: 400, maximum: 130) == 106)
        #expect(CascadeFilterHeightPolicy.resolve(requested: -20, maximum: 400) == 78)
    }

    @Test("Artwork placeholders disappear when the requested image has loaded")
    func artworkPlaceholderLifecycle() {
        #expect(ArtworkThumbnailPlaceholderPolicy.showsSymbol(hasLoadedImage: false))
        #expect(!ArtworkThumbnailPlaceholderPolicy.showsSymbol(hasLoadedImage: true))
    }

    @Test("Window and pane layout policies preserve the locked minimum geometry")
    func windowPaneGeometry() {
        #expect(PlayerWindowLayoutPolicy.minimumWidth(sidebarShown: false, rightPaneShown: false) == 760)
        #expect(PlayerWindowLayoutPolicy.minimumWidth(sidebarShown: true, rightPaneShown: false) == 760)
        #expect(PlayerWindowLayoutPolicy.minimumWidth(sidebarShown: false, rightPaneShown: true) == 768)
        #expect(PlayerWindowLayoutPolicy.minimumWidth(sidebarShown: true, rightPaneShown: true) == 956)

        let minimum = PlayerWindowLayoutPolicy.paneWidths(
            totalWidth: 956,
            sidebarShown: true,
            rightPaneShown: true,
            desiredSidebar: 420,
            desiredRightPane: 360
        )
        #expect(minimum.sidebar == 180)
        #expect(minimum.rightPane == 200)

        let roomy = PlayerWindowLayoutPolicy.paneWidths(
            totalWidth: 1_340,
            sidebarShown: true,
            rightPaneShown: true,
            desiredSidebar: 420,
            desiredRightPane: 360
        )
        #expect(roomy.sidebar == 420)
        #expect(roomy.rightPane == 344)
        #expect(PlayerWindowLayoutPolicy.sidebarArtworkSide(sidebarWidth: 260, windowHeight: 520) == 260)
        #expect(PlayerWindowLayoutPolicy.sidebarArtworkSide(sidebarWidth: 420, windowHeight: 900) == 420)
        #expect(PlayerWindowLayoutPolicy.sidebarArtworkSide(sidebarWidth: 180, windowHeight: 450) == 180)
        #expect(PlayerWindowLayoutPolicy.sidebarArtworkSide(sidebarWidth: 420, windowHeight: 520) == nil)
        #expect(PlayerWindowLayoutPolicy.sidebarArtworkSide(sidebarWidth: 100, windowHeight: 900) == nil)
    }

    @Test("The main Play button starts visible or selected content only when the queue is empty")
    func primaryTransportStartsVisibleAlbum() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        #expect(PrimaryTransportActionResolver.resolve(
            queueHasCurrentTrack: false,
            queueHasUpcomingTracks: false,
            visibleAlbumTrackIDs: [first, second],
            selectedTrackID: nil
        ) == .playTracks([first, second]))
        #expect(PrimaryTransportActionResolver.resolve(
            queueHasCurrentTrack: true,
            queueHasUpcomingTracks: false,
            visibleAlbumTrackIDs: [first, second],
            selectedTrackID: first
        ) == .togglePlayPause)
        #expect(PrimaryTransportActionResolver.resolve(
            queueHasCurrentTrack: false,
            queueHasUpcomingTracks: true,
            visibleAlbumTrackIDs: [first, second],
            selectedTrackID: first
        ) == .togglePlayPause)
        #expect(PrimaryTransportActionResolver.resolve(
            queueHasCurrentTrack: false,
            queueHasUpcomingTracks: false,
            visibleAlbumTrackIDs: nil,
            selectedTrackID: nil
        ) == .togglePlayPause)
        #expect(PrimaryTransportActionResolver.resolve(
            queueHasCurrentTrack: false,
            queueHasUpcomingTracks: false,
            visibleAlbumTrackIDs: nil,
            selectedTrackID: second
        ) == .playTracks([second]))
        #expect(PrimaryTransportActionResolver.resolve(
            queueHasCurrentTrack: false,
            queueHasUpcomingTracks: false,
            visibleAlbumTrackIDs: [first, second],
            selectedTrackID: second
        ) == .playTracks([first, second]))
    }

    @Test("A visible library selection retains stable identity without a resolved model")
    @MainActor
    func librarySelectionRetainsStableIdentity() {
        let selectedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let selection = LibrarySelectionState()

        selection.updateLibrarySelection(trackID: selectedID, track: nil)

        #expect(selection.selectedLibraryTrackID == selectedID)
        #expect(selection.selectedTrack == nil)
    }

    @Test("Player sliders clamp and use five-second and five-percent increments")
    func playerSliderRules() {
        #expect(PlayerSliderBehavior.clamp(-0.5) == 0)
        #expect(PlayerSliderBehavior.clamp(1.5) == 1)
        #expect(PlayerSliderBehavior.seekStep(duration: 100) == 0.05)
        #expect(PlayerSliderBehavior.volumeIncrement == 0.05)
        #expect(PlayerSliderBehavior.adjusted(0.98, direction: .plus, step: 0.05) == 1)
        #expect(PlayerSliderBehavior.adjusted(0.02, direction: .minus, step: 0.05) == 0)
    }

    @Test("Compact player selection does not activate while editing the layout")
    func compactPlayerSelection() {
        #expect(PlayerWindowMetrics.mainMinimumWidth == 760)
        #expect(PlayerWindowMetrics.libraryColumnMinimumWidth == 560)
        #expect(PlayerSliderBehavior.usesCompactPlayer(width: 760, isEditingLayout: false))
        #expect(!PlayerSliderBehavior.usesCompactPlayer(width: 820, isEditingLayout: false))
        #expect(!PlayerSliderBehavior.usesCompactPlayer(width: 760, isEditingLayout: true))
    }

    @Test("Playlist removal clears selection only after persistence succeeds")
    func playlistRemovalSelection() {
        let removed = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let retained = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let selection = Set([removed, retained])

        let afterFailure = TrackTableSelectionUpdate.afterRemoving(
            [removed],
            from: selection,
            persistenceSucceeded: false
        )
        let afterSuccess = TrackTableSelectionUpdate.afterRemoving(
            [removed],
            from: selection,
            persistenceSucceeded: true
        )

        #expect(afterFailure == selection)
        #expect(afterSuccess == [retained])
    }

    @Test("Credential Keychain routing respects the current signing entitlements")
    func credentialKeychainRouting() {
        #expect(SongbirdCredentialKeychainMode.resolved(from: nil) == .fileBased)
        #expect(SongbirdCredentialKeychainMode.resolved(from: [:]) == .fileBased)
        #expect(SongbirdCredentialKeychainMode.resolved(from: [
            "com.apple.application-identifier": "TEAMID.com.songbird.player"
        ]) == .dataProtection)
        #expect(SongbirdCredentialKeychainMode.resolved(from: [
            "keychain-access-groups": ["TEAMID.com.songbird.player"]
        ]) == .dataProtection)
    }

    @Test("Non-interactive Keychain reads use an authentication context that forbids UI")
    func nonInteractiveCredentialContext() throws {
        #expect(SongbirdCredentialStore.authenticationContext(
            for: .allowAuthenticationUI
        ) == nil)
        let context = try #require(SongbirdCredentialStore.authenticationContext(
            for: .failIfAuthenticationRequired
        ))
        #expect(context.interactionNotAllowed)
    }

    @Test("Focused track-table commands invoke only their published closures")
    func focusedTrackTableCommandRouting() {
        var selectedAll = false
        var focusedSearch = false
        let commands = FocusedTrackTableCommands(
            selectAll: { selectedAll = true },
            focusSearch: { focusedSearch = true }
        )

        commands.selectAll()
        #expect(selectedAll)
        #expect(!focusedSearch)
        commands.focusSearch()
        #expect(focusedSearch)
    }

    @MainActor
    @Test("Contextual library search opens, clears, collapses, and resets on navigation")
    func contextualLibrarySearchLifecycle() {
        let search = LibrarySearchCoordinator()

        search.requestFocus()
        #expect(search.isPresented)
        #expect(search.focusRequestID == 1)

        search.query = "Bowie"
        search.collapseIfEmpty()
        #expect(search.isPresented)

        search.clear()
        search.collapseIfEmpty()
        #expect(!search.isPresented)

        search.requestFocus()
        search.query = "Ambient"
        search.resetForNavigation()
        #expect(search.query.isEmpty)
        #expect(!search.isPresented)

        search.requestFocus()
        search.query = "Jazz"
        search.dismiss()
        #expect(search.query.isEmpty)
        #expect(!search.isPresented)
    }

    @Test("Playlist destination search explains an empty result")
    func playlistDestinationEmptyReason() {
        #expect(
            PlaylistDestinationEmptyReason.resolve(resultCount: 2, searchText: "Road")
                == .none
        )
        #expect(
            PlaylistDestinationEmptyReason.resolve(resultCount: 0, searchText: "   ")
                == .none
        )
        #expect(
            PlaylistDestinationEmptyReason.resolve(resultCount: 0, searchText: "  Road Trip ")
                == .noMatches(query: "Road Trip")
        )
    }

    @Test("A fresh Discogs query returns to page one while paging retains its destination")
    func discogsSearchPaging() {
        #expect(DiscogsSearchPaging.page(currentPage: 4, startsNewQuery: true) == 1)
        #expect(DiscogsSearchPaging.page(currentPage: 3, startsNewQuery: false) == 3)
        #expect(DiscogsSearchPaging.page(currentPage: 0, startsNewQuery: false) == 1)
    }

    @MainActor
    @Test("View-owned tasks replace, cancel, and tear down without stale cleanup")
    func viewTaskLifecycle() async throws {
        let tasks = ViewTaskSlot()
        var completions: [String] = []

        tasks.start {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            completions.append("replaced")
        }
        await Task.yield()
        tasks.start {
            completions.append("replacement")
        }

        for _ in 0..<100 where tasks.isRunning {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(completions == ["replacement"])
        #expect(!tasks.isRunning)

        tasks.start {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            completions.append("cancelled")
        }
        #expect(tasks.isRunning)
        tasks.cancel()
        try await Task.sleep(for: .milliseconds(20))

        #expect(!tasks.isRunning)
        #expect(completions == ["replacement"])

        let replacementTasks = ViewTaskSlot()
        replacementTasks.start {
            try? await Task.sleep(for: .milliseconds(20))
            completions.append("stale completion")
        }
        await Task.yield()
        replacementTasks.start {
            do {
                try await Task.sleep(for: .milliseconds(60))
            } catch {
                return
            }
            completions.append("current completion")
        }
        try await Task.sleep(for: .milliseconds(35))

        #expect(replacementTasks.isRunning)
        #expect(completions == ["replacement", "stale completion"])

        for _ in 0..<100 where replacementTasks.isRunning {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!replacementTasks.isRunning)
        #expect(completions == ["replacement", "stale completion", "current completion"])

        var teardownTasks: ViewTaskSlot? = ViewTaskSlot()
        weak let releasedTasks = teardownTasks
        teardownTasks?.start {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch is CancellationError {
                completions.append("deinit cancelled")
            } catch {
                return
            }
        }
        await Task.yield()
        teardownTasks = nil
        for _ in 0..<100 where releasedTasks != nil || !completions.contains("deinit cancelled") {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(releasedTasks == nil)
        #expect(completions.last == "deinit cancelled")

        let gatedTasks = ViewTaskSlot()
        let staleLease = try #require(gatedTasks.lease())
        gatedTasks.invalidate()
        #expect(gatedTasks.lease() == nil)
        #expect(gatedTasks.start { completions.append("late unleased start") } == false)
        gatedTasks.activate()
        #expect(gatedTasks.start(lease: staleLease) { completions.append("late leased start") } == false)
        #expect(gatedTasks.start { completions.append("reactivated start") })
        for _ in 0..<100 where gatedTasks.isRunning {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(completions.contains("late unleased start") == false)
        #expect(completions.contains("late leased start") == false)
        #expect(completions.last == "reactivated start")
    }

    @Test("Track Info changes artwork only after an explicit artwork edit")
    func trackInfoArtworkUpdate() {
        let existing = Data([1, 2, 3])
        let replacement = Data([4, 5, 6])

        #expect(
            TrackInfoArtworkUpdate.resolve(
                wasEdited: false,
                wasCleared: false,
                data: existing
            ) == .unchanged
        )
        #expect(
            TrackInfoArtworkUpdate.resolve(
                wasEdited: true,
                wasCleared: true,
                data: nil
            ) == .clear
        )
        #expect(
            TrackInfoArtworkUpdate.resolve(
                wasEdited: true,
                wasCleared: false,
                data: replacement
            ) == .replace(replacement)
        )
    }

    @MainActor
    @Test("Import Setup dismissal detaches once before closing its hosting panel")
    func importSetupDismissalIsReentrantSafe() {
        let parent = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let coordinator = ImportSetupWindowCoordinator()
        coordinator.panel = panel
        coordinator.parentWindow = parent
        panel.delegate = coordinator
        parent.addChildWindow(panel, ordered: .above)

        coordinator.dismiss()

        #expect(panel.parent == nil)
        #expect(panel.delegate == nil)
        #expect(coordinator.panel == nil)
        #expect(coordinator.parentWindow == nil)
    }

    @MainActor
    @Test("Play Next deduplicates a stable track ID and moves one copy to the front")
    func queuePlayNextDeduplicates() {
        let first = makeTrack("First")
        let selected = makeTrack("Selected")
        let last = makeTrack("Last")
        let queue = PlaybackQueue()
        queue.setStateForTesting(
            current: nil,
            upcoming: [first, selected, last, selected],
            history: []
        )

        queue.moveNext(trackID: selected.id)

        #expect(queue.upcomingTracks.map(\.id) == [selected.id, first.id, last.id])
    }

    @MainActor
    @Test("Duplicate queue occurrences retain independent identity and removal")
    func duplicateQueueOccurrenceIdentity() throws {
        let duplicate = makeTrack("Duplicate")
        let queue = PlaybackQueue()
        let entries = queue.enqueue([duplicate, duplicate])

        #expect(entries.count == 2)
        #expect(entries[0].id != entries[1].id)
        #expect(queue.removeUpcoming(entryID: entries[0].id))
        let remaining = try #require(queue.upcomingEntries.first)
        #expect(remaining.id == entries[1].id)
        #expect(remaining.track.id == duplicate.id)
    }

    @MainActor
    @Test("Queue accessibility actions target one duplicate occurrence and omit Play Next for the current row")
    func queueAccessibilityActionsUseOccurrenceIdentity() throws {
        let duplicate = makeTrack("Duplicate")
        let other = makeTrack("Other")
        let queue = PlaybackQueue()
        let entries = queue.enqueue([duplicate, duplicate, other])
        let selected = try #require(entries.dropFirst().first)
        var playedEntryID: PlaybackQueueEntry.ID?

        PlayQueueRowAccessibilityRouting.playNow(entryID: selected.id) {
            playedEntryID = $0
        }

        #expect(playedEntryID == selected.id)
        #expect(PlayQueueRowAccessibilityRouting.offersPlayNext(isCurrent: false))
        #expect(!PlayQueueRowAccessibilityRouting.offersPlayNext(isCurrent: true))

        var attemptedCurrentMove = false
        let movedCurrent = PlayQueueRowAccessibilityRouting.playNext(
            entryID: selected.id,
            isCurrent: true
        ) { _ in
            attemptedCurrentMove = true
            return true
        }
        #expect(!movedCurrent)
        #expect(!attemptedCurrentMove)

        let movedDuplicate = PlayQueueRowAccessibilityRouting.playNext(
            entryID: selected.id,
            isCurrent: false
        ) {
            queue.moveNext(entryID: $0)
        }

        #expect(movedDuplicate)
        #expect(queue.upcomingEntries.map(\.id) == [selected.id, entries[2].id])
        #expect(queue.upcomingTracks.map(\.id) == [duplicate.id, other.id])
    }

    @MainActor
    @Test("Queue drag movement changes the effective shuffled playback order")
    func shuffledQueueDragUsesDisplayedOrder() throws {
        let queue = PlaybackQueue()
        _ = queue.enqueue([makeTrack("One"), makeTrack("Two"), makeTrack("Three")])
        queue.shuffleEnabled = true
        let before = queue.displayedUpcomingEntries.map(\.id)
        let movedID = try #require(before.last)
        let orderRevision = queue.effectiveOrderRevision

        queue.moveDisplayedUpcoming(
            fromOffsets: IndexSet(integer: before.count - 1),
            toOffset: 0
        )

        #expect(queue.displayedUpcomingEntries.first?.id == movedID)
        #expect(queue.peekNextEntry()?.id == movedID)
        #expect(queue.effectiveOrderRevision == orderRevision + 1)
    }

    @MainActor
    @Test("Rejected replacement playback preserves queue identity, history, and Shuffle")
    func rejectedReplacementIsAtomic() throws {
        let current = makeTemporaryTrack("Current")
        let upcoming = makeTemporaryTrack("Upcoming")
        let replacement = makeTemporaryTrack("Replacement")
        defer {
            [current, upcoming, replacement].forEach {
                try? FileManager.default.removeItem(atPath: $0.path)
            }
        }
        let backend = RejectingPlaybackBackend()
        let session = PlaybackSession(backend: backend)
        session.queue.setStateForTesting(current: current, upcoming: [upcoming], history: [])
        session.queue.shuffleEnabled = true
        let currentEntryID = session.queue.currentEntry?.id
        let upcomingEntryIDs = session.queue.upcomingEntries.map(\.id)

        let result = session.startReplacement(PlaybackStartRequest(tracks: [replacement]))

        guard case .failure(let error) = result else {
            Issue.record("Expected replacement playback to be rejected")
            return
        }
        #expect(error == .backendRejected("Rejected for testing"))
        #expect(session.queue.currentEntry?.id == currentEntryID)
        #expect(session.queue.upcomingEntries.map(\.id) == upcomingEntryIDs)
        #expect(session.queue.historyEntries.isEmpty)
        #expect(session.queue.shuffleEnabled)
    }

    @MainActor
    @Test("Queue movement changes one position and Clear Up Next preserves current and history")
    func queueMovementAndClearUpcoming() {
        let current = makeTrack("Current")
        let prior = makeTrack("Prior")
        let first = makeTrack("First")
        let second = makeTrack("Second")
        let third = makeTrack("Third")
        let queue = PlaybackQueue()
        queue.setStateForTesting(
            current: current,
            upcoming: [first, second, third],
            history: [prior]
        )

        #expect(queue.moveUpcoming(trackID: second.id, offset: 1))
        #expect(queue.upcomingTracks.map(\.id) == [first.id, third.id, second.id])
        #expect(!queue.moveUpcoming(trackID: second.id, offset: 1))

        queue.clearUpcoming()
        #expect(queue.upcomingTracks.isEmpty)
        #expect(queue.currentTrack?.id == current.id)
        #expect(queue.history.map(\.id) == [prior.id])
    }

    @MainActor
    @Test("Replacement queues preserve global shuffle for album and Audio CD ordering")
    func replacementQueuePreservesShuffle() {
        let tracks = [makeTrack("One"), makeTrack("Two"), makeTrack("Three")]
        let queue = PlaybackQueue()
        queue.shuffleEnabled = true

        let first = queue.replace(with: tracks, startingAt: 1)

        #expect(queue.shuffleEnabled)
        #expect(first?.id == tracks[1].id)
        #expect(queue.currentTrack?.id == tracks[1].id)
        #expect(queue.upcomingTracks.map(\.id) == [tracks[2].id])
    }

    @MainActor
    @Test("Queue clear operations return exact restorable snapshots")
    func queueClearSnapshotsRestoreOccurrences() {
        let current = makeTrack("Current")
        let first = makeTrack("First")
        let second = makeTrack("Second")
        let queue = PlaybackQueue()
        _ = queue.replace(with: [current, first, second])
        _ = queue.next()
        let upcomingIDs = queue.upcomingEntries.map(\.id)
        let historyIDs = queue.historyEntries.map(\.id)

        let upcoming = queue.clearUpcomingReturningSnapshot()
        let history = queue.clearHistoryReturningSnapshot()
        #expect(queue.upcomingEntries.isEmpty)
        #expect(queue.historyEntries.isEmpty)

        queue.restoreUpcoming(upcoming)
        queue.restoreHistory(history)
        #expect(queue.upcomingEntries.map(\.id) == upcomingIDs)
        #expect(queue.historyEntries.map(\.id) == historyIDs)
    }

    @Test("Smart playlists require a condition and reject invalid operators")
    func smartPlaylistStructureValidation() {
        #expect(SmartPlaylistRuleSet().validationErrors == [.noConditions])

        let condition = SmartCondition(field: .title, op: .greaterThan, value: "A")
        #expect(
            SmartPlaylistRuleSet(conditions: [condition]).validationErrors
                == [.invalidOperator(conditionID: condition.id)]
        )
    }

    @Test(
        "Smart numeric values enforce field-specific ranges",
        arguments: [
            (SmartField.rating, "6", "Rating must be between 0 and 5."),
            (SmartField.playCount, "-1", "Play Count cannot be negative."),
            (SmartField.year, "10000", "Year must be between 0 and 9999."),
            (SmartField.dateAdded, "-2", "Days cannot be negative."),
            (SmartField.lastPlayed, "1.5", "Enter a whole number of days."),
        ]
    )
    func smartPlaylistNumericValidation(field: SmartField, value: String, message: String) {
        let condition = SmartCondition(field: field, op: .equals, value: value)
        #expect(
            SmartPlaylistRuleSet.validationError(for: condition)
                == .invalidValue(conditionID: condition.id, message: message)
        )
    }

    @Test("No-value smart operators discard the need for a value")
    func smartPlaylistNoValueOperator() {
        let condition = SmartCondition(field: .lastPlayed, op: .isNotSet, value: "")
        #expect(SmartPlaylistRuleSet.validationError(for: condition) == nil)
        #expect(throws: Never.self) {
            _ = try SmartPlaylistRuleSet(conditions: [condition]).encode()
        }
    }

    @Test("Favorite is Boolean while Rating remains numeric and decodes unchanged")
    func favoriteAndRatingRulesAreIndependent() throws {
        #expect(SmartField.favorite.label == "Favorite")
        #expect(SmartField.rating.label == "Rating")
        #expect(SmartOperator.operators(for: .favorite) == [.isSet, .isNotSet])
        #expect(SmartOperator.operators(for: .rating).contains(.greaterThan))

        let ratingRule = SmartPlaylistRuleSet(conditions: [
            SmartCondition(field: .rating, op: .greaterThan, value: "3"),
        ])
        let decoded = try #require(SmartPlaylistRuleSet.decode(from: ratingRule.encode()))
        #expect(decoded == ratingRule)
    }

    @Test("Decoded legacy smart rules normalize operators that no longer fit their field")
    func smartPlaylistDecodeCompatibility() throws {
        let legacy = SmartPlaylistRuleSet(conditions: [
            SmartCondition(field: .title, op: .greaterThan, value: "Example")
        ])
        let data = try JSONEncoder().encode(legacy)

        let decoded = try #require(SmartPlaylistRuleSet.decode(from: data))

        #expect(decoded.conditions[0].op == .contains)
        #expect(decoded.validationErrors.isEmpty)
    }

    @MainActor
    @Test("Cancellation enters a one-shot cancelling phase")
    func operationCancellationPhase() {
        let status = LibraryStatus.shared
        var cancellationCount = 0
        status.beginOperation(message: "Working…", total: 8) {
            cancellationCount += 1
        }

        status.cancelImport()
        status.cancelImport()

        #expect(status.importProgress.value.phase == .cancelling)
        #expect(status.importProgress.value.message == "Cancelling…")
        #expect(cancellationCount == 1)
        status.endOperation(message: "Cancelled", severity: .information)
    }

    @MainActor
    @Test("Sticky errors retain notice priority and source clearing is precise")
    func stickyNoticeOrderingAndSourceClearing() throws {
        let notices = UserNoticeState()
        let error = LibraryNotice(
            message: "Playback failed",
            severity: .error,
            source: .playback
        )
        let success = LibraryNotice(
            message: "Import complete",
            severity: .success,
            source: .importing
        )
        notices.enqueue(error)
        notices.enqueue(success)

        #expect(notices.notice == error)
        notices.clear(source: .playback)
        #expect(notices.notice == success)

        notices.enqueue(LibraryNotice(
            message: "Another playback issue",
            severity: .error,
            source: .playback
        ))
        notices.enqueue(LibraryNotice(
            message: "Queued playback detail",
            severity: .information,
            source: .playback
        ))
        notices.clear(source: .playback)
        #expect(notices.notice == success)
    }

    @MainActor
    @Test("Successful Last.fm migration verifies credentials before removing preferences")
    func credentialMigrationSuccess() async throws {
        let defaults = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        defaults.set("api", forKey: LastFMClient.apiKeyKey)
        defaults.set("secret", forKey: LastFMClient.apiSecretKey)
        defaults.set("session", forKey: LastFMClient.sessionKeyKey)
        let store = InMemoryCredentialStore()

        try await LastFMCredentialMigration.migrateIfNeeded(store: store, defaults: defaults)

        #expect(try await store.value(for: .lastFMAPIKey) == "api")
        #expect(try await store.value(for: .lastFMAPISecret) == "secret")
        #expect(try await store.value(for: .lastFMSessionKey) == "session")
        #expect(defaults.string(forKey: LastFMClient.apiKeyKey) == nil)
        #expect(defaults.string(forKey: LastFMClient.apiSecretKey) == nil)
        #expect(defaults.string(forKey: LastFMClient.sessionKeyKey) == nil)
    }

    @MainActor
    @Test("Failed Last.fm migration preserves every legacy preference")
    func credentialMigrationFailurePreservesSource() async {
        let defaults = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        defaults.set("api", forKey: LastFMClient.apiKeyKey)
        defaults.set("secret", forKey: LastFMClient.apiSecretKey)
        defaults.set("session", forKey: LastFMClient.sessionKeyKey)
        let store = InMemoryCredentialStore(behavior: .failWrite(.lastFMAPISecret))

        await #expect(throws: InMemoryCredentialStore.Failure.self) {
            try await LastFMCredentialMigration.migrateIfNeeded(store: store, defaults: defaults)
        }

        #expect(defaults.string(forKey: LastFMClient.apiKeyKey) == "api")
        #expect(defaults.string(forKey: LastFMClient.apiSecretKey) == "secret")
        #expect(defaults.string(forKey: LastFMClient.sessionKeyKey) == "session")
    }

    @MainActor
    @Test("Partial Last.fm preferences migrate without inventing missing credentials")
    func partialCredentialMigration() async throws {
        let defaults = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        defaults.set("api", forKey: LastFMClient.apiKeyKey)
        let store = InMemoryCredentialStore()

        try await LastFMCredentialMigration.migrateIfNeeded(store: store, defaults: defaults)

        #expect(try await store.value(for: .lastFMAPIKey) == "api")
        #expect(try await store.value(for: .lastFMAPISecret) == nil)
        #expect(try await store.value(for: .lastFMSessionKey) == nil)
        #expect(defaults.string(forKey: LastFMClient.apiKeyKey) == nil)
    }

    @MainActor
    @Test("Pre-existing Keychain credentials remain authoritative during migration")
    func preexistingCredentialMigration() async throws {
        let defaults = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        defaults.set("legacy-api", forKey: LastFMClient.apiKeyKey)
        let store = InMemoryCredentialStore(initialValues: [.lastFMAPIKey: "keychain-api"])

        try await LastFMCredentialMigration.migrateIfNeeded(store: store, defaults: defaults)

        #expect(try await store.value(for: .lastFMAPIKey) == "keychain-api")
        #expect(defaults.string(forKey: LastFMClient.apiKeyKey) == nil)
    }

    @MainActor
    @Test("Locked credential storage preserves Last.fm preferences")
    func lockedCredentialMigration() async {
        let defaults = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        defaults.set("api", forKey: LastFMClient.apiKeyKey)
        let store = InMemoryCredentialStore(behavior: .locked)

        await #expect(throws: SongbirdCredentialStoreError.interactionNotAllowed) {
            try await LastFMCredentialMigration.migrateIfNeeded(store: store, defaults: defaults)
        }
        #expect(defaults.string(forKey: LastFMClient.apiKeyKey) == "api")
    }

    @MainActor
    @Test("Credential verification failure preserves Last.fm preferences")
    func credentialVerificationFailure() async {
        let defaults = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        defaults.set("api", forKey: LastFMClient.apiKeyKey)
        let store = InMemoryCredentialStore(behavior: .corruptVerification(.lastFMAPIKey))

        await #expect(throws: SongbirdCredentialStoreError.verificationFailed) {
            try await LastFMCredentialMigration.migrateIfNeeded(store: store, defaults: defaults)
        }
        #expect(defaults.string(forKey: LastFMClient.apiKeyKey) == "api")
    }

    @MainActor
    @Test("Incomplete Last.fm authentication fails without entering a repeated submission state")
    func incompleteLastFMAuthenticationState() async {
        let client = LastFMClient(credentialStore: InMemoryCredentialStore())

        await client.authenticate(username: "", password: "", apiKey: "", apiSecret: "")

        guard case .failed(let message) = client.authenticationState else {
            Issue.record("Expected failed authentication state")
            return
        }
        #expect(message.contains("username"))
    }

    @MainActor
    @Test("Playback-time Last.fm reads never authorize Keychain UI")
    func backgroundLastFMCredentialReadsAreNonInteractive() async throws {
        let store = InteractionRecordingCredentialStore(values: [
            .lastFMAPIKey: "api",
            .lastFMAPISecret: "secret",
            .lastFMSessionKey: "session",
        ])
        let client = LastFMClient(credentialStore: store)

        let credentials = try #require(await client.credentialsForBackgroundPost())

        #expect(credentials == LastFMPostCredentials(
            apiKey: "api",
            apiSecret: "secret",
            sessionKey: "session"
        ))
        #expect(await store.recordedReads() == [
            .init(credential: .lastFMAPIKey, interaction: .failIfAuthenticationRequired),
            .init(credential: .lastFMAPISecret, interaction: .failIfAuthenticationRequired),
            .init(credential: .lastFMSessionKey, interaction: .failIfAuthenticationRequired),
        ])
    }

    @MainActor
    @Test("Last.fm defers when a playback-time Keychain read needs authorization")
    func backgroundLastFMCredentialReadsDeferOnInteraction() async {
        let store = InteractionRecordingCredentialStore(
            values: [.lastFMAPIKey: "api"],
            rejectsNonInteractiveReads: true
        )
        let client = LastFMClient(credentialStore: store)

        #expect(await client.credentialsForBackgroundPost() == nil)
        #expect(await store.recordedReads() == [
            .init(credential: .lastFMAPIKey, interaction: .failIfAuthenticationRequired)
        ])
    }

    @MainActor
    @Test("Explicit Last.fm settings reads may authorize Keychain UI")
    func userInitiatedLastFMCredentialReadRemainsInteractive() async throws {
        let store = InteractionRecordingCredentialStore(values: [.lastFMAPIKey: "api"])
        let client = LastFMClient(credentialStore: store)

        #expect(try await client.storedCredential(.lastFMAPIKey) == "api")
        #expect(await store.recordedReads() == [
            .init(credential: .lastFMAPIKey, interaction: .allowAuthenticationUI)
        ])
    }

    @MainActor
    private func makeTrack(_ title: String) -> Track {
        Track(path: "/tmp/songbird-usability-\(title).mp3", title: title)
    }

    private func makeTemporaryTrack(_ title: String) -> Track {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-usability-\(UUID().uuidString).mp3")
        _ = FileManager.default.createFile(atPath: url.path, contents: Data())
        return Track(path: url.path, title: title)
    }

    private var defaultsSuiteName: String { "Songbird.UsabilityRemediationTests" }

    private func temporaryDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }

    // MARK: - Status presentation tests (Phase 2 Tasks 5-6)

    @Test("Resting library status formats count and duration")
    func restingStatusFormatting() {
        #expect(
            LibraryStatusPresentation.resting(count: 381, duration: 8_502).text
                == "381 items · 2:21:42"
        )
    }

    @Test("Singular item uses correct word")
    func restingStatusSingular() {
        #expect(
            LibraryStatusPresentation.resting(count: 1, duration: 180).text
                == "1 item · 3:00"
        )
    }

    @Test("Zero duration shows 0:00")
    func restingStatusZeroDuration() {
        #expect(
            LibraryStatusPresentation.resting(count: 5, duration: 0).text
                == "5 items · 0:00"
        )
    }

    @Test("Durations over 24 hours format correctly")
    func restingStatusLongDuration() {
        #expect(
            LibraryStatusPresentation.resting(count: 1000, duration: 90_061).text
                == "1000 items · 25:01:01"
        )
    }

    @Test("Empty presentation returns empty string")
    func restingStatusEmpty() {
        #expect(LibraryStatusPresentation.empty.text == "")
    }

    @Test("Duration formatter handles edge cases")
    func durationFormatter() {
        #expect(LibraryStatusPresentation.formatDuration(0) == "0:00")
        #expect(LibraryStatusPresentation.formatDuration(59) == "0:59")
        #expect(LibraryStatusPresentation.formatDuration(60) == "1:00")
        #expect(LibraryStatusPresentation.formatDuration(3599) == "59:59")
        #expect(LibraryStatusPresentation.formatDuration(3600) == "1:00:00")
    }
}

@MainActor
private final class RejectingPlaybackBackend: PlayerBackend {
    struct Rejection: LocalizedError {
        var errorDescription: String? { "Rejected for testing" }
    }

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
    func play(_ source: AudioSource, durationHint: TimeInterval) throws { throw Rejection() }
    func pause() {}
    func resume() {}
    func stop() {}
    func seek(to time: TimeInterval) {}
    func setNextSource(_ source: AudioSource?, crossfadeDuration: TimeInterval) {}
}

private actor InMemoryCredentialStore: SongbirdCredentialStoring {
    enum Failure: Error {
        case writeFailed
    }

    enum Behavior {
        case normal
        case failWrite(SongbirdCredential)
        case corruptVerification(SongbirdCredential)
        case locked
    }

    private var values: [SongbirdCredential: String]
    private let behavior: Behavior

    init(
        initialValues: [SongbirdCredential: String] = [:],
        behavior: Behavior = .normal
    ) {
        values = initialValues
        self.behavior = behavior
    }

    func value(
        for credential: SongbirdCredential,
        interaction: SongbirdCredentialInteractionPolicy
    ) throws -> String? {
        if case .locked = behavior {
            throw SongbirdCredentialStoreError.interactionNotAllowed
        }
        return values[credential]
    }

    func setValue(_ value: String, for credential: SongbirdCredential) throws {
        switch behavior {
        case .failWrite(let target) where target == credential:
            throw Failure.writeFailed
        case .corruptVerification(let target) where target == credential:
            values[credential] = "corrupt"
        case .locked:
            throw SongbirdCredentialStoreError.interactionNotAllowed
        case .normal, .failWrite, .corruptVerification:
            values[credential] = value
        }
    }

    func removeValue(for credential: SongbirdCredential) {
        values.removeValue(forKey: credential)
    }
}

private actor InteractionRecordingCredentialStore: SongbirdCredentialStoring {
    struct Read: Equatable {
        let credential: SongbirdCredential
        let interaction: SongbirdCredentialInteractionPolicy
    }

    private var values: [SongbirdCredential: String]
    private var reads: [Read] = []
    private let rejectsNonInteractiveReads: Bool

    init(
        values: [SongbirdCredential: String],
        rejectsNonInteractiveReads: Bool = false
    ) {
        self.values = values
        self.rejectsNonInteractiveReads = rejectsNonInteractiveReads
    }

    func value(
        for credential: SongbirdCredential,
        interaction: SongbirdCredentialInteractionPolicy
    ) throws -> String? {
        reads.append(Read(credential: credential, interaction: interaction))
        if rejectsNonInteractiveReads,
           interaction == .failIfAuthenticationRequired {
            throw SongbirdCredentialStoreError.interactionNotAllowed
        }
        return values[credential]
    }

    func setValue(_ value: String, for credential: SongbirdCredential) {
        values[credential] = value
    }

    func removeValue(for credential: SongbirdCredential) {
        values.removeValue(forKey: credential)
    }

    func recordedReads() -> [Read] {
        reads
    }
}
