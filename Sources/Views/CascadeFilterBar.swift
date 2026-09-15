import SwiftUI
import AppKit

/// Canonical column order for the cascade filter browser.
/// Reference order: Genre → Artist → Album (matching Nightingale's original layout).
public enum CascadeFilterColumn: CaseIterable {
    case genre
    case artist
    case album

    /// The default cascade order used by the filter browser.
    public static let defaultOrder: [CascadeFilterColumn] = [.genre, .artist, .album]
}

/// Keeps high-frequency pointer state out of the filter browser so resizing
/// cannot rebuild the library facets or persist preferences on every mouse move.
private struct CascadeFilterResizeHandle: View {
    let currentHeight: CGFloat
    let maximumHeight: CGFloat
    let dividerColor: Color
    let indicatorColor: Color
    let onPreview: (CGFloat?) -> Void
    let onCommit: (CGFloat) -> Void

    @State private var dragStartHeight: CGFloat?
    @State private var dragStartY: CGFloat?
    @State private var pendingHeight: CGFloat?

    private var displayedHeight: CGFloat {
        pendingHeight ?? currentHeight
    }

    var body: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .frame(height: 8)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(pendingHeight == nil ? indicatorColor : Color.accentColor)
                    .frame(width: 36, height: 3)
                    .accessibilityHidden(true)
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartHeight == nil {
                            dragStartHeight = currentHeight
                            dragStartY = value.startLocation.y
                        }
                        guard let start = dragStartHeight, let startY = dragStartY else { return }
                        let nextHeight = clamped(start + value.location.y - startY)
                        pendingHeight = nextHeight
                        onPreview(nextHeight)
                    }
                    .onEnded { value in
                        let finalHeight = pendingHeight
                            ?? clamped(currentHeight + value.translation.height)
                        onCommit(finalHeight)
                        onPreview(nil)
                        pendingHeight = nil
                        dragStartHeight = nil
                        dragStartY = nil
                    }
            )
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.upArrow) {
                onCommit(clamped(currentHeight - 20))
                return .handled
            }
            .onKeyPress(.downArrow) {
                onCommit(clamped(currentHeight + 20))
                return .handled
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("library.cascadeDivider")
            .accessibilityLabel("Filter browser height") // [VERIFY] confirm label matches intent
            .accessibilityValue("\(Int(displayedHeight)) points")
            .accessibilityHint("Drag vertically, or use the arrow keys, to resize the filter browser.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    onCommit(clamped(currentHeight + 20))
                case .decrement:
                    onCommit(clamped(currentHeight - 20))
                @unknown default:
                    break
                }
            }
            .help("Drag to resize browser")
    }

    private func clamped(_ height: CGFloat) -> CGFloat {
        CascadeFilterHeightPolicy.resolve(requested: height, maximum: maximumHeight)
    }
}

enum CascadeFilterHeightPolicy {
    static let headerHeight: CGFloat = 22
    static let rowHeight: CGFloat = 28
    static let minimumRows = 2
    static let minimumHeight: CGFloat = 78
    static let defaultHeight: CGFloat = 134

    static func resolve(requested: CGFloat, maximum: CGFloat) -> CGFloat {
        let maximumRows = max(
            minimumRows,
            Int(floor((max(maximum, minimumHeight) - headerHeight) / rowHeight))
        )
        let requestedRows = Int(
            ((requested - headerHeight) / rowHeight).rounded(.toNearestOrAwayFromZero)
        )
        let rows = min(maximumRows, max(minimumRows, requestedRows))
        return headerHeight + CGFloat(rows) * rowHeight
    }
}

/// A single immutable snapshot of the expensive, locale-sorted filter catalogs.
/// Reference identity lets the live-resize container skip rebuilding all rows.
private final class CascadeFilterCatalog {
    let artists: [String]
    let albums: [TrackTableAlbumFacet]
    let genres: [String]

    init(artists: [String], albums: [TrackTableAlbumFacet], genres: [String]) {
        self.artists = artists
        self.albums = albums
        self.genres = genres
    }
}

private struct CascadeFilterColumns: View {
    let catalog: CascadeFilterCatalog
    @Binding var selectedArtist: String?
    @Binding var selectedAlbumIDs: Set<String>
    @Binding var selectedGenre: String?
    let textColor: Color
    let secondaryColor: Color
    let selectedBackground: Color
    let headerBackground: Color

    @EnvironmentObject private var actions: LibraryItemActionHandler
    @State private var albumsPendingDelete: [TrackTableAlbumFacet] = []

    var body: some View {
        HStack(spacing: 1) {
            filterColumn(
                title: "Genre",
                items: catalog.genres,
                selection: $selectedGenre
            ) {
                selectedArtist = nil
                selectedAlbumIDs.removeAll()
            }
            filterColumn(
                title: "Album Artist",
                items: catalog.artists,
                selection: $selectedArtist
            ) {
                selectedAlbumIDs.removeAll()
            }
            albumColumn
        }
    }

    private var albumColumn: some View {
        VStack(spacing: 0) {
            columnHeader("Album")
            filterRow(label: "All", isSelected: selectedAlbumIDs.isEmpty) {
                selectedAlbumIDs.removeAll()
            }
            List(selection: $selectedAlbumIDs) {
                ForEach(catalog.albums) { album in
                    albumRow(album)
                        .tag(album.id)
                        .contextMenu { albumContextMenu(for: album) }
                        .accessibilityAction(named: "Go to Album") {
                            guard let albumID = album.albumIDs.first else { return }
                            actions.showAlbum(albumID: albumID)
                        }
                        .listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, CascadeFilterHeightPolicy.rowHeight)
            .tint(selectedBackground)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity)
        .alert(
            albumsPendingDelete.count == 1 ? "Delete Album?" : "Delete Albums?",
            isPresented: Binding(
                get: { albumsPendingDelete.isEmpty == false },
                set: { if $0 == false { albumsPendingDelete = [] } }
            )
        ) {
            Button("Cancel", role: .cancel) { albumsPendingDelete = [] }
            Button("Delete", role: .destructive) {
                let albums = albumsPendingDelete
                albumsPendingDelete = []
                actions.deleteAlbum(
                    albumIDs: albums.flatMap(\.albumIDs),
                    trackIDs: albums.flatMap(\.trackIDs)
                )
            }
        } message: {
            Text("This removes the selected album\(albumsPendingDelete.count == 1 ? "" : "s") and all of their tracks from the library. The audio files will not be deleted.")
        }
    }

    private func filterColumn(
        title: String,
        items: [String],
        selection: Binding<String?>,
        onChange: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            columnHeader(title)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    filterRow(label: "All", isSelected: selection.wrappedValue == nil) {
                        selection.wrappedValue = nil
                        onChange()
                    }
                    ForEach(items, id: \.self) { item in
                        filterRow(label: item, isSelected: selection.wrappedValue == item) {
                            selection.wrappedValue = item
                            onChange()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func columnHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundColor(secondaryColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: CascadeFilterHeightPolicy.headerHeight)
            .background(headerBackground)
    }

    private func filterRow(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .foregroundColor(textColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: CascadeFilterHeightPolicy.rowHeight)
                .background(isSelected ? selectedBackground : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func albumRow(_ album: TrackTableAlbumFacet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(album.title)
                .font(.caption)
                .foregroundColor(textColor)
                .lineLimit(1)
            if let detail = album.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(secondaryColor)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CascadeFilterHeightPolicy.rowHeight)
        .contentShape(Rectangle())
        .help([album.title, album.detail].compactMap { $0 }.joined(separator: " — "))
    }

    @ViewBuilder
    private func albumContextMenu(for clickedAlbum: TrackTableAlbumFacet) -> some View {
        let albums = selectedAlbumIDs.contains(clickedAlbum.id)
            ? catalog.albums.filter { selectedAlbumIDs.contains($0.id) }
            : [clickedAlbum]
        let trackIDs = albums.flatMap(\.trackIDs)

        Button("Play") { actions.requestPlay(trackIDs: trackIDs) }
        Button("Play Next") { actions.playNext(trackIDs: trackIDs) }
        Button("Add to Queue") { actions.addToQueue(trackIDs: trackIDs) }
        Button("Shuffle") { actions.requestPlay(trackIDs: trackIDs, shuffled: true) }

        Divider()
        Button("Go to Album") {
            guard albums.count == 1, let albumID = albums.first?.albumIDs.first else { return }
            actions.showAlbum(albumID: albumID)
        }
        .disabled(albums.count != 1 || albums.first?.albumIDs.isEmpty != false)
        PlaylistDestinationMenu(trackIDs: trackIDs)

        Divider()
        Button("Edit Metadata…") { actions.showInfo(trackIDs: trackIDs) }
        Button("Show in Finder") { actions.showInFinder(trackIDs: trackIDs) }
            .disabled(actions.canShowInFinder(trackIDs: trackIDs) == false)
        Button("Re-read Metadata") { actions.refreshMetadata(trackIDs: trackIDs) }
            .disabled(actions.canRefreshMetadata(trackIDs: trackIDs) == false)
        Button("Add to Favorites") {
            actions.setAlbumFavorite(true, albumIDs: albums.flatMap(\.albumIDs))
        }

        Divider()
        Button(albums.count == 1 ? "Delete Album…" : "Delete \(albums.count) Albums…", role: .destructive) {
            albumsPendingDelete = albums
        }
    }
}

/// Owns only the live geometry. Updating this state relays out the browser and
/// track list, while the equatable catalog subtree remains untouched.
private struct CascadeFilterResizableBrowser: View {
    let catalog: CascadeFilterCatalog
    let persistedHeight: CGFloat
    let maximumHeight: CGFloat
    @Binding var selectedArtist: String?
    @Binding var selectedAlbumIDs: Set<String>
    @Binding var selectedGenre: String?
    let textColor: Color
    let secondaryColor: Color
    let selectedBackground: Color
    let headerBackground: Color
    let browserBackground: Color
    let dividerColor: Color
    let onCommit: (CGFloat) -> Void

    @State private var previewHeight: CGFloat?

    private var height: CGFloat {
        previewHeight ?? persistedHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            CascadeFilterColumns(
                catalog: catalog,
                selectedArtist: $selectedArtist,
                selectedAlbumIDs: $selectedAlbumIDs,
                selectedGenre: $selectedGenre,
                textColor: textColor,
                secondaryColor: secondaryColor,
                selectedBackground: selectedBackground,
                headerBackground: headerBackground
            )
            .frame(height: height)
            .clipped()
            .background(browserBackground)

            CascadeFilterResizeHandle(
                currentHeight: height,
                maximumHeight: maximumHeight,
                dividerColor: dividerColor,
                indicatorColor: secondaryColor.opacity(0.35),
                onPreview: { previewHeight = $0 },
                onCommit: onCommit
            )
        }
    }
}

/// Classic Songbird-style cascade filters: Artist → Album → Genre.
public struct CascadeFilterBar: View {
    let facets: TrackTableFacets
    let maximumHeight: CGFloat
    @Binding var selectedArtist: String?
    @Binding var selectedAlbumIDs: Set<String>
    @Binding var selectedGenre: String?

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SongbirdThemeID.storageKey) private var themeID = SongbirdThemeID.blueMonday.rawValue
    @AppStorage("cascadeFilter.height") private var storedHeight = 134.0
    @AppStorage("cascadeFilter.visible") private var isVisible = true

    public static let minHeight = CascadeFilterHeightPolicy.minimumHeight
    public static let defaultHeight = CascadeFilterHeightPolicy.defaultHeight

    private var featherTreatment: SongbirdFeatherTreatment {
        .treatment(for: SongbirdThemeID.resolved(rawValue: themeID))
    }
    private var textColor: Color {
        featherTreatment.usesBlueMondayChrome
            ? Color(red: 0.88, green: 0.89, blue: 0.91)
            : SongbirdTheme.text(for: colorScheme)
    }
    private var secondaryColor: Color {
        featherTreatment.usesBlueMondayChrome
            ? Color(red: 0.64, green: 0.66, blue: 0.70)
            : SongbirdTheme.secondaryText(for: colorScheme)
    }
    private var selectedBg: Color { SongbirdTheme.sidebarSelected(for: colorScheme) }

    public var body: some View {
        let artistValues = facets.artists
        let albumValues = facets.albums
        let genreValues = facets.genres
        let browserHeight = CascadeFilterHeightPolicy.resolve(
            requested: CGFloat(storedHeight),
            maximum: maximumHeight
        )
        let catalog = CascadeFilterCatalog(
            artists: artistValues,
            albums: albumValues,
            genres: genreValues
        )

        CascadeFilterResizableBrowser(
            catalog: catalog,
            persistedHeight: browserHeight,
            maximumHeight: maximumHeight,
            selectedArtist: $selectedArtist,
            selectedAlbumIDs: $selectedAlbumIDs,
            selectedGenre: $selectedGenre,
            textColor: textColor,
            secondaryColor: secondaryColor,
            selectedBackground: selectedBg,
            headerBackground: SongbirdTheme.nowPlayingBar(for: colorScheme),
            browserBackground: SongbirdTheme.sidebar(for: colorScheme),
            dividerColor: SongbirdTheme.divider(for: colorScheme)
        ) { newHeight in
            // Persist only after mouse-up; live geometry stays inside the lightweight
            // resize container and never rebuilds the locale-sorted catalogs.
            storedHeight = Double(CascadeFilterHeightPolicy.resolve(
                requested: newHeight,
                maximum: maximumHeight
            ))
        }
        .overlay(alignment: .topTrailing) {
            Button {
                isVisible = false
            } label: {
                Image(systemName: "rectangle.compress.vertical")
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Hide Browser") // [VERIFY] matches the View menu command
            .accessibilityHint("Hides the Album Artist, Album, and Genre browser.")
            .help("Hide Browser (⌥⌘B)")
            .padding(.trailing, 4)
        }
    }
}
