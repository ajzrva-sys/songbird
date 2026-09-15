import SwiftUI

/// Routes the main content area from service-pane selection.
public struct LibraryContentView: View {
    let destination: ServicePaneDestination

    @EnvironmentObject private var librarySnapshots: LibrarySnapshotStore
    @EnvironmentObject private var libraryNavigation: LibraryNavigationCoordinator
    @Environment(\.colorScheme) private var colorScheme

    public init(destination: ServicePaneDestination) {
        self.destination = destination
    }

    public var body: some View {
        switch destination {
        case .allTracks:
            TrackTableView(title: "All Tracks", collection: .allTracks, showsHeader: false)
        case .artists:
            BrowseListView(
                title: "Artists",
                items: artistItems,
                onSelect: { libraryNavigation.showArtist(name: $0) }
            )
        case .albums:
            AlbumGridView()
        case .genres:
            BrowseListView(
                title: "Genres",
                items: genreItems,
                showsDistribution: true,
                onSelect: { libraryNavigation.showGenre(name: $0) }
            )
        case .recentlyAdded:
            AlbumGridView(initialSortOrder: .recentlyAdded, scope: .recentlyAdded(limit: 100))
        case .topPlayed:
            TrackTableView(
                title: "Top Played",
                collection: .topPlayed,
                showsFilters: false,
                showsHeader: false,
                emptyMessage: "Nothing Played Yet",
                emptyHint: "Play some tracks to build this list"
            )
        case .healthDashboard:
            LibraryHealthDashboardView()
        case .ghostTracks:
            LibraryHealthDetailView(category: .missingFiles)
        case .unavailableTracks:
            LibraryHealthDetailView(category: .unavailableVolumes)
        case .missingGenre:
            LibraryHealthDetailView(category: .missingGenre)
        case .missingArtwork:
            LibraryHealthDetailView(category: .missingArtwork)
        case .unknownArtist:
            LibraryHealthDetailView(category: .missingArtistNames)
        case .unknownAlbum:
            MissingAlbumView()
        case .missingTrackNumber:
            LibraryHealthDetailView(category: .missingTrackNumber)
        case .inconsistentArtists:
            LibraryHealthDetailView(category: .inconsistentArtists)
        case .inconsistentAlbums:
            LibraryHealthDetailView(category: .inconsistentAlbums)
        case .emptyTitles:
            LibraryHealthDetailView(category: .emptyTitles)
        case .missingYear:
            LibraryHealthDetailView(category: .missingYear)
        case .lowBitrate:
            LibraryHealthDetailView(category: .lowBitrate)
        case .inconsistentGenres:
            LibraryHealthDetailView(category: .inconsistentGenres)
        case .filledComments:
            LibraryHealthDetailView(category: .filledComments)
        case .inconsistentAlbumArtists:
            LibraryHealthDetailView(category: .inconsistentAlbumArtists)
        case .duplicateTracks:
            DuplicateTracksView()
        case .queue:
            PlayQueueView()
        case .playlist(let id):
            PlaylistContentView(playlistID: id)
        case .audioCD(let id):
            AudioCDView(discID: id)
        }
    }

    private var artistItems: [BrowseListItem] {
        let grouped = Dictionary(grouping: librarySnapshots.snapshot.tracks, by: \.artist)
        return librarySnapshots.snapshot.artistNames.map { artist in
            let tracks = grouped[artist] ?? []
            let albumCount = Set(tracks.compactMap(\.albumID)).count
            let detail = "\(tracks.count) track\(tracks.count == 1 ? "" : "s") · \(albumCount) album\(albumCount == 1 ? "" : "s")"
            return BrowseListItem(name: artist, detail: detail)
        }
    }

    private var genreItems: [BrowseListItem] {
        let tracks = librarySnapshots.snapshot.tracks
        return librarySnapshots.snapshot.genreNames.map { genre in
            let count = tracks.count { $0.genre.localizedCaseInsensitiveCompare(genre) == .orderedSame }
            return BrowseListItem(
                name: genre,
                detail: "\(count) track\(count == 1 ? "" : "s")",
                metric: count
            )
        }
    }

}

/// Simple name list that pushes a filtered track table.
public struct BrowseListView: View {
    let title: String
    let items: [BrowseListItem]
    var showsDistribution = false
    let onSelect: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var librarySearch: LibrarySearchCoordinator
    @State private var selection = BrowseListSelectionState()

    private var textColor: Color { SongbirdTheme.text(for: colorScheme) }
    private var secondaryColor: Color { SongbirdTheme.secondaryText(for: colorScheme) }

    private var filteredItems: [BrowseListItem] {
        librarySearch.query.isEmpty
            ? items
            : items.filter { $0.name.localizedStandardContains(librarySearch.query) }
    }

    private var largestMetric: Int {
        max(1, items.compactMap(\.metric).max() ?? 1)
    }

    public var body: some View {
        VStack(spacing: 0) {
            List(filteredItems, selection: $selection.selected) { item in
                browseRow(item)
                .tag(item.name)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .onChange(of: selection.selected) { _, _ in
            guard let selected = selection.consume() else { return }
            onSelect(selected)
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "No \(title)",
                    systemImage: "music.note",
                    description: Text("Import music to populate this list.")
                )
            } else if filteredItems.isEmpty {
                ContentUnavailableView.search(text: librarySearch.query)
            }
        }
        .focusedValue(
            \.librarySearchCommands,
            FocusedLibrarySearchCommands(focusSearch: librarySearch.requestFocus)
        )
        .background(SongbirdTheme.background(for: colorScheme))
    }

    @ViewBuilder
    private func browseRow(_ item: BrowseListItem) -> some View {
        HStack {
            Text(item.name)
                .foregroundStyle(textColor)
            Spacer()
            if showsDistribution == false {
                Text(item.detail)
                    .foregroundStyle(secondaryColor)
            }
        }
        .background {
            if showsDistribution, let metric = item.metric {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(
                            width: max(
                                4,
                                geometry.size.width * CGFloat(metric) / CGFloat(largestMetric)
                            )
                        )
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.detail)
        .help(showsDistribution ? "\(item.name): \(item.detail)" : item.detail)
    }
}

struct BrowseListSelectionState: Equatable {
    var selected: String?

    mutating func consume() -> String? {
        defer { selected = nil }
        return selected
    }
}
