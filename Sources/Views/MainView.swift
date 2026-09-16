import SwiftUI

/// Full-height sidebar + main content column (player bar top or bottom).
public struct MainView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var libraryNavigation: LibraryNavigationCoordinator
    @EnvironmentObject private var libraryActions: LibraryItemActionHandler
    @EnvironmentObject private var librarySearch: LibrarySearchCoordinator
    @Binding var sidebarShown: Bool
    @Binding var nowPlayingPaneShown: Bool
    @AppStorage("main.sidebarWidth") private var sidebarWidth = Double(
        PlayerWindowMetrics.sidebarDefaultWidth
    )
    @AppStorage("main.nowPlayingPaneWidth") private var nowPlayingPaneWidth = Double(
        PlayerWindowMetrics.nowPlayingPaneDefaultWidth
    )
    @State private var newPlaylistName = ""
    @State private var retainPlaylistPromptAfterFailure = false
    @State private var sidebarWasOpenBeforePush = false
    @AppStorage(PlayerBarPlacement.storageKey) private var playerBarPlacementRaw = PlayerBarPlacement.top.rawValue
    @AppStorage(SongbirdThemeID.storageKey)
    private var themeID = SongbirdThemeID.blueMonday.rawValue

    private var playerBarPlacement: PlayerBarPlacement {
        PlayerBarPlacement(rawValue: playerBarPlacementRaw) ?? .top
    }

    public init(
        sidebarShown: Binding<Bool> = .constant(true),
        nowPlayingPaneShown: Binding<Bool> = .constant(false)
    ) {
        self._sidebarShown = sidebarShown
        self._nowPlayingPaneShown = nowPlayingPaneShown
    }

    /// Shared with ServicePaneView / library titleband (traffic-light row).
    static let titlebarCapHeight: CGFloat = 52
    private let trafficLightsPadding: CGFloat = 70
    /// Enough room for transport controls, the faceplate, and trailing chrome.
    public var body: some View {
        GeometryReader { outer in
            let dividerWidth: CGFloat = sidebarShown ? 8 : 0
            let paneWidths = PlayerWindowLayoutPolicy.paneWidths(
                totalWidth: outer.size.width,
                sidebarShown: sidebarShown,
                rightPaneShown: nowPlayingPaneShown,
                desiredSidebar: CGFloat(sidebarWidth),
                desiredRightPane: CGFloat(nowPlayingPaneWidth)
            )
            let sideWidth = paneWidths.sidebar
            let mainWidth = max(0, outer.size.width - sideWidth - dividerWidth)
            let sidebarLiveMaximum = max(
                PlayerWindowMetrics.sidebarMinimumWidth,
                min(
                    PlayerWindowMetrics.sidebarMaximumWidth,
                    outer.size.width - PlayerWindowMetrics.libraryColumnMinimumWidth
                        - (nowPlayingPaneShown ? paneWidths.rightPane + 16 : 8)
                )
            )
            let rightPaneLiveMaximum = max(
                PlayerWindowMetrics.nowPlayingPaneMinimumWidth,
                min(
                    PlayerWindowMetrics.nowPlayingPaneMaximumWidth,
                    outer.size.width - PlayerWindowMetrics.libraryColumnMinimumWidth
                        - (sidebarShown ? sideWidth + 16 : 8)
                )
            )

            HStack(spacing: 0) {
                if sidebarShown {
                    ServicePaneView(
                        selectedDestination: Binding(
                            get: { libraryNavigation.selectedSidebarDestination },
                            set: { libraryNavigation.selectRoot($0) }
                        ),
                        sidebarShown: $sidebarShown,
                        showsArtworkWell: libraryNavigation.presentsPrimaryArtwork == false
                    )
                    .frame(width: sideWidth, height: outer.size.height)
                    .clipped()

                    ResizableDivider(
                        width: $sidebarWidth,
                        minimum: PlayerWindowMetrics.sidebarMinimumWidth,
                        maximum: sidebarLiveMaximum,
                        direction: .expandsRight
                    )
                        .frame(width: dividerWidth, height: outer.size.height)
                }

                mainContentColumn(
                    resolvedRightPaneWidth: paneWidths.rightPane,
                    rightPaneMaximum: rightPaneLiveMaximum
                )
                    .frame(width: mainWidth, height: outer.size.height, alignment: .topLeading)
                    .clipped()
            }
            .frame(width: outer.size.width, height: outer.size.height, alignment: .topLeading)
            .clipped()
            .background(SongbirdTheme.background(for: colorScheme))
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: playerBarPlacementRaw)
        .onChange(of: libraryNavigation.rootDestination) { _, _ in
            librarySearch.resetForNavigation()
            UsabilityPerformanceSignposts.destinationCommitted()
        }
        .onChange(of: libraryNavigation.path) { oldPath, newPath in
            librarySearch.resetForNavigation()
            UsabilityPerformanceSignposts.destinationCommitted()
            // Spring-loaded sidebar: collapse when pushing into detail, restore when popping back.
            if newPath.isEmpty, sidebarWasOpenBeforePush, !sidebarShown {
                sidebarShown = true
                sidebarWasOpenBeforePush = false
            } else if !newPath.isEmpty, oldPath.isEmpty, sidebarShown {
                sidebarWasOpenBeforePush = true
                sidebarShown = false
            }
        }
        .onChange(of: librarySearch.focusRequestID) { _, _ in
            guard libraryNavigation.path.isEmpty, sidebarShown == false else { return }
            if reduceMotion {
                sidebarShown = true
            } else {
                withAnimation { sidebarShown = true }
            }
        }
        .onChange(of: libraryActions.sidebarPlaylistTargetRequest) { _, request in
            guard request != nil, sidebarShown == false else { return }
            if reduceMotion {
                sidebarShown = true
            } else {
                withAnimation { sidebarShown = true }
            }
        }
        .alert("New Playlist", isPresented: newPlaylistPromptPresented) {
            TextField("Playlist Name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) {
                libraryActions.playlistCreationRequest = nil
                newPlaylistName = ""
            }
            Button("Create") {
                guard let request = libraryActions.playlistCreationRequest else { return }
                switch libraryActions.createPlaylist(name: newPlaylistName, request: request) {
                case .success:
                    newPlaylistName = ""
                case .failure:
                    retainPlaylistPromptAfterFailure = true
                }
            }
            .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Create a playlist from the selected tracks.")
        }
        .sheet(item: $libraryActions.playlistDestinationRequest) { request in
            PlaylistDestinationChooser(request: request)
                .environmentObject(libraryActions)
        }
    }

    private var newPlaylistPromptPresented: Binding<Bool> {
        Binding(
            get: { libraryActions.playlistCreationRequest != nil },
            set: { presented in
                if presented == false {
                    if retainPlaylistPromptAfterFailure {
                        retainPlaylistPromptAfterFailure = false
                        return
                    }
                    libraryActions.playlistCreationRequest = nil
                    newPlaylistName = ""
                }
            }
        )
    }

    @ViewBuilder
    private func mainContentColumn(
        resolvedRightPaneWidth: CGFloat,
        rightPaneMaximum: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            if playerBarPlacement == .top {
                NowPlayingBar(
                    sidebarShown: $sidebarShown,
                    placement: .top,
                    showsSidebarToggle: !sidebarShown,
                    reservesTrafficLightsSpace: !sidebarShown
                )
            } else if !sidebarShown {
                bottomModeTitlebarCap
            }

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if !libraryNavigation.path.isEmpty {
                        HStack {
                            Button("Back", systemImage: "chevron.left") {
                                libraryNavigation.pop()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Back")
                            .keyboardShortcut("[", modifiers: .command)
                            .help("Back (⌘[)")
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(SongbirdTheme.background(for: colorScheme))
                        Divider()
                    }
                    NavigationStack(path: $libraryNavigation.path) {
                        DropReceiver {
                            LibraryContentView(destination: libraryNavigation.rootDestination ?? .allTracks)
                        }
                        .navigationDestination(for: LibraryRoute.self) { route in
                            routeDestination(route)
                                .navigationBarBackButtonHidden(true)
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                if nowPlayingPaneShown {
                    let dividerWidth: CGFloat = 8
                    let paneClamped = resolvedRightPaneWidth
                    ResizableDivider(
                        width: $nowPlayingPaneWidth,
                        minimum: PlayerWindowMetrics.nowPlayingPaneMinimumWidth,
                        maximum: rightPaneMaximum,
                        direction: .expandsLeft
                    )
                        .frame(width: dividerWidth)

                    NowPlayingPaneView()
                        .frame(width: paneClamped)
                        .clipped()
                }
            }

            LibraryStatusBar()

            if playerBarPlacement == .bottom {
                NowPlayingBar(
                    sidebarShown: $sidebarShown,
                    placement: .bottom,
                    showsSidebarToggle: false,
                    reservesTrafficLightsSpace: false
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            UsabilityPerformanceSignposts.installInputMonitorIfNeeded()
            sidebarWidth = min(
                max(sidebarWidth, Double(PlayerWindowMetrics.sidebarMinimumWidth)),
                Double(PlayerWindowMetrics.sidebarMaximumWidth)
            )
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: LibraryRoute) -> some View {
        switch route {
        case .album(let albumID):
            AlbumDetailView(albumID: albumID)
        case .artist(let name):
            TrackTableView(title: name, collection: .artist(name), showsFilters: false)
        case .genre(let name):
            TrackTableView(title: name, collection: .genre(name), showsFilters: false)
        case .health(let category):
            LibraryHealthRouteView(category: category)
        }
    }

    /// Compact titleband for bottom-player + hidden-sidebar: room for traffic
    /// lights and a sidebar restore control (aligned with ServicePaneView).
    private var bottomModeTitlebarCap: some View {
        let activeFeather = SongbirdThemeID.resolved(rawValue: themeID)
        let chrome = SongbirdThemePalette.palette(
            for: activeFeather,
            colorScheme: colorScheme
        ).playerChrome
        return HStack(spacing: 0) {
            Color.clear
                .frame(width: trafficLightsPadding)
            Spacer(minLength: 0)
            Button {
                withAnimation { sidebarShown = true }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SongbirdTheme.text(for: colorScheme))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Show Sidebar")
            .padding(.trailing, 8)
        }
        .frame(height: Self.titlebarCapHeight)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                SongbirdTopChromeBackground(
                    chrome: chrome,
                    edgeColor: SongbirdTheme.divider(for: colorScheme),
                    treatment: .treatment(for: activeFeather)
                )
                WindowDragRegion()
            }
        }
    }

}

private struct LibraryHealthRouteView: View {
    let category: LibraryHealthCategory

    @ViewBuilder
    var body: some View {
        switch category {
        case .missingFiles, .unavailableVolumes:
            LibraryHealthDetailView(category: category)
        case .duplicateTracks: DuplicateTracksView()
        case .missingArtwork, .missingGenre, .missingArtistNames,
             .missingTrackNumber, .emptyTitles, .missingYear,
             .inconsistentArtists, .inconsistentAlbums, .inconsistentGenres,
             .inconsistentAlbumArtists, .filledComments, .lowBitrate:
            LibraryHealthDetailView(category: category)
        case .missingAlbumNames: MissingAlbumView()
        }
    }
}

struct ResizableDivider: View {
    enum Direction { case expandsRight, expandsLeft }

    @Binding var width: Double
    let minimum: CGFloat
    let maximum: CGFloat
    let direction: Direction
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var dragStartWidth: Double?
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(
                    isHovering || isFocused
                        ? Color.accentColor.opacity(0.7)
                        : SongbirdTheme.divider(for: colorScheme)
                )
                .frame(width: 1)
                .allowsHitTesting(false)

            // Restoring a pane can leave no resizing room, or less than one
            // keyboard step. SwiftUI traps if a stepped Slider has zero steps.
            if maximum > minimum {
                Slider(
                    value: $width,
                    in: Double(minimum)...Double(maximum),
                    step: min(10, Double(maximum - minimum))
                )
                .labelsHidden()
                .opacity(0)
                .focusEffectDisabled()
                .focused($isFocused)
                .accessibilityLabel("Sidebar width")
                .accessibilityValue("\(Int(width)) points")
            }
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = width
                    }
                    let delta = Double(value.translation.width) * (direction == .expandsRight ? 1 : -1)
                    let newWidth = (dragStartWidth ?? width) + delta
                    width = min(
                        max(newWidth, Double(minimum)),
                        Double(maximum)
                    )
                }
                .onEnded { _ in
                    dragStartWidth = nil
                }
        )
    }
}
