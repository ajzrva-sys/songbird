import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

public struct ServicePaneView: View {
    @ObservedObject private var discogsClock = DiscogsPresentationClock.shared
    @EnvironmentObject private var queue: PlaybackQueue
    @EnvironmentObject private var playbackActivity: PlaybackActivity
    @EnvironmentObject private var librarySelection: LibrarySelectionState
    @EnvironmentObject private var opticalDiscs: OpticalDiscService
    @EnvironmentObject private var libraryNavigation: LibraryNavigationCoordinator
    @EnvironmentObject private var libraryActions: LibraryItemActionHandler
    @EnvironmentObject private var librarySnapshots: LibrarySnapshotStore
    @Binding var selectedDestination: ServicePaneDestination?
    @Binding var sidebarShown: Bool
    let showsArtworkWell: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SongbirdThemeID.storageKey)
    private var themeID = SongbirdThemeID.blueMonday.rawValue
    @AppStorage(ServicePaneMetrics.storageKey)
    private var metricsRaw = "standard"
    @AppStorage("servicePane.section.library.expanded")
    private var librarySectionExpanded = true
    @AppStorage("servicePane.section.libraryHealth.expanded")
    private var libraryHealthSectionExpanded = true
    @AppStorage("servicePane.section.libraryHealth.files.expanded")
    private var healthFilesExpanded = true
    @AppStorage("servicePane.section.libraryHealth.metadata.expanded")
    private var healthMetadataExpanded = true
    @AppStorage("servicePane.section.libraryHealth.consistency.expanded")
    private var healthConsistencyExpanded = false
    @AppStorage("servicePane.section.libraryHealth.cleanup.expanded")
    private var healthCleanupExpanded = false
    @AppStorage("servicePane.section.playlists.expanded")
    private var playlistsSectionExpanded = true
    @AppStorage("servicePane.section.queue.expanded")
    private var queueSectionExpanded = true
    @State private var newPlaylistName = ""
    @State private var isAddingPlaylist = false
    @State private var showingSmartEditor = false
    @State private var editingSmartPlaylist: SmartPlaylistEditorTarget?
    @FocusState private var newPlaylistFieldFocused: Bool

    private var sidebarBg: Color { SongbirdTheme.sidebar(for: colorScheme) }
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
    private var activeFeather: SongbirdThemeID {
        SongbirdThemeID.resolved(rawValue: themeID)
    }
    private var featherTreatment: SongbirdFeatherTreatment {
        .treatment(for: activeFeather)
    }
    private var sidebarMetrics: ServicePaneMetrics {
        ServicePaneMetrics.resolved(from: metricsRaw)
    }

    private let contentLeadingPad: CGFloat = 12
    /// Clearance for macOS traffic lights in the full-height sidebar titlebar cap.
    private let trafficLightsPadding: CGFloat = 70
    private let titlebarCapHeight: CGFloat = 52

    public init(
        selectedDestination: Binding<ServicePaneDestination?>,
        sidebarShown: Binding<Bool> = .constant(true),
        showsArtworkWell: Bool = true
    ) {
        self._selectedDestination = selectedDestination
        self._sidebarShown = sidebarShown
        self.showsArtworkWell = showsArtworkWell
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                titlebarCap

                ScrollViewReader { proxy in
                    ScrollView {
                        sidebarContent
                    }
                    .scrollIndicators(.automatic)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .onChange(of: selectedDestination) { _, destination in
                        guard let destination else { return }
                        proxy.scrollTo(destination, anchor: .center)
                    }
                    .onChange(of: isAddingPlaylist) { _, isAdding in
                        guard isAdding else { return }
                        Task { @MainActor in
                            await Task.yield()
                            proxy.scrollTo("newPlaylistEditor", anchor: .bottom)
                        }
                    }
                    .task(id: queue.currentTrack?.id) {
                        guard let destination = selectedDestination else { return }
                        await Task.yield()
                        proxy.scrollTo(destination, anchor: .center)
                    }
                }

                if showsArtworkWell,
                   let side = PlayerWindowLayoutPolicy.sidebarArtworkSide(
                    sidebarWidth: geometry.size.width,
                    windowHeight: geometry.size.height
                   ) {
                    sidebarArtworkWell
                        .frame(width: side, height: side)
                        .accessibilityIdentifier("library.sidebar.artwork")
                }
            }
        }
        .accessibilityIdentifier("library.sidebar")
        .background {
            if featherTreatment == .pinkMartini {
                LinearGradient(
                    colors: [
                        sidebarBg,
                        SongbirdTheme.background(for: colorScheme).opacity(0.92),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                sidebarBg
            }
        }
        .overlay(alignment: .trailing) {
            if featherTreatment == .pinkMartini {
                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 1)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showingSmartEditor, onDismiss: { editingSmartPlaylist = nil }) {
            SmartPlaylistEditorView(target: editingSmartPlaylist) { playlistID in
                selectedDestination = .playlist(playlistID)
            }
        }
        .onAppear {
            do {
                try DefaultSmartPlaylists.ensureInstalled(in: modelContext)
            } catch {
                modelContext.rollback()
                LibraryStatus.shared.showPlaybackError(
                    "Could not prepare smart playlists: \(error.localizedDescription)"
                )
            }
        }
        .onChange(of: libraryActions.sidebarPlaylistTargetRequest) { _, request in
            if request != nil {
                playlistsSectionExpanded = true
                newPlaylistName = ""
                isAddingPlaylist = false
            }
        }
    }

    @ViewBuilder
    private var sidebarArtworkWell: some View {
        let selectedDisc: AudioDisc? = {
            guard case .audioCD(let discID) = selectedDestination else { return nil }
            return opticalDiscs.discs.first(where: { $0.id == discID })
        }()
        let displayedTrack = librarySelection.selectedTrack ?? queue.currentTrack
        let displayedTrackDisc = displayedTrack?.audioDiscID.flatMap { discID in
            opticalDiscs.discs.first(where: { $0.id == discID })
        }
        let displayedDisc = selectedDisc ?? displayedTrackDisc
        let localArtworkTrack = selectedDisc == nil ? displayedTrack : nil
        let localAlbum = localArtworkTrack?.albumRelation
        let localArtworkReference: ArtworkReference? = {
            if let track = localArtworkTrack,
               let snapshot = librarySnapshots.trackSnapshot(id: track.id) {
                return snapshot.artworkReference
            }
            guard let album = localAlbum,
                  let artworkData = album.artworkData,
                  artworkData.isEmpty == false else { return nil }
            return .album(id: album.id, persistentIdentifier: album.persistentModelID)
        }()
        let artworkReference = displayedDisc?.artworkReference
            ?? localArtworkReference
        let selectionTitle = displayedDisc?.title ?? displayedTrack?.audioCDMetadata(at: discogsClock.now).album

        if let artworkReference {
            GeometryReader { geometry in
                let side = max(1, geometry.size.width)
                ArtworkThumbnailView(
                    reference: artworkReference,
                    pointSize: CGSize(width: side, height: side),
                    accessibilityLabel: "Album artwork for \(selectionTitle ?? "selected album")",
                    cornerRadius: 0,
                    contentMode: .fit,
                    placeholderSymbol: "photo",
                    placeholderColor: SongbirdTheme.placeholder(for: colorScheme)
                )
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
        } else if let localAlbum {
            MissingAlbumArtworkButton(
                albumTitle: localAlbum.title,
                cornerRadius: 0
            ) {
                libraryActions.searchForArtwork(
                    albumIDs: [localAlbum.id],
                    title: localAlbum.title
                )
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .help("Search Discogs for artwork for \(localAlbum.title)")
        }
    }

    /// Sidebar chrome behind traffic lights (Apple Music-style).
    private var titlebarCap: some View {
        let chrome = SongbirdThemePalette.palette(
            for: activeFeather,
            colorScheme: colorScheme
        ).playerChrome
        return HStack(spacing: 0) {
            Color.clear
                .frame(width: trafficLightsPadding)
            Spacer(minLength: 0)
            Button {
                withAnimation { sidebarShown.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Hide Sidebar")
            .padding(.trailing, 10)
        }
        .frame(height: titlebarCapHeight)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                SongbirdTopChromeBackground(
                    chrome: chrome,
                    edgeColor: SongbirdTheme.divider(for: colorScheme),
                    treatment: featherTreatment
                )
                WindowDragRegion()
            }
        }
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            collapsibleSectionLabel("Library", isExpanded: $librarySectionExpanded)
            if librarySectionExpanded {
                navRow("All Tracks", systemImage: "music.note", tag: .allTracks)
                navRow("Artists", systemImage: "person.2", tag: .artists)
                navRow("Albums", systemImage: "square.stack", tag: .albums)
                navRow("Genres", systemImage: "tag", tag: .genres)
                navRow("Recently Added", systemImage: "clock", tag: .recentlyAdded)
                navRow("Top Played", systemImage: "flame", tag: .topPlayed)
            }

            collapsibleSectionLabel(
                "Library Health",
                isExpanded: $libraryHealthSectionExpanded
            )
                .padding(.top, 10)
            if libraryHealthSectionExpanded {
                navRow("Overview", systemImage: "heart.text.square", tag: .healthDashboard, supportsSearch: false)
                healthSubsection("Files", isExpanded: $healthFilesExpanded)
                if healthFilesExpanded {
                    healthRow("Missing Files", systemImage: "doc.questionmark", tag: .ghostTracks, count: nil)
                    healthRow("Unavailable Volumes", systemImage: "externaldrive.badge.exclamationmark", tag: .unavailableTracks, count: nil)
                    healthRow("Duplicate Tracks", systemImage: "doc.on.doc", tag: .duplicateTracks, count: nil)
                }
                healthSubsection("Missing Metadata", isExpanded: $healthMetadataExpanded)
                if healthMetadataExpanded {
                    healthRow("Missing Artwork", systemImage: "photo.on.rectangle.angled", tag: .missingArtwork, count: missingArtworkCount)
                    healthRow("Missing Genre", systemImage: "tag.slash", tag: .missingGenre, count: count { $0.genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    healthRow("Missing Artist Names", systemImage: "person.crop.questionmark", tag: .unknownArtist, count: count { $0.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.artist == "Unknown Artist" })
                    healthRow("Missing Album Names", systemImage: "square.stack.questionmark", tag: .unknownAlbum, count: count { $0.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.album == "Unknown Album" })
                    healthRow("Missing Track Number", systemImage: "number", tag: .missingTrackNumber, count: count { $0.trackNumber <= 0 })
                    healthRow("Empty Titles", systemImage: "textformat.abc", tag: .emptyTitles, count: count { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    healthRow("Missing Year", systemImage: "calendar.badge.exclamationmark", tag: .missingYear, count: count { $0.year <= 0 })
                }
                healthSubsection("Consistency", isExpanded: $healthConsistencyExpanded)
                if healthConsistencyExpanded {
                    healthRow("Artists", systemImage: "person.2.badge.gearshape", tag: .inconsistentArtists, count: nil)
                    healthRow("Albums", systemImage: "square.stack.3d.up.badge.gearshape", tag: .inconsistentAlbums, count: nil)
                    healthRow("Genres", systemImage: "tag.badge.gearshape", tag: .inconsistentGenres, count: nil)
                    healthRow("Album Artists", systemImage: "person.2.badge.gearshape", tag: .inconsistentAlbumArtists, count: nil)
                }
                healthSubsection("Cleanup & Quality", isExpanded: $healthCleanupExpanded)
                if healthCleanupExpanded {
                    healthRow("Filled Comments", systemImage: "bubble.left.and.text.bubble.right", tag: .filledComments, count: count { !$0.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    healthRow("Low Bitrate", systemImage: "waveform.badge.minus", tag: .lowBitrate, count: count { $0.bitrate > 0 && $0.bitrate < 128 && !["FLAC", "ALAC", "WAV", "AIFF", "APE"].contains($0.fileKind) })
                }
            }

            playlistSection
                .padding(.top, 10)

            collapsibleSectionLabel("Queue", isExpanded: $queueSectionExpanded)
                .padding(.top, 10)
            if queueSectionExpanded {
                navRow(
                    "Play Queue",
                    systemImage: "text.alignleft",
                    tag: .queue,
                    supportsSearch: false
                )
            }

            if !opticalDiscs.discs.isEmpty {
                sectionLabel("Devices")
                    .padding(.top, 10)
                ForEach(opticalDiscs.discs) { disc in
                    deviceRow(disc)
                }
            }
        }
        .padding(.leading, contentLeadingPad)
        .padding(.trailing, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playlistSection: some View {
        let targetRequest = libraryActions.sidebarPlaylistTargetRequest
        return VStack(alignment: .leading, spacing: 2) {
            SidebarPlaylistSectionHeader(
                targetRequest: targetRequest,
                isExpanded: playlistsSectionExpanded,
                foregroundColor: secondaryColor,
                metrics: sidebarMetrics,
                onToggleExpanded: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        playlistsSectionExpanded.toggle()
                    }
                },
                onNewPlaylist: targetRequest == nil
                    ? beginAddingPlaylist
                    : libraryActions.requestNewPlaylistForSidebarTarget,
                onNewSmartPlaylist: beginAddingSmartPlaylist,
                onCancelTargeting: { libraryActions.cancelSidebarPlaylistTargeting() }
            )

            if playlistsSectionExpanded {
                if let targetRequest {
                    Text(targetRequest.sourceName)
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 8)
                        .help(targetRequest.sourceName)
                }

                PlaylistItems(
                    selectedDestination: $selectedDestination,
                    textColor: textColor,
                    metrics: sidebarMetrics,
                    onEditSmart: { playlist in
                        editingSmartPlaylist = SmartPlaylistEditorTarget(snapshot: playlist)
                        showingSmartEditor = true
                    }
                )

                if targetRequest != nil && libraryActions.manualPlaylists.isEmpty {
                    Text("No playlists yet. Use + to create one.")
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }

                if isAddingPlaylist {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(secondaryColor)
                            .frame(width: 16, alignment: .center)
                        TextField("New Playlist", text: $newPlaylistName)
                            .textFieldStyle(.plain)
                            .focused($newPlaylistFieldFocused)
                            .onSubmit { addPlaylist() }
                            .onKeyPress(.escape) {
                                newPlaylistName = ""
                                isAddingPlaylist = false
                                return .handled
                            }
                        Button {
                            addPlaylist()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Create Playlist")
                        Button {
                            newPlaylistName = ""
                            isAddingPlaylist = false
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Cancel")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .id("newPlaylistEditor")
                }
            }
        }
        .padding(.vertical, targetRequest == nil ? 0 : 4)
        .background {
            if targetRequest != nil {
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedBg)
            }
        }
        .overlay {
            if targetRequest != nil {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(secondaryColor)
            .tracking(0.5)
            .padding(.leading, 24)
            .padding(.trailing, 8)
            .padding(.top, 4)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func collapsibleSectionLabel(
        _ title: String,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 10)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(secondaryColor)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func navRow(
        _ title: String,
        systemImage: String,
        tag: ServicePaneDestination,
        supportsSearch: Bool = true,
        badgeCount: Int? = nil
    ) -> some View {
        SidebarNavigationRow(
            title: title,
            systemImage: systemImage,
            isSelected: selectedDestination == tag,
            supportsSearch: supportsSearch && libraryNavigation.path.isEmpty,
            badgeCount: badgeCount,
            foregroundColor: textColor,
            metrics: sidebarMetrics,
            action: { selectedDestination = tag }
        )
        .id(tag)
    }

    private func healthRow(
        _ title: String,
        systemImage: String,
        tag: ServicePaneDestination,
        count: Int?
    ) -> some View {
        navRow(
            title,
            systemImage: systemImage,
            tag: tag,
            supportsSearch: tag == .unknownAlbum,
            badgeCount: count
        )
        .padding(.leading, 8)
    }

    private func healthSubsection(_ title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(secondaryColor)
        .padding(.leading, 22)
        .padding(.vertical, 3)
    }

    private func count(where predicate: (LibraryTrackSnapshot) -> Bool) -> Int {
        librarySnapshots.snapshot.tracks.filter(predicate).count
    }

    private var missingArtworkCount: Int {
        librarySnapshots.snapshot.albums.filter { $0.artworkReference == nil }.count
    }

    private func deviceRow(_ disc: AudioDisc) -> some View {
        let tag = ServicePaneDestination.audioCD(disc.id)
        let selected = selectedDestination == tag
        let isPlaying = playbackActivity.status == .playing
            && queue.currentTrack?.audioDiscID == disc.id
        let animatesIcon = isPlaying || disc.status == .importing
        return HStack(spacing: 4) {
            Button {
                selectedDestination = tag
            } label: {
                HStack(spacing: 8) {
                    AudioCDIcon(color: textColor, isRotating: animatesIcon)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(disc.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if disc.status != .ready {
                            Text(disc.status.rawValue.capitalized)
                                .font(.system(size: 9))
                                .foregroundColor(secondaryColor)
                        }
                    }
                }
                .foregroundColor(textColor)
                .padding(.leading, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await opticalDiscs.eject(disc) }
            } label: {
                Label("Eject \(disc.title)", systemImage: "eject.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 9))
                    .foregroundColor(secondaryColor)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(disc.status != .ready)
            .help("Eject \(disc.title)")
            .accessibilityInputLabels(["Eject", "Eject \(disc.title)"])

            Spacer(minLength: 0)
        }
        .padding(.trailing, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? selectedBg : Color.clear)
        )
        .id(tag)
    }

    private func addPlaylist() {
        let trimmed = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let request = PlaylistCreationRequest(trackIDs: [], bringMainPlayerForward: false)
        switch libraryActions.createPlaylist(name: trimmed, request: request) {
        case .success(let id):
            selectedDestination = .playlist(id)
            newPlaylistName = ""
            isAddingPlaylist = false
        case .failure:
            break
        }
    }

    private func beginAddingPlaylist() {
        playlistsSectionExpanded = true
        isAddingPlaylist = true
        Task { @MainActor in
            await Task.yield()
            newPlaylistFieldFocused = true
        }
    }

    private func beginAddingSmartPlaylist() {
        editingSmartPlaylist = nil
        showingSmartEditor = true
    }
}

public struct PlaylistItems: View {
    @Binding var selectedDestination: ServicePaneDestination?
    let textColor: Color
    var metrics: ServicePaneMetrics = .standard
    var onEditSmart: (LibraryPlaylistSnapshot) -> Void
    @EnvironmentObject private var librarySnapshots: LibrarySnapshotStore
    @EnvironmentObject private var libraryActions: LibraryItemActionHandler
    @State private var dropTargetID: UUID?
    @State private var smartDropAlert = false
    @State private var renamePlaylistID: UUID?
    @State private var renameText = ""
    @State private var deletePlaylistID: UUID?

    private var playlists: [LibraryPlaylistSnapshot] { librarySnapshots.snapshot.playlists }

    public var body: some View {
        Group {
            ForEach(playlists) { playlist in
                let tag = ServicePaneDestination.playlist(playlist.id)
                let selected = selectedDestination == tag
                let isChoosingDestination = libraryActions.sidebarPlaylistTargetRequest != nil
                SidebarNavigationRow(
                    title: playlist.name,
                    systemImage: isChoosingDestination && playlist.isSmart == false
                        ? "plus.circle"
                        : (playlist.isSmart ? "gearshape.2" : "music.note.list"),
                    isSelected: isChoosingDestination == false && selected,
                    supportsSearch: isChoosingDestination == false,
                    foregroundColor: textColor,
                    metrics: metrics,
                    doubleClickAction: isChoosingDestination ? nil : {
                        selectedDestination = tag
                        libraryActions.requestPlay(playlistID: playlist.id)
                    },
                    action: {
                        if isChoosingDestination {
                            libraryActions.addSidebarTargetToPlaylist(playlistID: playlist.id)
                        } else {
                            selectedDestination = tag
                        }
                    }
                )
                .disabled(isChoosingDestination && playlist.isSmart)
                .opacity(dropTargetID == playlist.id ? 0.7 : 1)
                .help(isChoosingDestination && playlist.isSmart
                    ? "Smart playlists can't be changed"
                    : (isChoosingDestination ? "Add to \(playlist.name)" : playlist.name))
                .onDrop(of: [.songbirdTrackIDs, .plainText], isTargeted: Binding(
                    get: { dropTargetID == playlist.id },
                    set: { targeted in
                        if targeted {
                            dropTargetID = playlist.id
                        } else if dropTargetID == playlist.id {
                            dropTargetID = nil
                        }
                    }
                )) { providers in
                    handleDrop(providers: providers, onto: playlist)
                }
                .contextMenu {
                    if playlist.isSmart {
                        Button("Edit Rules…") {
                            onEditSmart(playlist)
                        }
                    }
                    Button("Rename…") {
                        renameText = playlist.name
                        renamePlaylistID = playlist.id
                    }
                    if playlist.systemKey == nil {
                        Button("Delete", role: .destructive) {
                            deletePlaylistID = playlist.id
                        }
                    }
                    Button("Export M3U…") {
                        libraryActions.exportPlaylist(playlistID: playlist.id)
                    }
                }
                .id(tag)
            }
        }
        .alert("Smart Playlists Are Read-Only", isPresented: $smartDropAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Drag tracks onto a manual playlist, or use Add to Playlist from the track list.")
        }
        .alert("Rename Playlist", isPresented: Binding(
            get: { renamePlaylistID != nil },
            set: { if !$0 { renamePlaylistID = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamePlaylistID = nil }
            Button("Save") {
                if let id = renamePlaylistID,
                   let playlist = playlists.first(where: { $0.id == id }) {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if case .success = libraryActions.renamePlaylist(
                        playlistID: id,
                        expectedName: playlist.name,
                        newName: trimmed
                    ) {
                        renamePlaylistID = nil
                    }
                }
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Delete Playlist?", isPresented: Binding(
            get: { deletePlaylistID != nil },
            set: { if !$0 { deletePlaylistID = nil } }
        )) {
            Button("Cancel", role: .cancel) { deletePlaylistID = nil }
            Button("Delete", role: .destructive) {
                if let id = deletePlaylistID {
                    let shouldSelectAllTracks: Bool = {
                        if case .playlist(let selectedID) = selectedDestination {
                            return selectedID == id
                        }
                        return false
                    }()
                    if case .success = libraryActions.deletePlaylist(playlistID: id) {
                        if shouldSelectAllTracks { selectedDestination = .allTracks }
                        deletePlaylistID = nil
                    }
                }
            }
        } message: {
            let name = playlists.first { $0.id == deletePlaylistID }?.name ?? ""
            Text("“\(name)” will be removed. Library tracks and audio files remain unchanged.")
        }
    }

    private func handleDrop(providers: [NSItemProvider], onto playlist: LibraryPlaylistSnapshot) -> Bool {
        if playlist.isSmart {
            smartDropAlert = true
            return false
        }

        return TrackIDDropDecoder.decode(providers: providers) {
            add(ids: $0, to: playlist.id)
        }
    }

    private func add(ids: [UUID], to playlistID: UUID) {
        guard !ids.isEmpty else { return }
        if case .success(let summary) = libraryActions.addTracks(ids, toPlaylist: playlistID) {
            LibraryStatus.shared.showNotice(
                "Added \(summary.added); \(summary.duplicateSkipped) already present; \(summary.missing) unavailable.",
                severity: .success,
                autoDismissAfter: 4
            )
        }
    }
}
