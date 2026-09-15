import AppKit
import Testing
@testable import SongbirdLib

@Suite("Track table interactions")
struct TrackTableInteractionTests {
    @Test("Group context menu labels state their affected track count")
    func groupMenuLabels() {
        #expect(TrackContextMenuLabels.action("Play", count: 3) == "Play 3 Tracks")
        #expect(TrackContextMenuLabels.addToQueue(count: 3) == "Add 3 Tracks to Queue")
        #expect(TrackContextMenuLabels.editMetadata(count: 3) == "Edit Metadata for 3 Tracks…")
        #expect(TrackContextMenuLabels.action("Play", count: 1) == "Play")
    }
    @Test("Top Played keeps its sort separate from ordinary track lists")
    func topPlayedUsesLocalSort() {
        // Given
        let ordinaryPreference = TrackTableSortPreference.resolve(for: .allTracks)

        // When
        let topPlayedPreference = TrackTableSortPreference.resolve(for: .topPlayed)

        // Then
        #expect(ordinaryPreference == .shared)
        #expect(
            topPlayedPreference
                == .local(defaultColumn: .playCount, ascending: false)
        )
    }

    @Test("Selection is visually stronger than the now-playing state")
    func selectionTakesVisualPriority() {
        // Given
        let rowIsSelected = true
        let rowIsPlaying = true

        // When
        let emphasis = TrackRowVisualEmphasis.resolve(
            isSelected: rowIsSelected,
            isPlaying: rowIsPlaying
        )

        // Then
        #expect(emphasis == .selected)
    }

    @Test("An unselected playing row remains subtly emphasized")
    func playingRowIsEmphasized() {
        // Given
        let rowIsSelected = false
        let rowIsPlaying = true

        // When
        let emphasis = TrackRowVisualEmphasis.resolve(
            isSelected: rowIsSelected,
            isPlaying: rowIsPlaying
        )

        // Then
        #expect(emphasis == .playing)
    }

    @Test("An idle unselected row has no emphasis")
    func idleRowIsUnemphasized() {
        // Given
        let rowIsSelected = false
        let rowIsPlaying = false

        // When
        let emphasis = TrackRowVisualEmphasis.resolve(
            isSelected: rowIsSelected,
            isPlaying: rowIsPlaying
        )

        // Then
        #expect(emphasis == .none)
    }

    @Test("The native list does not paint over the themed row selection")
    @MainActor
    func nativeSelectionPaintIsDisabled() {
        // Given
        let tableView = NSTableView()
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = true

        // When
        TrackTableNativeSelectionAppearance.apply(to: tableView)

        // Then
        #expect(tableView.selectionHighlightStyle == .none)
        #expect(tableView.allowsMultipleSelection)
    }

    @Test("Playback starts at the activated displayed track")
    func activationUsesDisplayedSuffix() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let ordered = [first, second, third]

        #expect(
            TrackTableActivationOrder.suffix(startingAt: second, in: ordered)
                == [second, third]
        )
        #expect(
            TrackTableActivationOrder.suffix(startingAt: UUID(), in: ordered).isEmpty
        )
    }

    @Test("Context actions preserve an existing selection in display order")
    func contextTargetsSelectionInDisplayOrder() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let ordered = [first, second, third]

        #expect(TrackTableSelectionTargeting.orderedTargets(
            clickedID: second,
            selection: [first, second],
            orderedIDs: ordered
        ) == [first, second])
        #expect(TrackTableSelectionTargeting.orderedTargets(
            clickedID: third,
            selection: [first, second],
            orderedIDs: ordered
        ) == [third])
    }

    @Test("Dragging outside the selection selects only the dragged track")
    func dragTargetsClickedTrackOrSelection() {
        let first = UUID()
        let second = UUID()
        let selection: Set<UUID> = [first]

        #expect(TrackTableSelectionTargeting.selectionForDrag(
            clickedID: first,
            selection: selection
        ) == selection)
        #expect(TrackTableSelectionTargeting.selectionForDrag(
            clickedID: second,
            selection: selection
        ) == [second])
    }

    @Test("Pointer selection supports plain, Command, and Shift clicks")
    func pointerSelectionUsesNativeModifierSemantics() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let fourth = UUID()
        let ordered = [first, second, third, fourth]

        let plain = TrackTablePointerSelection.update(
            clickedID: second,
            selection: [],
            anchorID: nil,
            orderedIDs: ordered,
            modifiers: []
        )
        #expect(plain.selection == [second])
        #expect(plain.anchorID == second)

        let command = TrackTablePointerSelection.update(
            clickedID: fourth,
            selection: plain.selection,
            anchorID: plain.anchorID,
            orderedIDs: ordered,
            modifiers: [.toggle]
        )
        #expect(command.selection == [second, fourth])
        #expect(command.anchorID == fourth)

        let shift = TrackTablePointerSelection.update(
            clickedID: first,
            selection: command.selection,
            anchorID: command.anchorID,
            orderedIDs: ordered,
            modifiers: [.range]
        )
        #expect(shift.selection == Set(ordered))
        #expect(shift.anchorID == fourth)
    }

    @MainActor
    @Test("A track monitor rejects rows from a different native table")
    func nativeDoubleClickIsScopedToItsTrackTable() {
        let monitored = NSTableView()
        let foreign = NSTableView()
        let embeddedButton = NSButton()

        #expect(TrackTableDoubleClickScope.owns(
            hitTable: monitored,
            monitoredTable: monitored,
            eventIsInsideMonitor: true
        ))
        #expect(TrackTableDoubleClickScope.owns(
            hitTable: foreign,
            monitoredTable: monitored,
            eventIsInsideMonitor: true
        ) == false)
        #expect(TrackTableDoubleClickScope.owns(
            hitTable: monitored,
            monitoredTable: nil,
            eventIsInsideMonitor: true
        ))
        #expect(TrackTableDoubleClickScope.owns(
            hitTable: monitored,
            monitoredTable: nil,
            eventIsInsideMonitor: false
        ) == false)
        #expect(TrackTableDoubleClickScope.accepts(
            nearestControl: monitored,
            tableView: monitored
        ))
        #expect(TrackTableDoubleClickScope.accepts(
            nearestControl: nil,
            tableView: monitored
        ))
        #expect(TrackTableDoubleClickScope.accepts(
            nearestControl: embeddedButton,
            tableView: monitored
        ) == false)
    }
}
