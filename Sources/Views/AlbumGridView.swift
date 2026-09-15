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
            spacing: spacing
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
        scope: AlbumGridScope = .all
    ) {
        self.scope = scope
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

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pageTitle).font(.title2.weight(.semibold))
                    Text("\(gridProjection.groups.count) albums")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Favorites Only", isOn: $favoritesOnly)
                    .toggleStyle(.button)
                if case .all = scope {
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
                    }
                }
                .padding()
            }
        }
        .accessibilityIdentifier("library.albumGrid")
        .background(bgColor)
        .onAppear { LibraryStatus.shared.summary.activate(owner: summaryOwner) }
        .onDisappear { LibraryStatus.shared.summary.clear(owner: summaryOwner) }
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
                ContentUnavailableView(
                    "No Albums",
                    systemImage: "square.stack",
                    description: Text("Import music to populate albums.")
                )
            case .loaded where gridProjection.groups.isEmpty:
                albumEmptyState
            default:
                EmptyView()
            }
        }
        .overlay(alignment: .topTrailing) {
            if case .loading(let previous) = albumProjectionStore.state, previous != nil {
                ProgressView()
                    .controlSize(.small)
                    .padding(12)
            }
        }
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
        if case .recentlyAdded = scope { return "Recently Added" }
        return "Albums"
    }

    private func open(_ group: LibraryAlbumGroupSnapshot) {
        guard let albumID = group.albumIDs.first else { return }
        actions.showAlbum(albumID: albumID)
    }

    @ViewBuilder
    private var albumEmptyState: some View {
        switch AlbumGridEmptyReason.resolve(
            searchText: librarySearch.query,
            favoritesOnly: favoritesOnly
        ) {
        case .noFavorites:
            ContentUnavailableView(
                "No Favorite Albums",
                systemImage: "heart",
                description: Text("Mark an album as a favorite, or turn off the Favorites filter.")
            )
        case .search(let query, let favoritesOnly):
            if favoritesOnly {
                ContentUnavailableView {
                    Label("No Favorite Albums Match", systemImage: "heart.slash")
                } description: {
                    Text("No favorite albums match “\(query)”. Clear the search or turn off the Favorites filter.")
                }
            } else {
                ContentUnavailableView.search(text: query)
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

            Text(title)
                .font(.caption.bold())
                .foregroundColor(textColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
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
        .cornerRadius(10)
    }
}
