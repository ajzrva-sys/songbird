import AppKit
import SwiftUI

private struct AlbumSnapshotProjectionInput: Hashable {
    let structureRevision: Int
    let presentationRevision: Int
}

enum AlbumGridLayout {
    static func columns(artworkSize: CGFloat, spacing: CGFloat) -> [GridItem] {
        [GridItem(
            .adaptive(minimum: artworkSize, maximum: artworkSize),
            spacing: spacing,
            alignment: .top
        )]
    }

    static func columnCount(
        forContentWidth width: CGFloat,
        artworkSize: CGFloat,
        spacing: CGFloat
    ) -> Int {
        max(1, Int((max(0, width) + spacing) / (artworkSize + spacing)))
    }
}

struct AlbumGridSelectionState: Equatable {
    private(set) var selectedIDs: Set<String> = []
    private(set) var anchorID: String?

    mutating func select(
        _ id: String,
        in orderedIDs: [String],
        modifiers: NSEvent.ModifierFlags
    ) {
        if modifiers.contains(.command) {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
            anchorID = id
            return
        }

        if modifiers.contains(.shift),
           let anchorID,
           let anchor = orderedIDs.firstIndex(of: anchorID),
           let target = orderedIDs.firstIndex(of: id) {
            selectedIDs = Set(orderedIDs[min(anchor, target)...max(anchor, target)])
            return
        }

        selectedIDs = [id]
        anchorID = id
    }

    mutating func retain(validIDs: Set<String>) {
        selectedIDs.formIntersection(validIDs)
        if let anchorID, validIDs.contains(anchorID) == false {
            self.anchorID = nil
        }
    }

    mutating func remove(_ ids: Set<String>) {
        selectedIDs.subtract(ids)
        if let anchorID, ids.contains(anchorID) {
            self.anchorID = selectedIDs.first
        }
    }
}

public struct AlbumGridView: View {
    public let scope: AlbumGridScope
    public let showsTitle: Bool
    @EnvironmentObject private var librarySnapshots: LibrarySnapshotStore
    @EnvironmentObject private var albumProjectionStore: LibraryAlbumProjectionStore
    @EnvironmentObject private var actions: LibraryItemActionHandler
    @EnvironmentObject private var librarySearch: LibrarySearchCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AlbumGridSettings.artworkSizeKey)
    private var storedArtworkSize = AlbumGridSettings.defaultArtworkSize
    @AppStorage(AlbumGridSettings.gridSpacingKey)
    private var storedGridSpacing = AlbumGridSettings.defaultGridSpacing

    private var bgColor: Color { SongbirdTheme.background(for: colorScheme) }
    private var textColor: Color { SongbirdTheme.text(for: colorScheme) }
    private var secondaryTextColor: Color { SongbirdTheme.secondaryText(for: colorScheme) }
    @State private var sortOrder: AlbumSortOrder
    @State private var favoritesOnly = false
    @State private var albumsPendingDelete: [LibraryAlbumGroupSnapshot] = []
    @State private var showsDeleteConfirmation = false
    @State private var albumsPendingMetadataRefresh: [LibraryAlbumGroupSnapshot] = []
    @State private var showsMetadataConfirmation = false
    @State private var selection = AlbumGridSelectionState()
    @State private var gridProjection: AlbumGridProjection = .empty
    @State private var gridProjectionWorker = AlbumGridProjectionWorker()
    @State private var summaryOwner = LibraryContentSummaryOwner()
    @State private var pendingScrollRestore = true
    @State private var scrollAnchorID: String?
    @FocusState private var searchFocused: Bool

    private var artworkSize: CGFloat {
        CGFloat(AlbumGridSettings.normalizedArtworkSize(storedArtworkSize))
    }

    private var gridSpacing: CGFloat {
        CGFloat(AlbumGridSettings.normalizedGridSpacing(storedGridSpacing))
    }

    private var columns: [GridItem] {
        AlbumGridLayout.columns(artworkSize: artworkSize, spacing: gridSpacing)
    }

    public init(
        initialSortOrder: AlbumSortOrder = .title,
        scope: AlbumGridScope = .all,
        showsTitle: Bool = true
    ) {
        self.scope = scope
        self.showsTitle = showsTitle
        _sortOrder = State(initialValue: initialSortOrder)
    }

    private var gridProjectionRequest: AlbumGridProjectionRequest {
        AlbumGridProjectionRequest(
            sourceRevision: albumProjectionStore.projectionRevision,
            searchText: librarySearch.query,
            favoritesOnly: favoritesOnly,
            sortOrder: sortOrder,
            scope: scope
        )
    }

    private var albumSnapshotProjectionInput: AlbumSnapshotProjectionInput {
        AlbumSnapshotProjectionInput(
            structureRevision: librarySnapshots.snapshot.albumStructureRevision,
            presentationRevision: librarySnapshots.snapshot.albumPresentationRevision
        )
    }

    private var isGridProjectionCurrent: Bool {
        gridProjection.request == gridProjectionRequest
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if showsTitle {
                        Text(pageTitle).font(.title2.weight(.semibold))
                    }
                    Text(isGridProjectionCurrent ? "\(gridProjection.groups.count) albums" : "Updating albums…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Favorites Only", isOn: $favoritesOnly)
                    .toggleStyle(.button)
                if allowsSorting {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(AlbumSortOrder.allCases) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            HStack(spacing: 12) {
                LibrarySearchField(scopeTitle: pageTitle, focused: $searchFocused)
                Spacer(minLength: 0)
                AlbumGridViewControls(artworkSize: $storedArtworkSize, gridSpacing: $storedGridSpacing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(gridProjection.groups) { group in
                        AlbumGridItem(
                            album: group,
                            artworkSize: artworkSize,
                            displayDetail: gridProjection.displayDetails[group.id],
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                            colorScheme: colorScheme,
                            isSelected: selection.selectedIDs.contains(group.id),
                            contextAlbums: { contextAlbums(for: group) },
                            selectionAction: { modifiers in
                                select(group, modifiers: modifiers)
                            },
                            openAction: { open(group) },
                            refreshMetadataAction: {
                                albumsPendingMetadataRefresh = contextAlbums(for: group)
                                showsMetadataConfirmation = true
                            },
                            deleteAction: {
                                albumsPendingDelete = contextAlbums(for: group)
                                showsDeleteConfirmation = true
                            }
                        )
                        .id(group.id)
                    }
                }
                .padding()
            }
            .scrollPosition(id: $scrollAnchorID, anchor: .center)
            .onChange(of: gridProjection.orderedIDs) { _, orderedIDs in
                guard pendingScrollRestore, orderedIDs.isEmpty == false else { return }
                restoreScrollIfNeeded()
            }
            .onAppear {
                guard pendingScrollRestore, gridProjection.orderedIDs.isEmpty == false else { return }
                restoreScrollIfNeeded()
            }
            .overlay {
                switch albumProjectionStore.state {
                case .loading(let previous) where previous == nil:
                    ProgressView("Loading Albums…")
                case .failed(let message, let previous) where previous == nil:
                    ContentUnavailableView {
                        Label("Albums Could Not Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") {
                            Task {
                                await albumProjectionStore.update(
                                    from: librarySnapshots.snapshot,
                                    force: true
                                )
                            }
                        }
                    }
                case .loaded where librarySnapshots.snapshot.albums.isEmpty:
                    ContentUnavailableView {
                        Label("No Albums", systemImage: "square.stack")
                    } description: {
                        Text("Import music to populate albums.")
                    } actions: {
                        Button("Import Music…") { ImportSetupWindowPresenter.show() }
                    }
                case .loaded where !isGridProjectionCurrent && gridProjection.groups.isEmpty:
                    ProgressView("Updating Albums…")
                case .loaded where gridProjection.groups.isEmpty:
                    albumEmptyState
                default:
                    EmptyView()
                }
            }
            .overlay(alignment: .topTrailing) {
                if isRefreshingAlbums {
                    ProgressView()
                        .controlSize(.small)
                        .padding(12)
                }
            }
        }
        .accessibilityIdentifier("library.albumGrid")
        .background(bgColor)
        .onAppear { LibraryStatus.shared.summary.activate(owner: summaryOwner) }
        .onDisappear { LibraryStatus.shared.summary.clear(owner: summaryOwner) }
        .task(id: albumSnapshotProjectionInput) {
            await albumProjectionStore.update(from: librarySnapshots.snapshot)
        }
        .task(id: gridProjectionRequest) {
            guard let projected = try? await gridProjectionWorker.project(
                groups: albumProjectionStore.groups,
                request: gridProjectionRequest
            ), Task.isCancelled == false else { return }
            gridProjection = projected
            UsabilityPerformanceSignposts.usefulProjectionPublished(
                revision: gridProjectionRequest.sourceRevision
            )
            selection.retain(validIDs: Set(projected.orderedIDs))
            LibraryStatus.shared.summary.update(
                owner: summaryOwner,
                summary: .albums(
                    albumCount: projected.groups.count,
                    trackCount: Set(projected.groups.flatMap(\.trackIDs)).count
                )
            )
        }
        .focusedValue(
            \.librarySearchCommands,
            FocusedLibrarySearchCommands(focusSearch: librarySearch.requestFocus)
        )
        .alert(deleteAlertTitle, isPresented: $showsDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                albumsPendingDelete = []
            }
            Button("Delete from Library", role: .destructive) {
                deleteFromLibrary(albumsPendingDelete)
                albumsPendingDelete = []
            }
        } message: {
            Text(deleteAlertMessage)
        }
        .alert(metadataAlertTitle, isPresented: $showsMetadataConfirmation) {
            Button("Cancel", role: .cancel) { albumsPendingMetadataRefresh = [] }
            Button("Re-read Metadata") {
                actions.refreshMetadata(trackIDs: metadataTrackIDs)
                albumsPendingMetadataRefresh = []
            }
        } message: {
            Text("Songbird will re-read metadata for \(metadataTrackIDs.count) tracks. You can cancel from the status bar.")
        }
    }

    private var pageTitle: String {
        switch scope {
        case .all: "Albums"
        case .recentlyAdded: "Recently Added"
        case .artist(let name): name
        }
    }

    private var allowsSorting: Bool {
        if case .recentlyAdded = scope { return false }
        return true
    }

    private var isRefreshingAlbums: Bool {
        if case .loading(let previous) = albumProjectionStore.state, previous != nil { return true }
        return !isGridProjectionCurrent && !gridProjection.groups.isEmpty
    }

    private func open(_ group: LibraryAlbumGroupSnapshot) {
        LibraryViewState.saveAlbumGridAnchor(group.id, for: scope)
        guard let albumID = group.albumIDs.first else { return }
        actions.showAlbum(albumID: albumID)
    }

    private func restoreScrollIfNeeded() {
        pendingScrollRestore = false
        guard let groupID = LibraryViewState.resolveScrollGroupID(
            in: gridProjection,
            scope: scope
        ) else { return }
        // Defer one turn so the lazy grid has identity for the target row.
        Task { @MainActor in
            await Task.yield()
            scrollAnchorID = groupID
        }
    }

    @ViewBuilder
    private var albumEmptyState: some View {
        if case .artist(let name) = scope,
           librarySearch.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !favoritesOnly {
            ContentUnavailableView(
                "No Albums",
                systemImage: "square.stack",
                description: Text("Albums containing tracks by \(name) appear here.")
            )
        } else {
            filteredAlbumEmptyState
        }
    }

    @ViewBuilder
    private var filteredAlbumEmptyState: some View {
        switch AlbumGridEmptyReason.resolve(
            searchText: librarySearch.query,
            favoritesOnly: favoritesOnly
        ) {
        case .noFavorites:
            ContentUnavailableView {
                Label("No Favorite Albums", systemImage: "heart")
            } description: {
                Text("Mark an album as a favorite, or turn off the Favorites filter.")
            } actions: {
                Button("Show All Albums") { favoritesOnly = false }
            }
        case .search(let query, let favoritesOnly):
            if favoritesOnly {
                ContentUnavailableView {
                    Label("No Favorite Albums Match", systemImage: "heart.slash")
                } description: {
                    Text("No favorite albums match “\(query)”. Clear the search or turn off the Favorites filter.")
                } actions: {
                    Button("Clear Search") { librarySearch.clear() }
                    Button("Show All Albums") { self.favoritesOnly = false }
                }
            } else {
                ContentUnavailableView {
                    Label("No Albums Match", systemImage: "magnifyingglass")
                } description: {
                    Text("No albums match “\(query)”.")
                } actions: {
                    Button("Clear Search") { librarySearch.clear() }
                }
            }
        }
    }

    private func select(
        _ group: LibraryAlbumGroupSnapshot,
        modifiers: NSEvent.ModifierFlags
    ) {
        selection.select(
            group.id,
            in: gridProjection.orderedIDs,
            modifiers: modifiers
        )
    }

    private func contextAlbums(
        for clickedAlbum: LibraryAlbumGroupSnapshot
    ) -> [LibraryAlbumGroupSnapshot] {
        let selected = gridProjection.contextAlbums(
            clickedID: clickedAlbum.id,
            selectedIDs: selection.selectedIDs
        )
        return selected.isEmpty ? [clickedAlbum] : selected
    }

    private func deleteFromLibrary(_ groups: [LibraryAlbumGroupSnapshot]) {
        let groupIDs = Set(groups.map(\.id))
        let result = actions.deleteAlbum(
            albumIDs: orderedUnique(groups.flatMap(\.albumIDs)),
            trackIDs: orderedUnique(groups.flatMap(\.trackIDs))
        )
        if case .success = result {
            selection.remove(groupIDs)
        }
    }

    private var metadataTrackIDs: [UUID] {
        orderedUnique(albumsPendingMetadataRefresh.flatMap(\.trackIDs))
    }

    private var deleteAlertTitle: String {
        albumsPendingDelete.count == 1
            ? "Delete Album?"
            : "Delete \(albumsPendingDelete.count) Albums?"
    }

    private var deleteAlertMessage: String {
        if albumsPendingDelete.count == 1, let album = albumsPendingDelete.first {
            let count = album.trackIDs.count
            let tracks = count == 1 ? "1 track" : "\(count) tracks"
            return "“\(album.title)” and its \(tracks) will be removed from your library. The files on disk are not deleted."
        }
        let count = orderedUnique(albumsPendingDelete.flatMap(\.trackIDs)).count
        return "The selected albums and their \(count) tracks will be removed from your library. The files on disk are not deleted."
    }

    private var metadataAlertTitle: String {
        albumsPendingMetadataRefresh.count == 1
            ? "Re-read Album Metadata?"
            : "Re-read \(albumsPendingMetadataRefresh.count) Albums’ Metadata?"
    }

    private func orderedUnique<ID: Hashable>(_ ids: [ID]) -> [ID] {
        var seen: Set<ID> = []
        return ids.filter { seen.insert($0).inserted }
    }
}

public struct AlbumCard: View {
    let title: String
    let artist: String
    let artworkSize: CGFloat
    let displayDetail: String?
    let discCount: Int
    let isFavorite: Bool
    let artworkReference: ArtworkReference?
    let textColor: Color
    let secondaryTextColor: Color
    let colorScheme: ColorScheme
    var selectionAction: ((NSEvent.ModifierFlags) -> Void)? = nil
    var openAction: (() -> Void)? = nil
    var playAction: (() -> Void)? = nil
    var showsPlayAction = false

    public var body: some View {
        VStack(alignment: .leading) {
            ArtworkThumbnailView(
                reference: artworkReference,
                pointSize: CGSize(width: artworkSize, height: artworkSize),
                accessibilityLabel: "Album artwork for \(title)",
                cornerRadius: 8,
                placeholderSymbol: "square.stack",
                placeholderColor: SongbirdTheme.placeholder(for: colorScheme)
            )
            .overlay(alignment: .topTrailing) {
                if isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.3), in: Circle())
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }
            .overlay { selectionOverlay }
            .overlay(alignment: .bottomTrailing) {
                if let playAction {
                    AlbumCardPlayButton(title: title, action: playAction, isRevealed: showsPlayAction)
                        .padding(8)
                }
            }

            if let openAction {
                AlbumCardOpenButton(
                    title: title,
                    textColor: textColor,
                    action: openAction,
                    selectionAction: selectionAction
                )
            } else {
                titleLabel
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(discCount > 1 ? "\(artist) · \(discCount) discs" : artist)
                    .font(.caption2)
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
                if let displayDetail {
                    Text(displayDetail)
                        .font(.caption2)
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(1)
                }
            }
            .overlay { selectionOverlay }
            .help(artist)
        }
        .cornerRadius(10)
    }

    private var titleLabel: some View {
        Text(title)
            .font(.caption.bold())
            .foregroundColor(textColor)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .help(title)
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if let selectionAction, let playAction {
            MacClickActivationView(singleClick: selectionAction, doubleClick: playAction)
        }
    }
}
