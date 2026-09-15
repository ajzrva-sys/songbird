import SwiftUI

public struct NowPlayingBar: View {
    @ObservedObject private var discogsClock = DiscogsPresentationClock.shared
    @EnvironmentObject private var playbackSession: PlaybackSession
    @EnvironmentObject private var playbackPresentation: PlaybackPresentationState
    @EnvironmentObject private var librarySnapshots: LibrarySnapshotStore
    @EnvironmentObject private var albumProjectionStore: LibraryAlbumProjectionStore
    @EnvironmentObject private var libraryActions: LibraryItemActionHandler
    @EnvironmentObject private var libraryNavigation: LibraryNavigationCoordinator
    @EnvironmentObject private var librarySelection: LibrarySelectionState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var sidebarShown: Bool
    var placement: PlayerBarPlacement
    /// When the sidebar is hidden, offer a toggle in the player bar.
    var showsSidebarToggle: Bool
    /// Leading clearance for traffic lights when the bar spans under the titlebar (sidebar hidden).
    var reservesTrafficLightsSpace: Bool

    @State private var timeMode: TimeDisplayMode = .elapsed
    @State private var isEditingLayout = false
    @State private var selectedZone: LayoutStudioZone = .faceplate
    @AppStorage(SongbirdThemeID.storageKey)
    private var themeID = SongbirdThemeID.blueMonday.rawValue

    @AppStorage(NowPlayingLayoutSettings.faceplateWidthKey)
    private var faceplateWidth = NowPlayingLayoutSettings.defaultFaceplateWidth
    @AppStorage(NowPlayingLayoutSettings.faceplateHeightKey)
    private var faceplateHeight = NowPlayingLayoutSettings.defaultFaceplateHeight
    @AppStorage(NowPlayingLayoutSettings.leadingGapKey)
    private var leadingGap = NowPlayingLayoutSettings.defaultLeadingGap
    @AppStorage(NowPlayingLayoutSettings.trailingGapKey)
    private var trailingGap = NowPlayingLayoutSettings.defaultTrailingGap
    @AppStorage(NowPlayingLayoutSettings.barPaddingKey)
    private var barPadding = NowPlayingLayoutSettings.defaultBarPadding
    @AppStorage(NowPlayingLayoutSettings.buttonSpacingKey)
    private var buttonSpacing = NowPlayingLayoutSettings.defaultButtonSpacing
    @AppStorage(NowPlayingLayoutSettings.controlsSpacingKey)
    private var controlsSpacing = NowPlayingLayoutSettings.defaultControlsSpacing
    @AppStorage(PlayerToolbarLayout.storageKey)
    private var toolbarItemsRaw = PlayerToolbarLayout.encode(PlayerToolbarLayout.defaults)

    private var toolbarItems: [PlayerToolbarItem] {
        PlayerToolbarLayout.decode(toolbarItemsRaw)
    }

    private var toolbarItemsBinding: Binding<[PlayerToolbarItem]> {
        Binding(
            get: { toolbarItems },
            set: { toolbarItemsRaw = PlayerToolbarLayout.encode($0) }
        )
    }

    private var isDark: Bool { colorScheme == .dark }
    private var activeFeather: SongbirdThemeID {
        SongbirdThemeID.resolved(rawValue: themeID)
    }
    private var featherTreatment: SongbirdFeatherTreatment {
        .treatment(for: activeFeather)
    }
    private var faceplateStyle: FaceplateStyle {
        FaceplateStyle.resolve(
            treatment: featherTreatment,
            palette: SongbirdThemePalette.palette(for: activeFeather, colorScheme: colorScheme),
            isDark: isDark
        )
    }
    private var playerControlShape: AnyShape {
        if featherTreatment.usesSquareControls {
            return AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        return AnyShape(Circle())
    }
    private var faceplateCornerRadius: CGFloat {
        faceplateStyle.cornerRadius
    }
    private var usesBrightIdleArtwork: Bool {
        activeFeather == .silverwing
    }
    private var iconColor: Color { SongbirdTheme.text(for: colorScheme) }
    private var secondaryColor: Color { SongbirdTheme.secondaryText(for: colorScheme) }
    private var playbackEngine: PlaybackEngine { playbackSession.engine }
    private var queue: PlaybackQueue { playbackSession.queue }

    // Drag gesture bookkeeping
    @State private var dragStartWidth: Double = 0
    @State private var dragStartHeight: Double = 0
    @State private var dragStartLeadingGap: Double = 0
    @State private var dragStartTrailingGap: Double = 0
    @State private var dragStartButtonSpacing: Double = 0
    @State private var dragStartControlsSpacing: Double = 0
    @State private var dragStartPadding: Double = 0
    @State private var widthDragArmed = false
    @State private var heightDragArmed = false
    @State private var leadingGapDragArmed = false
    @State private var trailingGapDragArmed = false
    @State private var buttonDragArmed = false
    @State private var controlsDragArmed = false
    @State private var paddingDragArmed = false
    @State private var previewFaceplateWidth: Double?
    @State private var previewFaceplateHeight: Double?
    @State private var previewLeadingGap: Double?
    @State private var previewTrailingGap: Double?
    @State private var previewButtonSpacing: Double?
    @State private var previewControlsSpacing: Double?
    @State private var previewBarPadding: Double?
    @State private var showingLyrics = false
    @State private var availableBarWidth: CGFloat = 820
    @State private var measuredControlsWidth: CGFloat = 308

    private let trafficLightsPadding: CGFloat = 70
    /// Non-customizable guard that keeps the rounded faceplate edge on-screen.
    private let minimumRightEdgeClearance: CGFloat = 8

    private var renderedFaceplateWidth: Double { previewFaceplateWidth ?? faceplateWidth }
    private var renderedFaceplateHeight: Double { previewFaceplateHeight ?? faceplateHeight }
    private var renderedLeadingGap: Double { previewLeadingGap ?? leadingGap }
    private var renderedTrailingGap: Double { previewTrailingGap ?? trailingGap }
    private var renderedButtonSpacing: Double { previewButtonSpacing ?? buttonSpacing }
    private var renderedControlsSpacing: Double { previewControlsSpacing ?? controlsSpacing }
    private var renderedBarPadding: Double { previewBarPadding ?? barPadding }

    private var barHeight: CGFloat {
        CGFloat(renderedFaceplateHeight) + CGFloat(renderedBarPadding) * 2
    }

    private var totalGapBudget: Double {
        // `availableBarWidth` is measured inside the bar's outer padding, so
        // subtracting padding/traffic clearance here would reserve it twice.
        let fixedWidth = measuredControlsWidth + CGFloat(renderedFaceplateWidth)
        return max(0, Double(availableBarWidth - fixedWidth))
    }

    private var leadingGapRange: ClosedRange<Double> {
        0...totalGapBudget
    }

    private var trailingGapRange: ClosedRange<Double> {
        0...totalGapBudget
    }

    private func renderedGaps(for budget: Double) -> (leading: CGFloat, trailing: CGFloat) {
        let requested = max(0, renderedLeadingGap) + max(0, renderedTrailingGap)
        guard requested > budget, requested > 0 else {
            return (CGFloat(max(0, renderedLeadingGap)), CGFloat(max(0, renderedTrailingGap)))
        }
        let scale = budget / requested
        return (
            CGFloat(max(0, renderedLeadingGap) * scale),
            CGFloat(max(0, renderedTrailingGap) * scale)
        )
    }
    public init(
        sidebarShown: Binding<Bool> = .constant(true),
        placement: PlayerBarPlacement = .top,
        showsSidebarToggle: Bool = false,
        reservesTrafficLightsSpace: Bool = false
    ) {
        self._sidebarShown = sidebarShown
        self.placement = placement
        self.showsSidebarToggle = showsSidebarToggle
        self.reservesTrafficLightsSpace = reservesTrafficLightsSpace
    }

    public var body: some View {
        VStack(spacing: 0) {
            if placement == .bottom, isEditingLayout {
                layoutStudio
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            chromeBar
                .contextMenu {
                    if isEditingLayout {
                        Button("Done Editing") { exitLayoutEditing() }
                        Button("Reset Layout") { resetLayout() }
                    } else {
                        Button("Edit Layout") { enterLayoutEditing() }
                        if playbackPresentation.currentTrack != nil {
                            Button("Show Lyrics") { showingLyrics = true }
                        }
                        Divider()
                        Button("Reset Layout") { resetLayout() }
                    }
                }
                // Avoid system focus ring — it draws as bright blue rules across the chrome.
                .focusable(isEditingLayout)
                .focusEffectDisabled()
                .onKeyPress(.escape) {
                    if isEditingLayout {
                        exitLayoutEditing()
                        return .handled
                    }
                    return .ignored
                }

            if placement == .top, isEditingLayout {
                layoutStudio
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isEditingLayout)
        .onReceive(NotificationCenter.default.publisher(for: .showLyrics)) { _ in
            if playbackPresentation.currentTrack != nil {
                showingLyrics = true
            }
        }
        .sheet(isPresented: $showingLyrics) {
            if let track = playbackPresentation.currentTrack {
                LyricsPaneView(track: track)
            }
        }
        .onAppear(perform: migrateIndependentGapsIfNeeded)
        .onChange(of: leadingGap) { oldValue, newValue in
            guard newValue != oldValue else { return }
            trailingGap = min(trailingGap, max(0, totalGapBudget - newValue))
        }
        .onChange(of: trailingGap) { oldValue, newValue in
            guard newValue != oldValue else { return }
            leadingGap = min(leadingGap, max(0, totalGapBudget - newValue))
        }
    }

    private var layoutStudio: some View {
        NowPlayingLayoutStudio(
            itemOrder: toolbarItemsBinding,
            selectedZone: $selectedZone,
            faceplateWidth: $faceplateWidth,
            faceplateHeight: $faceplateHeight,
            leadingGap: $leadingGap,
            trailingGap: $trailingGap,
            leadingGapRange: leadingGapRange,
            trailingGapRange: trailingGapRange,
            barPadding: $barPadding,
            buttonSpacing: $buttonSpacing,
            controlsSpacing: $controlsSpacing,
            onDone: { exitLayoutEditing() },
            onReset: { resetLayout() }
        )
    }

    // MARK: - Chrome bar

    private var chromeBar: some View {
        let chrome = SongbirdThemePalette.palette(
            for: activeFeather, colorScheme: colorScheme
        ).playerChrome
        return GeometryReader { geometry in
            chromeBarContent(availableWidth: geometry.size.width)
        }
        .frame(height: max(barHeight, 52))
        .accessibilityIdentifier("player.mainBar")
        .background {
            ZStack {
                SongbirdTopChromeBackground(
                    chrome: chrome,
                    edgeColor: SongbirdTheme.divider(for: colorScheme),
                    treatment: featherTreatment
                )
                WindowDragRegion(isEnabled: !isEditingLayout)
            }
        }
        .overlay(alignment: .trailing) {
            if isEditingLayout {
                barPaddingHandle
            }
        }
    }

    private func chromeBarContent(availableWidth: CGFloat) -> some View {
        let leadingInset = CGFloat(renderedBarPadding)
            + (reservesTrafficLightsSpace ? trafficLightsPadding : 0)
        let trailingInset = CGFloat(renderedBarPadding) + minimumRightEdgeClearance
        let innerWidth = max(0, availableWidth - leadingInset - trailingInset)
        let usesCompactLayout = PlayerSliderBehavior.usesCompactPlayer(
            width: Double(availableWidth),
            isEditingLayout: isEditingLayout
        )
        return Group {
            if usesCompactLayout {
                compactChromeBarContent
            } else {
                fullChromeBarContent
            }
        }
        .frame(width: innerWidth, alignment: .trailing)
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .frame(width: availableWidth, alignment: .leading)
        .onAppear {
            availableBarWidth = innerWidth
            clampGapsToAvailableWidth()
        }
        .onChange(of: innerWidth) { _, width in
            availableBarWidth = width
            clampGapsToAvailableWidth()
        }
    }

    private var fullChromeBarContent: some View {
        HStack(spacing: 0) {
            if showsSidebarToggle {
                sidebarToggle
                Color.clear.frame(width: CGFloat(renderedControlsSpacing))
            }

            ForEach(Array(toolbarItems.enumerated()), id: \.element) { index, item in
                layoutEditableToolbarItem(item)
                if index < toolbarItems.count - 1 {
                    Color.clear.frame(
                        width: toolbarSpacing(
                            after: item,
                            before: toolbarItems[index + 1]
                        )
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func layoutEditableToolbarItem(_ item: PlayerToolbarItem) -> some View {
        if isEditingLayout {
            playerToolbarItem(item)
                .overlay {
                    if item != .flexibleSpace, item != .faceplate {
                        LayoutZoneOutline(isSelected: false)
                    }
                }
                .contentShape(Rectangle())
                .draggable(item.rawValue) {
                    Label(item.title, systemImage: item.systemImage)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .dropDestination(for: String.self) { values, _ in
                    guard let rawValue = values.first,
                          let draggedItem = PlayerToolbarItem(rawValue: rawValue) else {
                        return false
                    }
                    moveToolbarItem(draggedItem, before: item)
                    return true
                }
                .accessibilityHint("Drag to reorder this item in the player bar.")
                .accessibilityAction(named: "Move Left") {
                    moveToolbarItem(item, offset: -1)
                }
                .accessibilityAction(named: "Move Right") {
                    moveToolbarItem(item, offset: 1)
                }
        } else {
            playerToolbarItem(item)
        }
    }

    private var compactChromeBarContent: some View {
        HStack(spacing: 8) {
            if showsSidebarToggle { sidebarToggle }
            flatWellButton("backward.end.fill", size: 26, iconSize: 10) {
                playbackEngine.playPrevious()
            }
            flatWellButton(
                playbackPresentation.status == .playing ? "pause.fill" : "play.fill",
                size: 38,
                iconSize: 14,
                glyphOffset: playbackPresentation.status == .playing ? 0 : 1
            ) {
                performPrimaryPlayPause()
            }
            flatWellButton("forward.end.fill", size: 26, iconSize: 10) {
                playbackEngine.playNext()
            }
            faceplate
                .frame(minWidth: 180, maxWidth: .infinity)
                .frame(height: min(renderedFaceplateHeight, 44))
            Menu {
                Button("Volume Up") {
                    playbackEngine.setVolume(playbackEngine.volume + 0.05)
                }
                Button("Volume Down") {
                    playbackEngine.setVolume(playbackEngine.volume - 0.05)
                }
                Divider()
                Toggle("Shuffle", isOn: Binding(
                    get: { queue.shuffleEnabled },
                    set: { queue.shuffleEnabled = $0 }
                ))
                Picker("Repeat", selection: Binding(
                    get: { queue.repeatMode },
                    set: { queue.repeatMode = $0 }
                )) {
                    Text("Off").tag(PlaybackQueue.RepeatMode.off)
                    Text("All").tag(PlaybackQueue.RepeatMode.all)
                    Text("One").tag(PlaybackQueue.RepeatMode.one)
                }
            } label: {
                Label("More Playback Controls", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 16, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
    }

    private var sidebarToggle: some View {
        Button {
            withAnimation { sidebarShown.toggle() }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help("Show Sidebar")
        .disabled(isEditingLayout)
    }

    @ViewBuilder
    private func playerToolbarItem(_ item: PlayerToolbarItem) -> some View {
        switch item {
        case .previous:
            flatWellButton("backward.end.fill", size: 26, iconSize: 10) {
                playbackEngine.playPrevious()
            }
            .disabled(isEditingLayout)
        case .playPause:
            flatWellButton(
                playbackPresentation.status == .playing ? "pause.fill" : "play.fill",
                size: 38,
                iconSize: 14,
                glyphOffset: playbackPresentation.status == .playing ? 0 : 1
            ) {
                performPrimaryPlayPause()
            }
            .disabled(isEditingLayout)
        case .next:
            flatWellButton("forward.end.fill", size: 26, iconSize: 10) {
                playbackEngine.playNext()
            }
            .disabled(isEditingLayout)
        case .volume:
            volumeControls
        case .shuffle:
            PlaybackQueueReader(queue: queue) { queue in
                shuffleButton(queue: queue)
            }
        case .repeatMode:
            PlaybackQueueReader(queue: queue) { queue in
                repeatButton(queue: queue)
            }
        case .flexibleSpace:
            Spacer(minLength: 0)
                .frame(maxWidth: .infinity)
        case .faceplate:
            editableFaceplate
                .fixedSize()
        }
    }

    private func toolbarSpacing(
        after item: PlayerToolbarItem,
        before next: PlayerToolbarItem
    ) -> CGFloat {
        let transport: Set<PlayerToolbarItem> = [.previous, .playPause, .next]
        if transport.contains(item), transport.contains(next) {
            return CGFloat(renderedButtonSpacing)
        }
        if item == .flexibleSpace || next == .flexibleSpace {
            return 0
        }
        return CGFloat(renderedControlsSpacing)
    }

    private func moveToolbarItem(
        _ draggedItem: PlayerToolbarItem,
        before targetItem: PlayerToolbarItem
    ) {
        guard draggedItem != targetItem else { return }
        var items = toolbarItems
        items.removeAll { $0 == draggedItem }
        guard let targetIndex = items.firstIndex(of: targetItem) else { return }
        items.insert(draggedItem, at: targetIndex)
        toolbarItemsRaw = PlayerToolbarLayout.encode(items)
        selectedZone = draggedItem == .faceplate ? .faceplate : selectedZone
    }

    private func moveToolbarItem(_ item: PlayerToolbarItem, offset: Int) {
        var items = toolbarItems
        guard let sourceIndex = items.firstIndex(of: item) else { return }
        let destinationIndex = min(max(sourceIndex + offset, 0), items.count - 1)
        guard sourceIndex != destinationIndex else { return }
        items.remove(at: sourceIndex)
        items.insert(item, at: destinationIndex)
        toolbarItemsRaw = PlayerToolbarLayout.encode(items)
        selectedZone = item == .faceplate ? .faceplate : selectedZone
    }

    private var editableFaceplate: some View {
        faceplate
            .frame(width: renderedFaceplateWidth, height: renderedFaceplateHeight)
            .overlay {
                if isEditingLayout {
                    LayoutZoneOutline(isSelected: selectedZone == .faceplate)
                    faceplateResizeHandles
                }
            }
            .onTapGesture {
                if isEditingLayout { selectedZone = .faceplate }
            }
    }

    // MARK: - Edit handles

    private func gapHandle(isLeading: Bool) -> some View {
        let zone: LayoutStudioZone = isLeading ? .leadingGap : .trailingGap
        let currentValue = isLeading ? renderedLeadingGap : renderedTrailingGap

        return LayoutDragHandle(
            axis: .horizontal,
            label: selectedZone == zone ? "\(Int(currentValue)) pt" : nil,
            isSelected: selectedZone == zone
        )
        .offset(x: isLeading ? -10 : 10)
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    selectedZone = zone
                    if isLeading {
                        if !leadingGapDragArmed {
                            leadingGapDragArmed = true
                            dragStartLeadingGap = leadingGap
                        }
                        previewLeadingGap = NowPlayingLayoutSettings.clamp(
                            dragStartLeadingGap - Double(value.translation.width),
                            to: leadingGapRange
                        )
                    } else {
                        if !trailingGapDragArmed {
                            trailingGapDragArmed = true
                            dragStartTrailingGap = trailingGap
                        }
                        previewTrailingGap = NowPlayingLayoutSettings.clamp(
                            dragStartTrailingGap + Double(value.translation.width),
                            to: trailingGapRange
                        )
                    }
                }
                .onEnded { _ in
                    if isLeading, let previewLeadingGap {
                        leadingGap = previewLeadingGap
                    } else if !isLeading, let previewTrailingGap {
                        trailingGap = previewTrailingGap
                    }
                    self.previewLeadingGap = nil
                    self.previewTrailingGap = nil
                    leadingGapDragArmed = false
                    trailingGapDragArmed = false
                    dragStartLeadingGap = leadingGap
                    dragStartTrailingGap = trailingGap
                }
        )
        .onTapGesture { selectedZone = zone }
    }

    private var faceplateResizeHandles: some View {
        ZStack {
            HStack {
                Spacer()
                LayoutDragHandle(
                    axis: .horizontal,
                    label: selectedZone == .faceplate ? "\(Int(renderedFaceplateWidth))×\(Int(renderedFaceplateHeight))" : nil,
                    isSelected: selectedZone == .faceplate
                )
                .offset(x: 6)
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            if !widthDragArmed {
                                widthDragArmed = true
                                selectedZone = .faceplate
                                dragStartWidth = faceplateWidth
                            }
                            previewFaceplateWidth = NowPlayingLayoutSettings.clamp(
                                dragStartWidth + Double(value.translation.width) * 2,
                                to: NowPlayingLayoutSettings.faceplateWidthRange
                            )
                        }
                        .onEnded { _ in
                            if let previewFaceplateWidth {
                                faceplateWidth = previewFaceplateWidth
                            }
                            self.previewFaceplateWidth = nil
                            widthDragArmed = false
                            dragStartWidth = faceplateWidth
                        }
                )
            }

            VStack {
                Spacer()
                LayoutDragHandle(
                    axis: .vertical,
                    label: nil,
                    isSelected: selectedZone == .faceplate
                )
                .offset(y: 6)
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            if !heightDragArmed {
                                heightDragArmed = true
                                selectedZone = .faceplate
                                dragStartHeight = faceplateHeight
                            }
                            previewFaceplateHeight = NowPlayingLayoutSettings.clamp(
                                dragStartHeight + Double(value.translation.height) * 2,
                                to: NowPlayingLayoutSettings.faceplateHeightRange
                            )
                        }
                        .onEnded { _ in
                            if let previewFaceplateHeight {
                                faceplateHeight = previewFaceplateHeight
                            }
                            self.previewFaceplateHeight = nil
                            heightDragArmed = false
                            dragStartHeight = faceplateHeight
                        }
                )
            }
        }
    }

    private var controlsSpacingHandle: some View {
        LayoutDragHandle(
            axis: .horizontal,
            label: selectedZone == .controlsSpacing ? "\(Int(renderedControlsSpacing)) pt" : nil,
            isSelected: selectedZone == .controlsSpacing
        )
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if !controlsDragArmed {
                        controlsDragArmed = true
                        selectedZone = .controlsSpacing
                        dragStartControlsSpacing = controlsSpacing
                    }
                    previewControlsSpacing = NowPlayingLayoutSettings.clamp(
                        dragStartControlsSpacing + Double(value.translation.width),
                        to: NowPlayingLayoutSettings.controlsSpacingRange
                    )
                }
                .onEnded { _ in
                    if let previewControlsSpacing {
                        controlsSpacing = previewControlsSpacing
                    }
                    self.previewControlsSpacing = nil
                    controlsDragArmed = false
                    dragStartControlsSpacing = controlsSpacing
                }
        )
        .onTapGesture { selectedZone = .controlsSpacing }
    }

    private var buttonSpacingHandle: some View {
        LayoutDragHandle(
            axis: .horizontal,
            label: selectedZone == .buttonSpacing ? "\(Int(renderedButtonSpacing)) pt" : nil,
            isSelected: selectedZone == .buttonSpacing
        )
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if !buttonDragArmed {
                        buttonDragArmed = true
                        selectedZone = .buttonSpacing
                        dragStartButtonSpacing = buttonSpacing
                    }
                    previewButtonSpacing = NowPlayingLayoutSettings.clamp(
                        dragStartButtonSpacing + Double(value.translation.width) * 0.4,
                        to: NowPlayingLayoutSettings.buttonSpacingRange
                    )
                }
                .onEnded { _ in
                    if let previewButtonSpacing {
                        buttonSpacing = previewButtonSpacing
                    }
                    self.previewButtonSpacing = nil
                    buttonDragArmed = false
                    dragStartButtonSpacing = buttonSpacing
                }
        )
        .onTapGesture { selectedZone = .buttonSpacing }
    }

    private var barPaddingHandle: some View {
        LayoutDragHandle(
            axis: .horizontal,
            label: selectedZone == .barPadding ? "\(Int(renderedBarPadding)) pt" : nil,
            isSelected: selectedZone == .barPadding
        )
        .padding(.trailing, 4)
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if !paddingDragArmed {
                        paddingDragArmed = true
                        selectedZone = .barPadding
                        dragStartPadding = barPadding
                    }
                    previewBarPadding = NowPlayingLayoutSettings.clamp(
                        dragStartPadding + Double(value.translation.width),
                        to: NowPlayingLayoutSettings.barPaddingRange
                    )
                }
                .onEnded { _ in
                    if let previewBarPadding {
                        barPadding = previewBarPadding
                    }
                    self.previewBarPadding = nil
                    paddingDragArmed = false
                    dragStartPadding = barPadding
                }
        )
        .onTapGesture { selectedZone = .barPadding }
    }

    private func enterLayoutEditing() {
        dragStartWidth = faceplateWidth
        dragStartHeight = faceplateHeight
        dragStartLeadingGap = leadingGap
        dragStartTrailingGap = trailingGap
        dragStartButtonSpacing = buttonSpacing
        dragStartControlsSpacing = controlsSpacing
        dragStartPadding = barPadding
        withAnimation { isEditingLayout = true }
    }

    private func exitLayoutEditing() {
        withAnimation { isEditingLayout = false }
    }

    private func resetLayout() {
        faceplateWidth = NowPlayingLayoutSettings.defaultFaceplateWidth
        faceplateHeight = NowPlayingLayoutSettings.defaultFaceplateHeight
        leadingGap = NowPlayingLayoutSettings.defaultLeadingGap
        trailingGap = NowPlayingLayoutSettings.defaultTrailingGap
        barPadding = NowPlayingLayoutSettings.defaultBarPadding
        buttonSpacing = NowPlayingLayoutSettings.defaultButtonSpacing
        controlsSpacing = NowPlayingLayoutSettings.defaultControlsSpacing
        toolbarItemsRaw = PlayerToolbarLayout.encode(PlayerToolbarLayout.defaults)
        dragStartWidth = faceplateWidth
        dragStartHeight = faceplateHeight
        dragStartLeadingGap = leadingGap
        dragStartTrailingGap = trailingGap
        dragStartButtonSpacing = buttonSpacing
        dragStartControlsSpacing = controlsSpacing
        dragStartPadding = barPadding
    }

    private func migrateIndependentGapsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: NowPlayingLayoutSettings.gapMigrationKey) else {
            return
        }
        let oldBase = defaults.object(forKey: NowPlayingLayoutSettings.sectionSpacingKey) as? Double
            ?? NowPlayingLayoutSettings.defaultLeadingGap
        let oldExtra = defaults.object(forKey: NowPlayingLayoutSettings.sideSpacerKey) as? Double
            ?? 0
        let oldTotal = max(0, oldBase + oldExtra)
        leadingGap = NowPlayingLayoutSettings.clamp(
            oldTotal,
            to: NowPlayingLayoutSettings.gapRange
        )
        trailingGap = NowPlayingLayoutSettings.clamp(
            oldTotal * 0.5,
            to: NowPlayingLayoutSettings.gapRange
        )
        defaults.set(true, forKey: NowPlayingLayoutSettings.gapMigrationKey)
        clampGapsToAvailableWidth()
    }

    private func clampGapsToAvailableWidth() {
        let budget = totalGapBudget
        guard leadingGap + trailingGap > budget else { return }

        if selectedZone == .trailingGap {
            leadingGap = min(leadingGap, max(0, budget - trailingGap))
            trailingGap = min(trailingGap, budget)
        } else {
            trailingGap = min(trailingGap, max(0, budget - leadingGap))
            leadingGap = min(leadingGap, budget)
        }
    }
    // MARK: - Transport

    private var transportControls: some View {
        // Classic Songbird proportions: play well ≈ 1.45× side wells, nearly touching.
        let sideSize: CGFloat = 26
        let playSize: CGFloat = 38
        return HStack(spacing: renderedButtonSpacing) {
            flatWellButton("backward.end.fill", size: sideSize, iconSize: 10) {
                playbackEngine.playPrevious()
            }
            .disabled(isEditingLayout)

            flatWellButton(
                playbackPresentation.status == .playing ? "pause.fill" : "play.fill",
                size: playSize,
                iconSize: 14,
                glyphOffset: playbackPresentation.status == .playing ? 0 : 1
            ) {
                performPrimaryPlayPause()
            }
            .disabled(isEditingLayout)

            if isEditingLayout {
                buttonSpacingHandle
            }

            flatWellButton("forward.end.fill", size: sideSize, iconSize: 10) {
                playbackEngine.playNext()
            }
            .disabled(isEditingLayout)
        }
        .overlay {
            if isEditingLayout && selectedZone == .buttonSpacing {
                LayoutZoneOutline(isSelected: true)
            }
        }
        .onTapGesture {
            if isEditingLayout { selectedZone = .buttonSpacing }
        }
    }

    /// Flat icon in an inset well (carved into the bar — no raised disc).
    private func flatWellButton(
        _ systemName: String,
        size: CGFloat,
        iconSize: CGFloat,
        glyphOffset: CGFloat = 0,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let title = controlTitle(for: systemName)
        let usesSourceWell = featherTreatment.usesBlueControlRims
        let usesGoldWell = featherTreatment.usesGoldControlRims
        let usesVioletWell = featherTreatment.usesPurpleControlRims
        let usesDarkWell = isDark
            || featherTreatment.usesDarkControlWells
            || featherTreatment.usesSquareControls
            || usesVioletWell
        let wellColors: [Color] = if featherTreatment.usesSquareControls {
            [
                Color(red: 0.075, green: 0.085, blue: 0.088),
                Color(red: 0.13, green: 0.145, blue: 0.15),
            ]
        } else if featherTreatment.usesDarkControlWells {
            [
                Color(red: 0.20, green: 0.055, blue: 0.12),
                Color(red: 0.38, green: 0.13, blue: 0.23),
            ]
        } else if usesVioletWell {
            [
                Color(red: 0.14, green: 0.08, blue: 0.22),
                Color(red: 0.26, green: 0.16, blue: 0.38),
            ]
        } else if usesGoldWell {
            [Color(red: 0.92, green: 0.86, blue: 0.70), Color(red: 0.78, green: 0.68, blue: 0.46)]
        } else if usesSourceWell {
            [Color(white: 0.94), Color(white: 0.66)]
        } else if isDark {
            [Color(white: 0.12), Color(white: 0.20)]
        } else {
            [Color(white: 0.78), Color(white: 0.88)]
        }
        let wellGlyph = if featherTreatment.usesSquareControls {
            SongbirdThemePalette.terminalAccent
        } else if featherTreatment.usesDarkControlWells {
            Color(red: 0.96, green: 0.80, blue: 0.87)
        } else if usesVioletWell {
            Color(red: 0.88, green: 0.78, blue: 0.96)
        } else if usesGoldWell {
            Color(red: 0.22, green: 0.18, blue: 0.10)
        } else if usesSourceWell {
            Color(red: 0.13, green: 0.15, blue: 0.17)
        } else {
            iconColor
        }
        return Button(action: action) {
            ZStack {
                // Floor of the well — slightly inset from the bar surface
                playerControlShape
                    .fill(
                        LinearGradient(
                            colors: wellColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Rim: dark along top (lip shadow), light along bottom (catch light)
                playerControlShape
                    .stroke(
                        AngularGradient(
                            colors: usesSourceWell
                                ? [
                                    SongbirdThemePalette.blueMondayAccent,
                                    Color(red: 0.50, green: 0.82, blue: 0.94),
                                    Color.white.opacity(0.92),
                                    SongbirdThemePalette.blueMondayAccent,
                                    Color(red: 0.10, green: 0.36, blue: 0.56),
                                ]
                                : usesGoldWell
                                    ? [
                                        SongbirdThemePalette.gonzoAccent,
                                        Color(red: 0.90, green: 0.80, blue: 0.40),
                                        Color.white.opacity(0.85),
                                        SongbirdThemePalette.gonzoAccent,
                                        Color(red: 0.55, green: 0.45, blue: 0.15),
                                    ]
                                : usesVioletWell
                                    ? [
                                        SongbirdThemePalette.purpleRainAccent,
                                        Color(red: 0.72, green: 0.48, blue: 0.88),
                                        Color.white.opacity(0.25),
                                        SongbirdThemePalette.purpleRainAccent,
                                        Color(red: 0.35, green: 0.15, blue: 0.52),
                                    ]
                                : [
                                    Color.black.opacity(usesDarkWell ? 0.65 : 0.28),
                                    Color.black.opacity(usesDarkWell ? 0.35 : 0.12),
                                    Color.white.opacity(usesDarkWell ? 0.18 : 0.55),
                                    Color.black.opacity(usesDarkWell ? 0.45 : 0.16),
                                    Color.black.opacity(usesDarkWell ? 0.65 : 0.28),
                                ],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        lineWidth: 1.5
                    )

                Label(title, systemImage: systemName)
                    .labelStyle(.iconOnly)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(tint ?? wellGlyph)
                    .offset(x: glyphOffset)
            }
            .frame(width: size, height: size)
            .contentShape(playerControlShape)
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func controlTitle(for systemName: String) -> String {
        switch systemName {
        case "backward.end.fill": return "Previous Track"
        case "play.fill": return "Play"
        case "pause.fill": return "Pause"
        case "forward.end.fill": return "Next Track"
        case "shuffle": return "Shuffle"
        case "repeat", "repeat.1": return "Repeat"
        default: return "Playback Control"
        }
    }

    // MARK: - Volume

    private var volumeControls: some View {
        PlaybackVolumeReader { volume in
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(secondaryColor)
                    .accessibilityHidden(true)
                VolumePillSlider(
                    value: Binding(
                        get: { volume },
                        set: { playbackEngine.setVolume($0) }
                    ),
                    isDark: isDark
                )
                .frame(width: 92, height: 16)
                .disabled(isEditingLayout)
            }
        }
    }

    private var shuffleRepeatControls: some View {
        PlaybackQueueReader(queue: queue) { queue in
            HStack(spacing: 6) {
                shuffleButton(queue: queue)
                repeatButton(queue: queue)
            }
        }
    }

    private func shuffleButton(queue: PlaybackQueue) -> some View {
        flatWellButton(
            "shuffle",
            size: 22,
            iconSize: 9,
            tint: queue.shuffleEnabled ? Color.accentColor : iconColor
        ) {
            queue.shuffleEnabled.toggle()
        }
        .help(queue.shuffleEnabled ? "Shuffle On" : "Shuffle Off")
        .disabled(isEditingLayout)
        .opacity(queue.shuffleEnabled ? 1 : 0.55)
    }

    private func repeatButton(queue: PlaybackQueue) -> some View {
        flatWellButton(
            queue.repeatMode.systemImage,
            size: 22,
            iconSize: 9,
            tint: queue.repeatMode == .off ? iconColor : Color.accentColor
        ) {
            playbackEngine.cycleRepeatMode()
        }
        .help(queue.repeatMode.help)
        .disabled(isEditingLayout)
        .opacity(queue.repeatMode == .off ? 0.55 : 1)
    }

    // MARK: - Faceplate (centered now-playing box)

    private var faceplate: some View {
        let track = playbackPresentation.currentTrack
        return Group {
            if let track {
                PlaybackClockReader { position, duration in
                    playingFaceplate(
                        track: track,
                        progress: duration > 0 ? position / duration : 0,
                        position: position,
                        duration: duration
                    )
                }
            } else {
                idleFaceplate
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(faceplateBackground)
        .overlay {
            // LCD backlight glow — warm center bloom tinted by theme
            RadialGradient(
                colors: [
                    faceplateStyle.lcdText.opacity(faceplateStyle.glowOpacity),
                    Color.clear,
                ],
                center: .center,
                startRadius: 0,
                endRadius: 120
            )
            .allowsHitTesting(false)
        }
        .overlay {
            // Scanline texture — subtle LCD pixel rows
            if faceplateStyle.scanlineOpacity > 0 {
                ScanlineTexture(opacity: faceplateStyle.scanlineOpacity)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: faceplateCornerRadius, style: .continuous))
        .overlay {
            ZStack {
                // Outer accent stroke
                RoundedRectangle(cornerRadius: faceplateCornerRadius, style: .continuous)
                    .stroke(
                        faceplateStrokeColor,
                        lineWidth: 1
                    )
                // Inner bevel — top highlight, bottom shadow
                RoundedRectangle(cornerRadius: faceplateCornerRadius, style: .continuous)
                    .inset(by: 1)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.clear,
                                Color.clear,
                                Color.black.opacity(0.18),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                // Per-feather inner glow — LCD backlight bloom
                if faceplateStyle.glowOpacity > 0 {
                    RoundedRectangle(cornerRadius: faceplateCornerRadius - 2, style: .continuous)
                        .inset(by: 2)
                        .stroke(faceplateStyle.glowColor.opacity(faceplateStyle.glowOpacity), lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .shadow(
            color: .black.opacity(featherTreatment.usesSmokedFaceplate ? 0.28 : (isDark ? 0.35 : 0.10)),
            radius: featherTreatment.usesSmokedFaceplate ? 2 : 1,
            x: 0,
            y: 1
        )
        .contextMenu {
            if let track,
               let snapshot = librarySnapshots.trackSnapshot(id: track.id) {
                TrackContextMenu(
                    track: snapshot,
                    targetIDs: [track.id],
                    playNowAction: { libraryActions.requestPlayNow(trackID: track.id) }
                )
            }
        }
        .accessibilityAction(named: "Go to Album") {
            guard let albumID = track?.albumRelation?.id else { return }
            libraryActions.showAlbum(albumID: albumID)
        }
        .accessibilityAction(named: "Go to Artist") {
            guard let track else { return }
            libraryActions.showArtist(name: track.audioCDMetadata(at: discogsClock.now).artist)
        }
        .accessibilityAction(named: "Add to New Playlist") {
            guard let track else { return }
            libraryActions.requestNewPlaylist(trackIDs: [track.id])
        }
        .accessibilityAction(named: "Show Lyrics") {
            guard let track else { return }
            libraryActions.showLyrics(trackID: track.id)
        }
        .accessibilityAction(named: "Show in Finder") {
            guard let track else { return }
            libraryActions.showInFinder(trackIDs: [track.id])
        }
        .accessibilityAction(named: {
            guard let track, let snap = librarySnapshots.trackSnapshot(id: track.id) else { return "Add to Favorites" }
            return snap.isLoved ? "Remove from Favorites" : "Add to Favorites"
        }()) {
            guard let track else { return }
            let isLoved = librarySnapshots.trackSnapshot(id: track.id)?.isLoved ?? false
            libraryActions.setTrackLoved(!isLoved, trackIDs: [track.id])
        }
    }

    private var faceplateBackground: some View {
        LinearGradient(
            colors: [
                SongbirdTheme.faceplateTop(for: colorScheme),
                SongbirdTheme.faceplateBottom(for: colorScheme)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var faceplateStrokeColor: Color {
        faceplateStyle.strokeColor
    }

    private func faceplateFont(size: CGFloat, weight: Font.Weight) -> Font {
        .system(
            size: size,
            weight: weight,
            design: featherTreatment.usesMonospacedTypography ? .monospaced : .default
        )
    }

    @ViewBuilder
    private var idleFaceplate: some View {
        let logoHeight = max(faceplateHeight - 6, 28)
        ArtworkThumbnailView(
            reference: .songbirdLogo,
            pointSize: CGSize(
                width: min(renderedFaceplateWidth - 24, logoHeight * 1.2),
                height: logoHeight
            ),
            accessibilityLabel: "Songbird",
            cornerRadius: 0,
            contentMode: .fit,
            placeholderColor: .clear,
            tintColor: featherTreatment.usesSmokedFaceplate
                || featherTreatment.usesGraphiteFaceplate
                || featherTreatment.usesWarmFaceplate
                || featherTreatment.usesVioletFaceplate
                ? SongbirdTheme.lcdTextColor(for: colorScheme)
                : Color.black.opacity(0.88)
        )
        .brightness(usesBrightIdleArtwork ? 0.18 : 0)
        .accessibilityHidden(featherTreatment.usesSmokedFaceplate)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func playingFaceplate(
        track: Track,
        progress: Double,
        position: TimeInterval,
        duration: TimeInterval
    ) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 6) {
                faceplateArtwork(for: track)

                if track.isAudioCDTrack {
                    AudioCDIcon(
                        color: SongbirdTheme.lcdTextColor(for: colorScheme),
                        isRotating: playbackPresentation.status == .playing
                    )
                    .frame(width: 13, height: 13)
                    .accessibilityHidden(true)
                }

                VStack(spacing: 1) {
                    DiscogsTrackAttributionView(track: track, now: discogsClock.now)
                    Text(displayTitle(for: track))
                        .font(faceplateFont(size: 11, weight: .semibold))
                        .foregroundColor(SongbirdTheme.lcdTextColor(for: colorScheme))
                        .shadow(color: SongbirdTheme.lcdTextColor(for: colorScheme).opacity(0.15), radius: 2)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(displaySubtitle(for: track))
                        .font(faceplateFont(size: 9, weight: .regular))
                        .foregroundColor(SongbirdTheme.lcdTextColor(for: colorScheme).opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity)
                .clipped()

                faceplateRating(for: track)
            }

            HStack(spacing: 6) {
                Text(formatTime(position))
                    .font(faceplateFont(size: 9, weight: .regular))
                    .foregroundColor(SongbirdTheme.lcdTextColor(for: colorScheme))
                    .shadow(color: SongbirdTheme.lcdTextColor(for: colorScheme).opacity(0.10), radius: 1)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)

                DiamondSeekBar(
                    progress: progress,
                    duration: duration,
                    isEnabled: !isEditingLayout && duration > 0,
                    isLoading: playbackPresentation.status == .loading,
                    lcdText: SongbirdTheme.lcdTextColor(for: colorScheme)
                ) { fraction in
                    playbackEngine.seekTo(fraction * duration)
                }
                .frame(height: 8)
                .layoutPriority(1)

                Button(action: cycleTimeMode) {
                    Text(timeTrailingLabel(position: position, duration: duration))
                        .font(faceplateFont(size: 9, weight: .regular))
                        .foregroundColor(SongbirdTheme.lcdTextColor(for: colorScheme))
                        .shadow(color: SongbirdTheme.lcdTextColor(for: colorScheme).opacity(0.10), radius: 1)
                        .monospacedDigit()
                        .frame(width: 34, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Change Time Display — \(timeLabel(position: position, duration: duration))")
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture(count: 2) {
            if !isEditingLayout {
                NotificationCenter.default.post(name: .openMiniPlayer, object: nil)
            }
        }
    }

    @ViewBuilder
    private func faceplateArtwork(for track: Track) -> some View {
        ArtworkThumbnailView(
            reference: ArtworkReference.resolved(for: track),
            pointSize: CGSize(width: 28, height: 28),
            accessibilityLabel: "Album artwork for \(track.audioCDMetadata(at: discogsClock.now).album)",
            placeholderColor: SongbirdTheme.lcdTextColor(for: colorScheme).opacity(0.12)
        )
    }

    private func timeTrailingLabel(position: TimeInterval, duration: TimeInterval) -> String {
        switch timeMode {
        case .elapsed:
            return formatTime(duration)
        case .remaining:
            let remaining = max(duration - position, 0)
            return "-\(formatTime(remaining))"
        }
    }

    private func faceplateRating(for track: Track) -> some View {
        let isLoved = librarySnapshots.trackSnapshot(id: track.id)?.isLoved ?? false
        let starCount = track.rating > 0 ? min(track.rating, 5) : 0
        return HStack(spacing: 4) {
            StarRatingDisplay(rating: starCount, starSize: 8)
                .opacity(starCount > 0 ? 0.9 : 0.3)

            Button {
                libraryActions.setTrackLoved(!isLoved, trackIDs: [track.id])
            } label: {
                Image(systemName: isLoved ? "heart.fill" : "heart")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(
                        isLoved
                            ? Color.accentColor
                            : SongbirdTheme.lcdTextColor(for: colorScheme).opacity(0.4)
                    )
            }
            .buttonStyle(.plain)
            .help(isLoved ? "Remove Favorite" : "Favorite")
            .disabled(isEditingLayout)
        }
    }

    // MARK: - Helpers

    private enum TimeDisplayMode {
        case elapsed, remaining
    }

    private func timeLabel(position: TimeInterval, duration: TimeInterval) -> String {
        switch timeMode {
        case .elapsed:
            return "Elapsed Time: \(formatTime(position))"
        case .remaining:
            let remaining = max(duration - position, 0)
            return "Remaining Time: \(formatTime(remaining))"
        }
    }

    private func cycleTimeMode() {
        switch timeMode {
        case .elapsed: timeMode = .remaining
        case .remaining: timeMode = .elapsed
        }
    }

    private var visibleAlbumTrackIDs: [UUID]? {
        guard case .album(let albumID) = libraryNavigation.path.last else { return nil }
        return albumProjectionStore.group(
            containing: albumID,
            fallback: librarySnapshots.snapshot
        )?.trackIDs
    }

    private func performPrimaryPlayPause() {
        switch PrimaryTransportActionResolver.resolve(
            queueHasCurrentTrack: queue.currentTrack != nil,
            queueHasUpcomingTracks: queue.upcomingEntries.isEmpty == false,
            visibleAlbumTrackIDs: visibleAlbumTrackIDs,
            selectedTrackID: librarySelection.selectedLibraryTrackID
        ) {
        case .togglePlayPause:
            playbackEngine.togglePlayPause()
        case .playTracks(let trackIDs):
            libraryActions.requestPlay(trackIDs: trackIDs)
        }
    }

    private func displayTitle(for track: Track) -> String {
        if !track.audioCDMetadata(at: discogsClock.now).title.isEmpty { return track.audioCDMetadata(at: discogsClock.now).title }
        if !track.audioCDMetadata(at: discogsClock.now).album.isEmpty { return track.audioCDMetadata(at: discogsClock.now).album }
        return "Unknown"
    }

    private func displaySubtitle(for track: Track) -> String {
        let artist = track.audioCDMetadata(at: discogsClock.now).artist.isEmpty ? "Unknown Artist" : track.audioCDMetadata(at: discogsClock.now).artist
        let album = track.audioCDMetadata(at: discogsClock.now).album.isEmpty ? "Unknown Album" : track.audioCDMetadata(at: discogsClock.now).album
        return "\(artist) — \(album)"
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        return String(format: "%d:%02d", mins, secs)
    }

}

// MARK: - Diamond seek bar

struct DiamondSeekBar: View {
    let progress: Double
    let duration: TimeInterval
    let isEnabled: Bool
    var isLoading: Bool = false
    var lightChrome: Bool = false
    var lcdText: Color?
    let onSeek: (Double) -> Void

    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var bufferingPhase: CGFloat = 0

    private var shownProgress: Double {
        isDragging ? dragProgress : PlayerSliderBehavior.clamp(progress)
    }

    private var trackColor: Color {
        if let lcdText {
            return lcdText.opacity(0.20)
        }
        return lightChrome ? Color.white.opacity(0.55) : Color.black.opacity(0.75)
    }

    private var diamondColor: Color {
        if let lcdText {
            return lcdText.opacity(isEnabled ? 0.90 : 0.35)
        }
        return lightChrome
            ? Color.white.opacity(isEnabled ? 0.95 : 0.35)
            : Color.black.opacity(isEnabled ? 0.9 : 0.35)
    }

    private var bufferingStripeColor: Color {
        if let lcdText {
            return lcdText.opacity(0.30)
        }
        return lightChrome ? Color.white.opacity(0.30) : Color.black.opacity(0.30)
    }

    private var bufferingStripes: some View {
        GeometryReader { geo in
            let stripeWidth: CGFloat = 4
            let stripeSpacing: CGFloat = 8
            let totalWidth = stripeWidth + stripeSpacing
            Canvas { context, size in
                let count = Int(ceil(size.width / totalWidth)) + 2
                for i in 0..<count {
                    let x = CGFloat(i) * totalWidth + bufferingPhase
                    let rect = CGRect(x: x, y: 0, width: stripeWidth, height: size.height)
                    context.fill(Path(rect), with: .color(bufferingStripeColor))
                }
            }
            .mask(Rectangle())
        }
        .onAppear {
            guard isLoading else { return }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                bufferingPhase = -12
            }
        }
        .onChange(of: isLoading) { _, loading in
            if loading {
                bufferingPhase = 0
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    bufferingPhase = -12
                }
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let trackHeight: CGFloat = 4
            let diamondSize: CGFloat = 6
            let x = shownProgress * max(width - diamondSize, 0)

            ZStack(alignment: .leading) {
                Rectangle()
                    .strokeBorder(trackColor, lineWidth: 1)
                    .frame(height: trackHeight)
                    .frame(maxWidth: .infinity)
                    .frame(height: height, alignment: .center)

                // Notch marks at 25%, 50%, 75% — matching the legacy faceplate's 4-section seekbar
                ForEach([0.25, 0.50, 0.75], id: \.self) { fraction in
                    Rectangle()
                        .fill(trackColor)
                        .frame(width: 1, height: trackHeight + 2)
                        .offset(x: fraction * max(width - 1, 0))
                        .frame(height: height, alignment: .center)
                }

                if isLoading {
                    bufferingStripes
                        .frame(height: trackHeight)
                        .frame(maxWidth: .infinity)
                        .frame(height: height, alignment: .center)
                }

                DiamondShape()
                    .fill(diamondColor)
                    .frame(width: diamondSize, height: diamondSize)
                    .offset(x: x)
                    .frame(height: height, alignment: .center)
            }
            .allowsHitTesting(false)

            Slider(
                value: Binding(
                    get: { shownProgress },
                    set: { newValue in
                        isDragging = true
                        dragProgress = PlayerSliderBehavior.clamp(newValue)
                    }
                ),
                in: 0...1,
                step: PlayerSliderBehavior.seekStep(duration: duration),
                onEditingChanged: { editing in
                    guard isEnabled else { return }
                    if editing == false {
                        onSeek(dragProgress)
                        isDragging = false
                    }
                }
            )
            .labelsHidden()
            .opacity(0.02)
            .disabled(isEnabled == false)
            .accessibilityLabel("Playback position")
            .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                guard isEnabled else { return .ignored }
                let direction: FloatingPointSign = press.key == .rightArrow ? .plus : .minus
                onSeek(PlayerSliderBehavior.adjusted(
                    progress,
                    direction: direction,
                    step: PlayerSliderBehavior.seekStep(duration: duration)
                ))
                return .handled
            }
        }
    }
}

private struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// Recessed pill groove + circular well thumb (Songbird volume shape).
struct VolumePillSlider: View {
    @Binding var value: Double
    var isDark: Bool

    private let trackHeight: CGFloat = 7
    private let thumbSize: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let travel = max(width - thumbSize, 1)
            let x = PlayerSliderBehavior.clamp(value) * travel

            ZStack(alignment: .leading) {
                // Inset pill groove
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [Color(white: 0.10), Color(white: 0.18)]
                                : [Color(white: 0.72), Color(white: 0.84)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(isDark ? 0.55 : 0.25),
                                        Color.white.opacity(isDark ? 0.12 : 0.45)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .frame(height: trackHeight)
                    .frame(maxWidth: .infinity)
                    .frame(height: height, alignment: .center)

                // Circular thumb — also a small flat well with a center dimple
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isDark
                                    ? [Color(white: 0.14), Color(white: 0.24)]
                                    : [Color(white: 0.80), Color(white: 0.92)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(isDark ? 0.5 : 0.22),
                                    Color.white.opacity(isDark ? 0.12 : 0.5)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    Circle()
                        .fill(Color.black.opacity(isDark ? 0.45 : 0.2))
                        .frame(width: 3.5, height: 3.5)
                }
                .frame(width: thumbSize, height: thumbSize)
                .offset(x: x)
                .frame(height: height, alignment: .center)
            }
            .allowsHitTesting(false)

            Slider(value: $value, in: 0...1, step: PlayerSliderBehavior.volumeIncrement)
                .labelsHidden()
                .opacity(0.02)
                .accessibilityLabel("Volume")
        }
    }
}
