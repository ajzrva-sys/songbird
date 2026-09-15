import AppKit
import SwiftUI

private struct TrackProjectionInput: Hashable {
    let revision: Int
    let albumProjectionRevision: Int
    let request: TrackTableRequest
}

enum TrackRowVisualEmphasis: Equatable {
    case none
    case playing
    case selected

    static func resolve(isSelected: Bool, isPlaying: Bool) -> Self {
        if isSelected { return .selected }
        if isPlaying { return .playing }
        return .none
    }
}

enum TrackTableSortPreference: Equatable {
    case shared
    case local(defaultColumn: TrackSortColumn, ascending: Bool)

    static func resolve(for collection: TrackCollectionDescriptor) -> Self {
        collection == .topPlayed
            ? .local(defaultColumn: .playCount, ascending: false)
            : .shared
    }
}

enum TrackTableSelectionUpdate {
    static func afterRemoving(
        _ removedTrackIDs: Set<UUID>,
        from selection: Set<UUID>,
        persistenceSucceeded: Bool
    ) -> Set<UUID> {
        guard persistenceSucceeded else { return selection }
        return selection.subtracting(removedTrackIDs)
    }
}

enum TrackTableActivationOrder {
    static func suffix(startingAt trackID: UUID, in orderedTrackIDs: [UUID]) -> [UUID] {
        guard let index = orderedTrackIDs.firstIndex(of: trackID) else { return [] }
        return Array(orderedTrackIDs[index...])
    }
}

enum TrackTableSelectionTargeting {
    static func orderedTargets(
        clickedID: UUID,
        selection: Set<UUID>,
        orderedIDs: [UUID]
    ) -> [UUID] {
        guard selection.contains(clickedID) else { return [clickedID] }
        let selected = orderedIDs.filter(selection.contains)
        return selected.isEmpty ? [clickedID] : selected
    }

    static func selectionForDrag(clickedID: UUID, selection: Set<UUID>) -> Set<UUID> {
        selection.contains(clickedID) ? selection : [clickedID]
    }
}

struct TrackTablePointerModifiers: OptionSet, Equatable, Sendable {
    let rawValue: Int

    static let toggle = Self(rawValue: 1 << 0)
    static let range = Self(rawValue: 1 << 1)
}

struct TrackTableSelectionResult: Equatable, Sendable {
    let selection: Set<UUID>
    let anchorID: UUID?
}

enum TrackTablePointerSelection {
    static func update(
        clickedID: UUID,
        selection: Set<UUID>,
        anchorID: UUID?,
        orderedIDs: [UUID],
        modifiers: TrackTablePointerModifiers
    ) -> TrackTableSelectionResult {
        if modifiers.contains(.range),
           let anchorID,
           let anchorIndex = orderedIDs.firstIndex(of: anchorID),
           let clickedIndex = orderedIDs.firstIndex(of: clickedID) {
            let range = Set(orderedIDs[min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)])
            return TrackTableSelectionResult(
                selection: modifiers.contains(.toggle) ? selection.union(range) : range,
                anchorID: anchorID
            )
        }

        if modifiers.contains(.toggle) {
            var updated = selection
            if updated.contains(clickedID) {
                updated.remove(clickedID)
            } else {
                updated.insert(clickedID)
            }
            return TrackTableSelectionResult(selection: updated, anchorID: clickedID)
        }

        return TrackTableSelectionResult(selection: [clickedID], anchorID: clickedID)
    }
}

/// Value-backed multi-column table. Selection never participates in projection work.
public struct TrackTableView: View {
    public let title: String
    public let collection: TrackCollectionDescriptor
    public var showsFilters: Bool
    public var showsHeader: Bool
    public var supportsSearch: Bool
    public var emptyMessage: String
    public var emptyHint: String
    public var publishesSummary: Bool

    @EnvironmentObject private var librarySnapshots: LibrarySnapshotStore
    @EnvironmentObject private var albumProjectionStore: LibraryAlbumProjectionStore
    @EnvironmentObject private var playbackSession: PlaybackSession
    @EnvironmentObject private var playbackPresentation: PlaybackPresentationState
    @EnvironmentObject private var actions: LibraryItemActionHandler
    @EnvironmentObject private var librarySearch: LibrarySearchCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @FocusState private var searchFocused: Bool
    @State private var typeSelectBuffer = ""
    @State private var typeSelectGeneration = 0
    @State private var selectedArtist: String?
    @State private var selectedAlbumIDs: Set<String> = []
    @State private var selectedGenre: String?
    @State private var selectedTrackIDs: Set<UUID> = []
    @State private var selectionAnchorID: UUID?
    @State private var trackIDsPendingDelete: [UUID] = []
    @State private var usePlaylistOrder = true
    @State private var projection: TrackTableProjection = .empty
    @State private var projectionState: LibraryProjectionState<TrackTableProjection> =
        .loading(previous: nil)
    @State private var projectedSearchText = ""
    @State private var projectedInput: TrackProjectionInput?
    @State private var projectionWorker = TrackTableProjectionWorker()
    @State private var localSortColumnRaw: String
    @State private var localSortAscending: Bool
    @State private var summaryOwner = LibraryContentSummaryOwner()

    @AppStorage("trackTable.sortColumn") private var sortColumnRaw = TrackSortColumn.dateAdded.rawValue
    @AppStorage("trackTable.sortAscending") private var sortAscending = false
    @AppStorage(TrackTableColumnPrefs.storageKey) private var columnPrefsRaw = TrackTableColumnPrefs.encode(TrackTableColumnPrefs.defaults)
    @AppStorage(TrackTablePresentation.storageKey) private var tablePresentationRaw = TrackTablePresentation.classic.rawValue
    @AppStorage(TrackTableColumnPrefs.albumArtistDefaultMigrationKey)
    private var migratedAlbumArtistDefault = false
    @AppStorage(TrackTableColumnPrefs.primaryColumnOrderMigrationKey)
    private var migratedPrimaryColumnOrder = false
    @AppStorage("cascadeFilter.visible") private var cascadeVisible = true
    @AppStorage(PlayerBarPlacement.storageKey) private var playerBarPlacementRaw = PlayerBarPlacement.top.rawValue
    @State private var resizePreviewWidths: [TrackSortColumn: CGFloat] = [:]

    private var tablePresentation: TrackTablePresentation {
        TrackTablePresentation.resolved(from: tablePresentationRaw)
    }

    public init(
        title: String,
        collection: TrackCollectionDescriptor,
        showsFilters: Bool = true,
        showsHeader: Bool = true,
        supportsSearch: Bool = true,
        emptyMessage: String = "No Music Loaded",
        emptyHint: String = "Drop files here or use File ▸ Scan Folder…",
        publishesSummary: Bool = true
    ) {
        self.title = title
        self.collection = collection
        self.showsFilters = showsFilters
        self.showsHeader = showsHeader
        self.supportsSearch = supportsSearch
        self.emptyMessage = emptyMessage
        self.emptyHint = emptyHint
        self.publishesSummary = publishesSummary

        switch TrackTableSortPreference.resolve(for: collection) {
        case .shared:
            _localSortColumnRaw = State(initialValue: TrackSortColumn.dateAdded.rawValue)
            _localSortAscending = State(initialValue: false)
        case .local(let defaultColumn, let ascending):
            _localSortColumnRaw = State(initialValue: defaultColumn.rawValue)
            _localSortAscending = State(initialValue: ascending)
        }
    }

    private var textColor: Color { SongbirdTheme.text(for: colorScheme) }
    private var secondaryColor: Color { SongbirdTheme.secondaryText(for: colorScheme) }
    private var selectedBackground: Color { SongbirdTheme.sidebarSelected(for: colorScheme) }
    /// Text color to use on selected rows — white when the selection background is dark.
    private var selectedTextColor: Color {
        isDarkSelection ? Color.white : textColor
    }
    /// Secondary text color to use on selected rows.
    private var selectedSecondaryColor: Color {
        isDarkSelection ? Color.white.opacity(0.75) : secondaryColor
    }
    /// Whether the current selection background is dark enough to need light text.
    private var isDarkSelection: Bool {
        let bg = NSColor(selectedBackground).usingColorSpace(.deviceRGB) ?? NSColor(selectedBackground)
        let luminance = 0.2126 * bg.redComponent + 0.7152 * bg.greenComponent + 0.0722 * bg.blueComponent
        return luminance < 0.5
    }
    private var queue: PlaybackQueue { playbackSession.queue }
    private var searchText: String { supportsSearch ? librarySearch.query : "" }
    private var sortPreference: TrackTableSortPreference {
        TrackTableSortPreference.resolve(for: collection)
    }
    private var activeSortColumnRaw: String {
        sortPreference == .shared ? sortColumnRaw : localSortColumnRaw
    }
    private var activeSortAscending: Bool {
        sortPreference == .shared ? sortAscending : localSortAscending
    }
    private var activeSortColumn: TrackSortColumn {
        guard let column = TrackSortColumn(rawValue: activeSortColumnRaw), column.isSupported else {
            return .dateAdded
        }
        return column
    }

    private var playlistSnapshot: LibraryPlaylistSnapshot? {
        guard case .playlist(let id) = collection else { return nil }
        return librarySnapshots.snapshot.playlistsByID[id]
    }

    private var canReorderPlaylist: Bool {
        guard playlistSnapshot?.isSmart == false else { return false }
        return usePlaylistOrder
            && searchText.isEmpty
            && selectedArtist == nil
            && selectedAlbumIDs.isEmpty
            && selectedGenre == nil
    }

    private var usesBottomTitleband: Bool {
        (PlayerBarPlacement(rawValue: playerBarPlacementRaw) ?? .top) == .bottom
    }

    private var request: TrackTableRequest {
        TrackTableRequest(
            collection: collection,
            searchText: searchText,
            selectedArtist: selectedArtist,
            selectedAlbumIDs: selectedAlbumIDs,
            selectedGenre: selectedGenre,
            sortColumn: activeSortColumn,
            sortAscending: activeSortAscending,
            usePlaylistOrder: usePlaylistOrder,
            includesFacets: showsFilters,
            columnPreferencesJSON: columnPrefsRaw
        )
    }

    private var projectionInput: TrackProjectionInput {
        let revision: Int
        if case .playlist = collection {
            revision = max(
                librarySnapshots.snapshot.trackRevision,
                librarySnapshots.snapshot.playlistRevision
            )
        } else {
            revision = librarySnapshots.snapshot.trackRevision
        }
        return TrackProjectionInput(
            revision: revision,
            albumProjectionRevision: request.includesFacets
                || request.selectedAlbumIDs.isEmpty == false
                ? albumProjectionStore.projectionRevision
                : 0,
            request: request
        )
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if showsHeader {
                    header.frame(width: geometry.size.width)
                }
                if projection.sourceWasEmpty, projection.sourceRevision > 0 {
                    emptyState(sourceIsEmpty: true)
                } else {
                    if showsFilters, cascadeVisible {
                        CascadeFilterBar(
                            facets: projection.facets,
                            maximumHeight: filterBrowserMaximumHeight(
                                availableHeight: geometry.size.height
                            ),
                            selectedArtist: $selectedArtist,
                            selectedAlbumIDs: $selectedAlbumIDs,
                            selectedGenre: $selectedGenre
                        )
                        .frame(width: geometry.size.width)
                        .clipped()
                    }
                    tableBody
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .background(SongbirdTheme.background(for: colorScheme))
        .overlay {
            if case .loading(nil) = projectionState {
                ProgressView("Loading Tracks…")
            } else if case .failed(let message, nil) = projectionState {
                ContentUnavailableView {
                    Label("Tracks Could Not Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") {
                        Task { await updateProjection(for: projectionInput) }
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if case .loading(let previous) = projectionState, previous != nil {
                ProgressView()
                    .controlSize(.small)
                    .padding(12)
            }
        }
        .task(id: projectionInput) {
            await updateProjection(for: projectionInput)
        }
        .onAppear {
            if publishesSummary { LibraryStatus.shared.summary.activate(owner: summaryOwner) }
            primeImmediateOrderedProjection()
            if migratedAlbumArtistDefault == false {
                columnPrefsRaw = TrackTableColumnPrefs.encode(
                    TrackTableColumnPrefs.preferringAlbumArtist(
                        TrackTableColumnPrefs.decode(columnPrefsRaw)
                    )
                )
                migratedAlbumArtistDefault = true
            }
            if migratedPrimaryColumnOrder == false {
                columnPrefsRaw = TrackTableColumnPrefs.encode(
                    TrackTableColumnPrefs.preferringPrimaryColumnOrder(
                        TrackTableColumnPrefs.decode(columnPrefsRaw)
                    )
                )
                migratedPrimaryColumnOrder = true
            }
            if collection == .topPlayed {
                columnPrefsRaw = TrackTableColumnPrefs.encode(
                    TrackTableColumnPrefs.preferringPlayCount(
                        TrackTableColumnPrefs.decode(columnPrefsRaw)
                    )
                )
            }
        }
        .onChange(of: selectedTrackIDs) { oldSelection, selection in
            let added = selection.subtracting(oldSelection)
            if selectionAnchorID == nil || selectionAnchorID.map(selection.contains) == false,
               let focused = earliestID(in: added) ?? primarySelectedID(in: selection) {
                selectionAnchorID = focused
            }
            updateSelectedTrack(preferredID: selectionAnchorID)
            UsabilityPerformanceSignposts.selectionCommitted(revision: projection.sourceRevision)
        }
        .onDisappear {
            LibraryStatus.shared.selection.updateLibrarySelection(trackID: nil, track: nil)
            if publishesSummary { LibraryStatus.shared.summary.clear(owner: summaryOwner) }
        }
        .focusedValue(
            \.trackTableCommands,
            searchFocused
                ? nil
                : FocusedTrackTableCommands(
                    selectAll: { selectedTrackIDs = Set(projection.orderedIDs) },
                    focusSearch: librarySearch.requestFocus
                )
        )
        .focusedValue(
            \.librarySearchCommands,
            searchFocused || supportsSearch == false
                ? nil
                : FocusedLibrarySearchCommands(focusSearch: librarySearch.requestFocus)
        )
        .task(id: librarySearch.focusRequestID) {
            guard showsHeader, supportsSearch else { return }
            await Task.yield()
            searchFocused = true
        }
        .onKeyPress(
            characters: .alphanumerics.union(CharacterSet(charactersIn: " .'\"-")),
            phases: .down
        ) { press in
            guard searchFocused == false,
                  press.modifiers.isDisjoint(with: [.command, .control, .option]) else {
                return .ignored
            }
            handleTypeSelect(press.characters)
            return .handled
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleColumnVisibility)) { note in
            guard let raw = note.userInfo?["column"] as? String,
                  let column = TrackSortColumn(rawValue: raw) else { return }
            toggleColumnVisibility(column)
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetTrackColumns)) { _ in
            columnPrefsRaw = TrackTableColumnPrefs.encode(TrackTableColumnPrefs.defaults)
        }
        .alert(deleteAlertTitle, isPresented: deleteAlertPresented) {
            Button("Cancel", role: .cancel) { trackIDsPendingDelete = [] }
            Button("Delete from Library", role: .destructive) {
                deleteFromLibrary(ids: trackIDsPendingDelete)
                trackIDsPendingDelete = []
            }
        } message: {
            Text(deleteAlertMessage)
        }
    }

    private func filterBrowserMaximumHeight(availableHeight: CGFloat) -> CGFloat {
        let destinationHeader = showsHeader
            ? (usesBottomTitleband ? MainView.titlebarCapHeight : 40)
            : 0
        let minimumTrackRow: CGFloat = tablePresentation.showsArtwork ? 36 : 22
        let reserved = destinationHeader
            + tablePresentation.headerHeight
            + minimumTrackRow * 3
            + 8
        return max(CascadeFilterBar.minHeight, availableHeight - reserved)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            searchField
        }
        .padding(.leading, 16)
        .padding(.trailing, 36)
        .frame(height: usesBottomTitleband ? MainView.titlebarCapHeight : 40)
        .frame(maxWidth: .infinity)
        .background(SongbirdTheme.background(for: colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SongbirdTheme.divider(for: colorScheme))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryColor)
                .accessibilityHidden(true)
            TextField("Search \(title)", text: $librarySearch.query)
                .textFieldStyle(.plain)
                .font(.caption)
                .focused($searchFocused)
                .accessibilityIdentifier("library.trackSearch")
            if searchText.isEmpty == false {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    librarySearch.clear()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(secondaryColor.opacity(0.7))
                .accessibilityInputLabels(["Clear Search", "Clear"])
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 7)
        .padding(.vertical, 4)
        .frame(width: 160, height: 24)
        .background(
            Capsule(style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color(white: 0.78))
        )
        .clipShape(Capsule(style: .continuous))
    }

    private var columnHeader: some View {
        TrackTableColumnHeader(
            columnPrefsRaw: $columnPrefsRaw,
            sortColumnRaw: activeSortColumnBinding,
            sortAscending: activeSortAscendingBinding,
            usePlaylistOrder: $usePlaylistOrder,
            resizePreviewWidths: $resizePreviewWidths,
            showsPlaylistOrderOption: playlistSnapshot?.isSmart == false,
            presentation: tablePresentation
        )
    }

    private var activeSortColumnBinding: Binding<String> {
        Binding(
            get: { activeSortColumnRaw },
            set: { value in
                if sortPreference == .shared {
                    sortColumnRaw = value
                } else {
                    localSortColumnRaw = value
                }
            }
        )
    }

    private var activeSortAscendingBinding: Binding<Bool> {
        Binding(
            get: { activeSortAscending },
            set: { value in
                if sortPreference == .shared {
                    sortAscending = value
                } else {
                    localSortAscending = value
                }
            }
        )
    }

    @ViewBuilder
    private var columnVisibilityMenu: some View {
        let preferences = TrackTableColumnPrefs.decode(columnPrefsRaw)
        ForEach(preferences.sorted {
            ($0.column?.label ?? $0.id).localizedCaseInsensitiveCompare($1.column?.label ?? $1.id)
                == .orderedAscending
        }) { preference in
            if let column = preference.column, column.isSupported {
                Toggle(
                    column.label,
                    isOn: Binding(
                        get: { column == .title || preference.visible },
                        set: { _ in toggleColumnVisibility(column) }
                    )
                )
                .disabled(column == .title)
            }
        }
        Divider()
        Button("Reset Columns") {
            columnPrefsRaw = TrackTableColumnPrefs.encode(TrackTableColumnPrefs.defaults)
        }
    }

    @ViewBuilder
    private var tableBody: some View {
        if case .loading(let previous) = projectionState, previous == nil {
            Color.clear
        } else if projection.rows.isEmpty {
            emptyState(sourceIsEmpty: false)
        } else {
            GeometryReader { geometry in
                let contentWidth = max(
                    geometry.size.width,
                    TrackTableLayout.contentWidth(
                        columns: projection.columns,
                        presentation: tablePresentation,
                        previewWidths: resizePreviewWidths
                    )
                )
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        columnHeader.frame(width: contentWidth)
                        List(selection: $selectedTrackIDs) {
                            ForEach(projection.rows) { row in
                                projectedRow(row)
                            }
                            .onMove(perform: canReorderPlaylist ? reorderPlaylist : nil)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .overlay {
                            TrackTableDoubleClickMonitor(
                                action: { rowIndex in
                                    guard projection.rows.indices.contains(rowIndex) else { return }
                                    play(rowID: projection.rows[rowIndex].id)
                                },
                                selectionAction: { rowIndex, modifiers in
                                    guard projection.rows.indices.contains(rowIndex) else { return }
                                    handlePointerSelection(
                                        rowID: projection.rows[rowIndex].id,
                                        modifiers: modifiers
                                    )
                                },
                                selectAllAction: {
                                    selectedTrackIDs = Set(projection.orderedIDs)
                                }
                            )
                        }
                        .contextMenu(forSelectionType: UUID.self) { selection in
                            trackContextMenu(for: selection)
                        }
                    }
                    .frame(width: contentWidth, height: geometry.size.height)
                }
                .scrollIndicators(.automatic)
            }
            .accessibilityIdentifier("library.trackTable")
        }
    }

    private func projectedRow(_ row: LibraryTrackSnapshot) -> some View {
        ProjectedTrackRow(
            track: row,
            displayValues: projection.displayValuesByID[row.id] ?? .fallback,
            columns: projection.columns,
            presentation: tablePresentation,
            resizePreviewWidths: resizePreviewWidths,
            textColor: textColor,
            secondaryColor: secondaryColor,
            selectedTextColor: selectedTextColor,
            selectedSecondaryColor: selectedSecondaryColor,
            isSelected: selectedTrackIDs.contains(row.id),
            dragPayload: {
                let selection = TrackTableSelectionTargeting.selectionForDrag(
                    clickedID: row.id,
                    selection: selectedTrackIDs
                )
                if selection != selectedTrackIDs {
                    selectedTrackIDs = selection
                }
                return TrackIDPasteboard(ids: TrackTableSelectionTargeting.orderedTargets(
                    clickedID: row.id,
                    selection: selection,
                    orderedIDs: projection.orderedIDs
                ))
            },
            favoriteAction: {
                actions.setTrackLoved(
                    !row.isLoved,
                    trackIDs: targetIDs(for: row.id)
                )
            },
            ratingAction: { rating in
                actions.setTrackRating(
                    rating,
                    trackIDs: targetIDs(for: row.id)
                )
            }
        )
        .tag(row.id)
        .listRowInsets(EdgeInsets(
            top: tablePresentation.rowVerticalInset,
            leading: 8,
            bottom: tablePresentation.rowVerticalInset,
            trailing: 8
        ))
        .listRowBackground(rowBackground(for: row.id))
        .modifier(TrackRowAccessibilityActions(
            track: row,
            targetIDs: { targetIDs(for: row.id) },
            actions: actions,
            deleteAction: { trackIDsPendingDelete = targetIDs(for: row.id) }
        ))
    }

    private func rowBackground(for rowID: UUID) -> Color {
        switch TrackRowVisualEmphasis.resolve(
            isSelected: selectedTrackIDs.contains(rowID),
            isPlaying: playbackPresentation.currentTrackID == rowID
        ) {
        case .none:
            Color.clear
        case .playing:
            selectedBackground.opacity(0.3)
        case .selected:
            selectedBackground
        }
    }

    private func emptyState(sourceIsEmpty: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: sourceIsEmpty ? "opticaldisc" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(secondaryColor.opacity(0.85))
                .accessibilityHidden(true)
            Text(sourceIsEmpty ? emptyMessage : "No Results")
                .font(.title3.weight(.semibold))
                .foregroundStyle(textColor)
            Text(sourceIsEmpty ? emptyHint : "Try a different search or filter")
                .font(.callout)
                .foregroundStyle(secondaryColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if sourceIsEmpty {
                Text("File ▸ Scan Folder…  ·  ⌘⇧O")
                    .font(.caption)
                    .foregroundStyle(secondaryColor.opacity(0.8))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    /// Whether the projection input differs only in sort order (not in
    /// search text, filters, or data revision). A sort-only change can
    /// reuse the existing rows and re-sort in place, avoiding the
    /// intermediate loading state that causes visible jitter.
    private func isSortOnlyChange(
        _ old: TrackProjectionInput?,
        _ new: TrackProjectionInput
    ) -> Bool {
        guard let old else { return false }
        let oldReq = old.request
        let newReq = new.request
        return old.revision == new.revision
            && old.albumProjectionRevision == new.albumProjectionRevision
            && oldReq.collection == newReq.collection
            && oldReq.searchText == newReq.searchText
            && oldReq.selectedArtist == newReq.selectedArtist
            && oldReq.selectedAlbumIDs == newReq.selectedAlbumIDs
            && oldReq.selectedGenre == newReq.selectedGenre
            && oldReq.includesFacets == newReq.includesFacets
            && oldReq.columnPreferencesJSON == newReq.columnPreferencesJSON
            && oldReq.usePlaylistOrder == newReq.usePlaylistOrder
            && (oldReq.sortColumn != newReq.sortColumn
                || oldReq.sortAscending != newReq.sortAscending)
    }

    private func updateProjection(for input: TrackProjectionInput) async {
        if projectedInput == input {
            projectionState = .loaded(projection)
            return
        }

        // Fast path: sort-only changes remain on the projection worker.
        if isSortOnlyChange(projectedInput, input),
           projection.sourceRevision > 0 {
            guard let sorted = try? await projectionWorker.sort(
                projection: projection,
                column: input.request.sortColumn,
                ascending: input.request.sortAscending
            ), Task.isCancelled == false, input == projectionInput else {
                return
            }
            projection = sorted
            projectionState = .loaded(sorted)
            UsabilityPerformanceSignposts.usefulProjectionPublished(revision: sorted.sourceRevision)
            projectedInput = input
            selectedTrackIDs.formIntersection(sorted.indexByID.keys)
            return
        }

        projectionState = .loading(
            previous: projection.sourceRevision > 0 ? projection : nil
        )
        do {
            if input.request.searchText != projectedSearchText {
                try await Task.sleep(for: .milliseconds(120))
            }
            let result = try await projectionWorker.project(
                snapshot: librarySnapshots.snapshot,
                request: input.request,
                albumGroups: albumProjectionStore.groups,
                albumProjectionRevision: albumProjectionStore.projectionRevision
            )
            try Task.checkCancellation()
            guard input == projectionInput else { return }
            projection = result
            projectionState = .loaded(result)
            UsabilityPerformanceSignposts.usefulProjectionPublished(revision: result.sourceRevision)
            projectedSearchText = input.request.searchText
            projectedInput = input
            selectedAlbumIDs.formIntersection(Set(result.facets.albums.map(\.id)))
            selectedTrackIDs.formIntersection(result.indexByID.keys)
            if publishesSummary {
                LibraryStatus.shared.summary.update(
                    owner: summaryOwner,
                    summary: .tracks(count: result.rows.count, duration: result.totalDuration)
                )
            }
            updateSelectedTrack(preferredID: selectionAnchorID)
        } catch is CancellationError {
            return
        } catch {
            projectionState = .failed(
                message: error.localizedDescription,
                previous: projection.sourceRevision > 0 ? projection : nil
            )
            LibraryStatus.shared.showNotice(
                "Could not update the track list: \(error.localizedDescription)",
                severity: .error
            )
        }
    }

    private func primeImmediateOrderedProjection() {
        guard projection.sourceRevision == 0,
              case .orderedTrackIDs(let trackIDs) = collection,
              request.searchText.isEmpty,
              request.selectedArtist == nil,
              request.selectedAlbumIDs.isEmpty,
              request.selectedGenre == nil,
              request.includesFacets == false else {
            return
        }
        let result = TrackTableProjection.immediateOrdered(
            snapshot: librarySnapshots.snapshot,
            trackIDs: trackIDs,
            columnPreferencesJSON: request.columnPreferencesJSON
        )
        projection = result
        projectionState = .loaded(result)
        UsabilityPerformanceSignposts.usefulProjectionPublished(revision: result.sourceRevision)
        projectedSearchText = ""
        projectedInput = projectionInput
        if publishesSummary {
            LibraryStatus.shared.summary.update(
                owner: summaryOwner,
                summary: .tracks(count: result.rows.count, duration: result.totalDuration)
            )
        }
    }

    private func updateSelectedTrack(preferredID: UUID? = nil) {
        let id = preferredID.flatMap { selectedTrackIDs.contains($0) ? $0 : nil }
            ?? primarySelectedID(in: selectedTrackIDs)
        LibraryStatus.shared.selection.updateLibrarySelection(
            trackID: id,
            track: id.flatMap(librarySnapshots.resolveTrack(id:))
        )
    }

    private func primarySelectedID(in selection: Set<UUID>) -> UUID? {
        if selection.count == 1 { return selection.first }
        return earliestID(in: selection)
    }

    private func earliestID(in ids: Set<UUID>) -> UUID? {
        ids.min { lhs, rhs in
            (projection.indexByID[lhs] ?? .max) < (projection.indexByID[rhs] ?? .max)
        }
    }

    private func targetIDs(for rowID: UUID) -> [UUID] {
        TrackTableSelectionTargeting.orderedTargets(
            clickedID: rowID,
            selection: selectedTrackIDs,
            orderedIDs: projection.orderedIDs
        )
    }

    private func handlePointerSelection(
        rowID: UUID,
        modifiers: NSEvent.ModifierFlags
    ) {
        var pointerModifiers: TrackTablePointerModifiers = []
        if modifiers.contains(.command) { pointerModifiers.insert(.toggle) }
        if modifiers.contains(.shift) { pointerModifiers.insert(.range) }
        let result = TrackTablePointerSelection.update(
            clickedID: rowID,
            selection: selectedTrackIDs,
            anchorID: selectionAnchorID,
            orderedIDs: projection.orderedIDs,
            modifiers: pointerModifiers
        )
        selectionAnchorID = result.anchorID
        selectedTrackIDs = result.selection
    }

    @ViewBuilder
    private func trackContextMenu(for selection: Set<UUID>) -> some View {
        // SwiftUI supplies the context-clicked row as `selection` even when the
        // row is already part of a larger visible selection. Preserve that
        // visible group only when the context target is inside it; an outside
        // target remains clicked-only.
        let effectiveSelection = selection.allSatisfy(selectedTrackIDs.contains)
            ? selectedTrackIDs
            : selection
        let orderedIDs = projection.selectedIDsInDisplayOrder(effectiveSelection)
        if let rowID = orderedIDs.first,
           let row = projection.rows.first(where: { $0.id == rowID }) {
            TrackContextMenu(
                track: row,
                targetIDs: orderedIDs,
                removeFromPlaylistAction: playlistSnapshot?.isSmart == false
                    ? { removeFromPlaylist(ids: orderedIDs) }
                    : nil,
                deleteAction: { trackIDsPendingDelete = orderedIDs }
            )
            if canReorderPlaylist, orderedIDs.count == 1 {
                Divider()
                Button("Move Up") { _ = movePlaylistRow(trackID: rowID, offset: -1) }
                    .disabled(projection.indexByID[rowID] == 0)
                Button("Move Down") { _ = movePlaylistRow(trackID: rowID, offset: 1) }
                    .disabled(projection.indexByID[rowID] == projection.rows.count - 1)
            }
        }
    }

    private func play(rowID: UUID) {
        let ordered = TrackTableActivationOrder.suffix(
            startingAt: rowID,
            in: projection.orderedIDs
        )
        guard ordered.isEmpty == false else { return }
        actions.requestPlay(trackIDs: ordered)
    }

    private func playSelectedTrack() {
        guard let id = primarySelectedID(in: selectedTrackIDs) else { return }
        play(rowID: id)
    }

    private func handleTypeSelect(_ characters: String) {
        let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        typeSelectBuffer += trimmed
        typeSelectGeneration += 1
        let generation = typeSelectGeneration
        let needle = typeSelectBuffer.lowercased()
        if let match = projection.rows.first(where: { $0.title.lowercased().hasPrefix(needle) })
            ?? projection.rows.first(where: { $0.artist.lowercased().hasPrefix(needle) }) {
            selectedTrackIDs = [match.id]
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            if generation == typeSelectGeneration { typeSelectBuffer = "" }
        }
    }

    private func removeFromPlaylist(ids: [UUID]) {
        guard case .playlist(let playlistID) = collection,
              playlistSnapshot?.isSmart == false else { return }
        let removed = Set(ids)
        let persistenceSucceeded: Bool
        if case .success = actions.removeTracks(ids, fromPlaylist: playlistID) {
            persistenceSucceeded = true
        } else {
            persistenceSucceeded = false
        }
        selectedTrackIDs = TrackTableSelectionUpdate.afterRemoving(
            removed,
            from: selectedTrackIDs,
            persistenceSucceeded: persistenceSucceeded
        )
    }

    private func reorderPlaylist(from source: IndexSet, to destination: Int) {
        guard case .playlist(let playlistID) = collection,
              let playlist = playlistSnapshot,
              playlist.isSmart == false,
              canReorderPlaylist else { return }
        var newOrder = playlist.trackIDs
        newOrder.move(fromOffsets: source, toOffset: destination)
        _ = actions.reorderPlaylist(
            playlistID: playlistID,
            expectedOrder: playlist.trackIDs,
            newOrder: newOrder
        )
    }

    @discardableResult
    private func movePlaylistRow(trackID: UUID, offset: Int) -> Bool {
        guard case .playlist(let playlistID) = collection,
              let playlist = playlistSnapshot,
              playlist.isSmart == false,
              canReorderPlaylist,
              let source = playlist.trackIDs.firstIndex(of: trackID) else {
            return false
        }
        let destination = min(max(source + offset, 0), playlist.trackIDs.count - 1)
        guard destination != source else { return false }
        var newOrder = playlist.trackIDs
        let track = newOrder.remove(at: source)
        newOrder.insert(track, at: destination)
        if case .success = actions.reorderPlaylist(
            playlistID: playlistID,
            expectedOrder: playlist.trackIDs,
            newOrder: newOrder
        ) { return true }
        return false
    }

    private func deleteFromLibrary(ids: [UUID]) {
        guard ids.isEmpty == false else { return }
        let removed = Set(ids)
        if case .success = actions.deleteTracks(trackIDs: ids) {
            selectedTrackIDs.subtract(removed)
        }
    }

    private func toggleColumnVisibility(_ column: TrackSortColumn) {
        guard column != .title else { return }
        var preferences = TrackTableColumnPrefs.decode(columnPrefsRaw)
        guard let index = preferences.firstIndex(where: { $0.id == column.rawValue }) else { return }
        preferences[index].visible.toggle()
        if let titleIndex = preferences.firstIndex(where: { $0.id == TrackSortColumn.title.rawValue }) {
            preferences[titleIndex].visible = true
        }
        columnPrefsRaw = TrackTableColumnPrefs.encode(preferences)
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { trackIDsPendingDelete.isEmpty == false },
            set: { if $0 == false { trackIDsPendingDelete = [] } }
        )
    }

    private var deleteAlertTitle: String {
        trackIDsPendingDelete.count == 1 ? "Delete Track?" : "Delete \(trackIDsPendingDelete.count) Tracks?"
    }

    private var deleteAlertMessage: String {
        if trackIDsPendingDelete.count == 1,
           let title = librarySnapshots.trackSnapshot(id: trackIDsPendingDelete[0])?.title {
            return "“\(title)” will be removed from your library. The file on disk is not deleted."
        }
        return "These tracks will be removed from your library. Files on disk are not deleted."
    }
}

private struct TrackRowAccessibilityActions: ViewModifier {
    let track: LibraryTrackSnapshot
    let targetIDs: () -> [UUID]
    let actions: LibraryItemActionHandler
    let deleteAction: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityValue(track.isLoved ? "Favorite" : "")
            .accessibilityAction(named: "Play") {
                actions.requestPlay(trackIDs: targetIDs())
            }
            .accessibilityAction(named: "Go to Album") {
                guard let albumID = track.albumID else { return }
                actions.showAlbum(albumID: albumID)
            }
            .accessibilityAction(named: "Go to Artist") {
                actions.showArtist(name: track.artist)
            }
            .accessibilityAction(named: "Add to Queue") {
                actions.addToQueue(trackIDs: targetIDs())
            }
            .accessibilityAction(named: "Add to New Playlist") {
                actions.requestNewPlaylist(trackIDs: targetIDs())
            }
            .accessibilityAction(named: track.isLoved ? "Remove from Favorites" : "Add to Favorites") {
                actions.setTrackLoved(!track.isLoved, trackIDs: targetIDs())
            }
            .accessibilityAction(named: "Delete from Library", deleteAction)
    }
}

private struct ProjectedTrackRow: View {
    let track: LibraryTrackSnapshot
    let displayValues: TrackTableDisplayValues
    let columns: [TrackTableColumnDefinition]
    let presentation: TrackTablePresentation
    let resizePreviewWidths: [TrackSortColumn: CGFloat]
    let textColor: Color
    let secondaryColor: Color
    let selectedTextColor: Color
    let selectedSecondaryColor: Color
    let isSelected: Bool
    let dragPayload: () -> TrackIDPasteboard
    let favoriteAction: () -> Void
    let ratingAction: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if presentation.showsArtwork {
                ProjectedTrackArtwork(reference: track.artworkReference, title: track.album)
                    .frame(width: presentation.artworkGutterWidth, alignment: .leading)
            }

            ForEach(columns) { definition in
                ProjectedTrackCell(
                    track: track,
                    displayValues: displayValues,
                    definition: definition,
                    previewWidth: resizePreviewWidths[definition.column],
                    textColor: textColor,
                    secondaryColor: secondaryColor,
                    selectedTextColor: selectedTextColor,
                    selectedSecondaryColor: selectedSecondaryColor,
                    isSelected: isSelected,
                    favoriteAction: favoriteAction,
                    ratingAction: ratingAction
                )
                .padding(.trailing, definition.id == columns.last?.id ? 0 : 8)
            }
        }
        .font(.caption)
        .contentShape(Rectangle())
        .onDrag { dragPayload().itemProvider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(track.title), \(track.artist), \(track.album)")
    }
}

private struct ProjectedTrackArtwork: View {
    let reference: ArtworkReference?
    let title: String

    var body: some View {
        ArtworkThumbnailView(
            reference: reference,
            pointSize: CGSize(width: 24, height: 24),
            accessibilityLabel: "Artwork for \(title)"
        )
    }
}

private struct ProjectedTrackCell: View {
    let track: LibraryTrackSnapshot
    let displayValues: TrackTableDisplayValues
    let definition: TrackTableColumnDefinition
    let previewWidth: CGFloat?
    let textColor: Color
    let secondaryColor: Color
    let selectedTextColor: Color
    let selectedSecondaryColor: Color
    let isSelected: Bool
    let favoriteAction: () -> Void
    let ratingAction: (Int) -> Void

    private var width: CGFloat { previewWidth ?? CGFloat(definition.width) }
    private var alignment: Alignment { definition.column.isRightAligned ? .trailing : .leading }

    var body: some View {
        content
            .frame(width: width, alignment: alignment)
    }

    @ViewBuilder
    private var content: some View {
        switch definition.column {
        case .title: label(displayValues.text(for: .title) ?? track.title, primary: true)
        case .artist, .sortArtist: label(track.artist)
        case .album, .sortAlbum: label(track.album)
        case .albumArtist, .sortAlbumArtist: label(track.albumArtist)
        case .albumRating: number(displayValues.text(for: .albumRating) ?? "—")
        case .genre: label(track.genre)
        case .comments, .description: label(track.comment)
        case .composer, .sortComposer: label(track.composer)
        case .duration: number(displayValues.text(for: .duration) ?? "—")
        case .rating:
            Button("Favorite", systemImage: track.isLoved ? "heart.fill" : "heart", action: favoriteAction)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(
                    track.isLoved
                        ? Color.accentColor
                        : (isSelected ? selectedTextColor : secondaryColor.opacity(0.55))
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityAddTraits(track.isLoved ? .isSelected : [])
                .accessibilityInputLabels(["Favorite", "Favorite \(track.title)"])
        case .playCount: number(displayValues.text(for: .playCount) ?? "—")
        case .dateAdded: label(displayValues.text(for: .dateAdded) ?? "—")
        case .dateModified: label(displayValues.text(for: .dateModified) ?? "—")
        case .lastPlayed: label(displayValues.text(for: .lastPlayed) ?? "—")
        case .bitRate: number(displayValues.text(for: .bitRate) ?? "—")
        case .sampleRate: number(displayValues.text(for: .sampleRate) ?? "—")
        case .kind: label(displayValues.text(for: .kind) ?? "—")
        case .starRating:
            TrackStarRatingControl(
                rating: Binding(
                    get: { track.rating },
                    set: { ratingAction($0) }
                ),
                starSize: 10
            )
            .frame(maxWidth: .infinity, alignment: .center)
        case .releaseDate: number(displayValues.text(for: .releaseDate) ?? "—")
        case .year: number(displayValues.text(for: .year) ?? "—")
        case .size: number(displayValues.text(for: .size) ?? "—")
        case .sortTitle: label(track.title)
        case .trackNumber: number(displayValues.text(for: .trackNumber) ?? "—")
        case .beatsPerMinute: number(displayValues.text(for: .beatsPerMinute) ?? "—")
        case .discNumber: number(displayValues.text(for: .discNumber) ?? "—")
        case .grouping, .lastSkipped, .movementName,
             .movementNumber, .skipCount, .work:
            label("—")
        }
    }

    private func label(_ value: String, primary: Bool = false) -> some View {
        Text(value)
            .foregroundStyle(isSelected ? selectedTextColor : (primary ? textColor : secondaryColor))
            .lineLimit(1)
    }

    private func number(_ value: String) -> some View {
        Text(value)
            .font(.caption.monospacedDigit())
            .foregroundStyle(isSelected ? selectedSecondaryColor : secondaryColor)
            .lineLimit(1)
    }

}
