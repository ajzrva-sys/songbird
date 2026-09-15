import SwiftUI
import AppKit
import SwiftData

public struct MiniPlayerView: View {
    @ObservedObject private var discogsClock = DiscogsPresentationClock.shared
    @EnvironmentObject private var playbackSession: PlaybackSession
    @EnvironmentObject private var playbackPresentation: PlaybackPresentationState
    @EnvironmentObject private var librarySnapshots: LibrarySnapshotStore
    @EnvironmentObject private var libraryActions: LibraryItemActionHandler
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @AppStorage(SongbirdThemeID.storageKey) private var themeID = SongbirdThemeID.blueMonday.rawValue
    @AppStorage(MiniPlayerStyle.storageKey) private var styleRaw = MiniPlayerStyle.modern.rawValue
    @AppStorage("miniPlayer.floatOnTop") private var floatOnTop = false
    @AppStorage(NowPlayingLayoutSettings.faceplateWidthKey)
    private var faceplateWidth = NowPlayingLayoutSettings.defaultFaceplateWidth
    @AppStorage(NowPlayingLayoutSettings.faceplateHeightKey)
    private var faceplateHeight = NowPlayingLayoutSettings.defaultFaceplateHeight

    private var style: MiniPlayerStyle {
        MiniPlayerStyle(rawValue: styleRaw) ?? .modern
    }

    private var textColor: Color { SongbirdTheme.text(for: colorScheme) }
    private var secondaryTextColor: Color { SongbirdTheme.secondaryText(for: colorScheme) }
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
    private var playbackEngine: PlaybackEngine { playbackSession.engine }
    private var queue: PlaybackQueue { playbackSession.queue }

    public init() {}

    public var body: some View {
        Group {
            switch style {
            case .modern, .glass:
                modernChrome
            case .classic:
                classicChrome
            case .strip:
                stripChrome
            }
        }
        .frame(
            minWidth: style == .strip ? 712 : (style == .classic ? 448 : modernMinimumWidth),
            idealWidth: style == .strip ? 872 : (style == .classic ? 552 : modernIdealWidth),
            maxWidth: style == .strip ? 1600 : (style == .classic ? 1200 : 2400),
            minHeight: compactChromeHeight ?? modernMinimumHeight,
            idealHeight: compactChromeHeight ?? modernMinimumHeight,
            maxHeight: compactChromeHeight ?? modernMinimumHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: chromeCornerRadius, style: .continuous))
        .overlay {
            if colorSchemeContrast == .increased {
                RoundedRectangle(
                    cornerRadius: chromeCornerRadius,
                    style: .continuous
                )
                .stroke(Color.primary, lineWidth: 2)
            }
        }
        .preferredColorScheme(
            isGlass && reduceTransparency == false
                ? .dark
                : SongbirdThemeID.resolved(rawValue: themeID).appearance.preferredColorScheme
        )
        .accessibilityIdentifier("player.miniBar")
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            returnToFullPlayer()
        }
        .contextMenu {
            if let track = playbackPresentation.currentTrack,
               let snapshot = librarySnapshots.trackSnapshot(id: track.id) {
                TrackContextMenu(
                    track: snapshot,
                    targetIDs: [track.id],
                    bringMainPlayerForward: true,
                    playNowAction: { libraryActions.requestPlayNow(trackID: track.id) }
                )
                Divider()
            }
            Button("Show Full Player") {
                DispatchQueue.main.async { closeMiniPlayer() }
            }

            Button("Minimize") {
                DispatchQueue.main.async { minimizeMiniPlayer() }
            }

            Toggle("Stay on Top", isOn: $floatOnTop)

            Divider()

            Button("Close Mini Player") {
                DispatchQueue.main.async { closeMiniPlayer() }
            }
        }
        .accessibilityAction(named: "Go to Album") {
            guard let albumID = playbackPresentation.currentTrack?.albumRelation?.id else { return }
            libraryActions.showAlbum(albumID: albumID, bringMainPlayerForward: true)
        }
        .accessibilityAction(named: "Go to Artist") {
            guard let track = playbackPresentation.currentTrack else { return }
            libraryActions.showArtist(name: track.audioCDMetadata(at: discogsClock.now).artist, bringMainPlayerForward: true)
        }
        .accessibilityAction(named: "Add to New Playlist") {
            guard let track = playbackPresentation.currentTrack else { return }
            libraryActions.requestNewPlaylist(
                trackIDs: [track.id],
                bringMainPlayerForward: true
            )
        }
        .accessibilityAction(named: "Show Lyrics") {
            guard let track = playbackPresentation.currentTrack else { return }
            libraryActions.showLyrics(trackID: track.id)
        }
        .accessibilityAction(named: "Show in Finder") {
            guard let track = playbackPresentation.currentTrack else { return }
            libraryActions.showInFinder(trackIDs: [track.id])
        }
        .accessibilityAction(named: favoriteAccessibilityActionName) {
            toggleFavorite()
        }
        .onChange(of: floatOnTop) { _, enabled in
            applyFloatOnTop(enabled)
        }
        .help("Double-click or ⌥⌘M to show the full player")
    }

    private func returnToFullPlayer() {
        closeMiniPlayer()
    }

    private func closeMiniPlayer() {
        // Target the main scene explicitly. Never fall back to an arbitrary
        // non-mini window, which may be the Settings scene.
        if PlayerWindowMode.mainWindows().isEmpty {
            openWindow(id: "main-player")
        }
        DispatchQueue.main.async {
            PlayerWindowMode.enterFullMode(closeMini: true)
            NotificationCenter.default.post(name: .showMainPlayer, object: nil)
        }
    }

    private func minimizeMiniPlayer() {
        guard let window = miniPlayerWindow() else { return }
        if !window.styleMask.contains(.miniaturizable) {
            window.styleMask.insert(.miniaturizable)
        }
        window.miniaturize(nil)
    }

    private func applyFloatOnTop(_ enabled: Bool) {
        for window in PlayerWindowMode.miniWindows() {
            window.level = enabled ? .floating : .normal
        }
        if let window = miniPlayerWindow() {
            window.level = enabled ? .floating : .normal
        }
    }

    private func miniPlayerWindow() -> NSWindow? {
        if let key = NSApp.keyWindow, key.identifier?.rawValue == "mini-player" {
            return key
        }
        if let match = PlayerWindowMode.miniWindows().first {
            return match
        }
        return NSApp.windows.first {
            $0.title == "Mini Player" || $0.identifier?.rawValue == "mini-player"
        }
    }

    // MARK: - Modern / Glass (matches main Now Playing chrome)

    /// Leading inset for modern/glass chrome (no traffic lights).
    private var modernLeadingWidth: CGFloat { 14 }
    private let modernTrailingPad: CGFloat = 16
    private let modernColumnGap: CGFloat = 12
    /// Intrinsic width of transport + volume/output + shuffle (must stay fully visible).
    private let modernControlsWidth: CGFloat = 304
    /// Smallest faceplate before the window stops shrinking.
    private let modernMinFaceplateWidth: CGFloat = 280
    private var isGlass: Bool { style == .glass }
    private var compactChromeHeight: CGFloat? {
        switch style {
        case .classic: classicChromeHeight
        case .strip: stripChromeHeight
        case .modern, .glass: nil
        }
    }
    private var chromeCornerRadius: CGFloat {
        switch style {
        case .glass: 16
        case .classic, .strip: 6
        case .modern: 10
        }
    }

    private var modernMinimumWidth: CGFloat {
        modernLeadingWidth
            + modernControlsWidth
            + modernColumnGap
            + modernMinFaceplateWidth
            + modernTrailingPad
    }

    private var modernIdealWidth: CGFloat {
        modernLeadingWidth
            + modernControlsWidth
            + modernColumnGap
            + CGFloat(faceplateWidth)
            + modernTrailingPad
    }

    private var modernMinimumHeight: CGFloat {
        max(CGFloat(faceplateHeight) + 16, 64)
    }

    private var modernChrome: some View {
        // Controls stay fixed on the left. Faceplate fills to the trailing
        // window edge and is the only piece that grows/shrinks.
        HStack(spacing: modernColumnGap) {
            HStack(spacing: 8) {
                modernTransport
                modernVolume
                modernShuffleRepeat
            }
            .fixedSize(horizontal: true, vertical: false)

            modernFaceplate
                .frame(minWidth: modernMinFaceplateWidth, maxWidth: .infinity)
                .frame(height: faceplateHeight)
        }
        .padding(.leading, modernLeadingWidth)
        .padding(.trailing, modernTrailingPad)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: modernMinimumHeight)
        .background {
            Group {
                if isGlass && reduceTransparency == false {
                    MiniPlayerVisualEffectBackground()
                } else if isGlass {
                    Color(nsColor: .windowBackgroundColor)
                } else {
                    modernBarBackground
                }
            }
        }
    }

    private var modernTransport: some View {
        // Same proportions as the main bar: play ≈ 1.45× side wells.
        HStack(spacing: 3) {
            flatWellButton("backward.end.fill", size: 26, iconSize: 10) {
                playbackEngine.playPrevious()
            }
            flatWellButton(
                playbackPresentation.status == .playing ? "pause.fill" : "play.fill",
                size: 38,
                iconSize: 14,
                glyphOffset: playbackPresentation.status == .playing ? 0 : 1
            ) {
                playbackEngine.togglePlayPause()
            }
            flatWellButton("forward.end.fill", size: 26, iconSize: 10) {
                playbackEngine.playNext()
            }
        }
    }

    private var modernVolume: some View {
        PlaybackVolumeReader { volume in
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isGlass ? Color.white.opacity(0.75) : secondaryTextColor)
                    .accessibilityHidden(true)
                VolumePillSlider(
                    value: Binding(
                        get: { volume },
                        set: { playbackEngine.setVolume($0) }
                    ),
                    isDark: isGlass || isDark
                )
                .frame(width: 92, height: 16)
            }
        }
    }

    private var modernShuffleRepeat: some View {
        PlaybackQueueReader(queue: queue) { queue in
            HStack(spacing: 6) {
                flatWellButton(
                    "shuffle",
                    size: 22,
                    iconSize: 9,
                    tint: queue.shuffleEnabled ? .accentColor : (isGlass ? .white : textColor)
                ) {
                    queue.shuffleEnabled.toggle()
                }
                .help(queue.shuffleEnabled ? "Shuffle On" : "Shuffle Off")
                .opacity(queue.shuffleEnabled ? 1 : 0.55)

                flatWellButton(
                    queue.repeatMode.systemImage,
                    size: 22,
                    iconSize: 9,
                    tint: queue.repeatMode == .off
                        ? (isGlass ? .white : textColor)
                        : .accentColor
                ) {
                    playbackEngine.cycleRepeatMode()
                }
                .help(queue.repeatMode.help)
                .opacity(queue.repeatMode == .off ? 0.55 : 1)
            }
        }
    }

    private var modernFaceplate: some View {
        Group {
            if let track = playbackPresentation.currentTrack {
                PlaybackClockReader { position, duration in
                    modernPlayingFaceplate(track: track, position: position, duration: duration)
                }
            } else {
                modernIdleFaceplate
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isGlass {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            } else {
                LinearGradient(
                    colors: [
                        SongbirdTheme.faceplateTop(for: colorScheme),
                        SongbirdTheme.faceplateBottom(for: colorScheme)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .overlay {
            if isGlass == false {
                // LCD backlight glow — warm center bloom tinted by theme
                RadialGradient(
                    colors: [
                        faceplateStyle.lcdText.opacity(faceplateStyle.glowOpacity),
                        Color.clear,
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 80
                )
                .allowsHitTesting(false)
            }
        }
        .overlay {
            // Scanline texture
            if isGlass == false, faceplateStyle.scanlineOpacity > 0 {
                ScanlineTexture(opacity: faceplateStyle.scanlineOpacity)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isGlass ? 10 : 7, style: .continuous))
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: isGlass ? 10 : 7, style: .continuous)
                    .stroke(
                        isGlass
                            ? Color.white.opacity(0.18)
                            : featherTreatment.usesGraphiteFaceplate
                                ? SongbirdThemePalette.blueMondayAccent.opacity(0.70)
                            : featherTreatment.usesWarmFaceplate
                                ? SongbirdThemePalette.gonzoAccent.opacity(0.60)
                            : featherTreatment.usesVioletFaceplate
                                ? SongbirdThemePalette.purpleRainAccent.opacity(0.55)
                            : featherTreatment.usesSmokedFaceplate
                                ? Color(red: 0.44, green: 0.18, blue: 0.29)
                                : Color.black.opacity(isDark ? 0.55 : 0.20),
                        lineWidth: 1
                    )
                // Inner bevel — top highlight, bottom shadow
                if isGlass == false {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
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
                }
                // Per-feather inner glow
                if isGlass == false, faceplateStyle.glowOpacity > 0 {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .inset(by: 2)
                        .stroke(faceplateStyle.glowColor.opacity(faceplateStyle.glowOpacity), lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .shadow(
            color: .black.opacity(
                isGlass ? 0 : (featherTreatment.usesSmokedFaceplate ? 0.28 : (isDark ? 0.35 : 0.10))
            ),
            radius: featherTreatment.usesSmokedFaceplate ? 2 : 1,
            y: 1
        )
    }

    @ViewBuilder
    private var modernIdleFaceplate: some View {
        let logoHeight = max(faceplateHeight - 6, 28)
        GeometryReader { geo in
            ArtworkThumbnailView(
                reference: .songbirdLogo,
                pointSize: CGSize(
                    width: min(max(geo.size.width - 24, 40), logoHeight * 1.2),
                    height: logoHeight
                ),
                accessibilityLabel: "Songbird",
                cornerRadius: 0,
                contentMode: .fit,
                placeholderColor: .clear,
                tintColor: isGlass == false
                    && (featherTreatment.usesSmokedFaceplate
                        || featherTreatment.usesGraphiteFaceplate
                        || featherTreatment.usesWarmFaceplate
                        || featherTreatment.usesVioletFaceplate)
                    ? SongbirdTheme.lcdTextColor(for: colorScheme)
                    : Color.black.opacity(0.88)
            )
            .accessibilityHidden(isGlass == false && featherTreatment.usesSmokedFaceplate)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func modernPlayingFaceplate(
        track: Track,
        position: TimeInterval,
        duration: TimeInterval
    ) -> some View {
        let progress = duration > 0
            ? position / duration
            : 0
        return VStack(spacing: 1) {
            HStack(spacing: 6) {
                artwork(for: track, size: 28)

                VStack(spacing: 1) {
                    DiscogsTrackAttributionView(track: track, now: discogsClock.now)
                    Text(track.audioCDMetadata(at: discogsClock.now).title.isEmpty ? "Unknown" : track.audioCDMetadata(at: discogsClock.now).title)
                        .font(.system(size: 11, weight: .semibold))
                        .shadow(color: SongbirdTheme.lcdTextColor(for: colorScheme).opacity(0.15), radius: 2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text([track.audioCDMetadata(at: discogsClock.now).artist, track.audioCDMetadata(at: discogsClock.now).album].filter { !$0.isEmpty }.joined(separator: " — "))
                        .font(.system(size: 9, weight: .regular))
                        .opacity(0.85)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity)

                modernRating(for: track)
            }

            HStack(spacing: 6) {
                Text(formatTime(position))
                    .frame(width: 34, alignment: .trailing)
                DiamondSeekBar(
                    progress: progress,
                    duration: duration,
                    isEnabled: duration > 0,
                    lightChrome: isGlass,
                    lcdText: isGlass ? nil : SongbirdTheme.lcdTextColor(for: colorScheme)
                ) { fraction in
                    playbackEngine.seekTo(fraction * duration)
                }
                .frame(height: 8)
                Text(formatTime(duration))
                    .frame(width: 40, alignment: .leading)
            }
            .font(.system(size: 9, weight: .regular))
            .monospacedDigit()
            .padding(.horizontal, 8)
        }
        .foregroundStyle(
            isGlass
                ? Color.white.opacity(0.95)
                : SongbirdTheme.lcdTextColor(for: colorScheme)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func modernRating(for track: Track) -> some View {
        let isLoved = librarySnapshots.trackSnapshot(id: track.id)?.isLoved ?? false
        return Button {
            toggleFavorite()
        } label: {
            Image(systemName: isLoved ? "heart.fill" : "heart")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(
                    isLoved
                        ? Color.accentColor
                        : (isGlass
                            ? Color.white.opacity(0.4)
                            : SongbirdTheme.lcdTextColor(for: colorScheme).opacity(0.4))
                )
        }
        .buttonStyle(.plain)
        .help(isLoved ? "Remove Favorite" : "Favorite")
    }

    // MARK: - Strip (original Songbird-inspired single-row player)

    private let stripChromeHeight: CGFloat = 32

    private var stripChrome: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                stripButton("Previous Track", systemImage: "backward.end.fill", width: 48) {
                    playbackEngine.playPrevious()
                }
                stripButton(
                    playbackPresentation.status == .playing ? "Pause" : "Play",
                    systemImage: playbackPresentation.status == .playing ? "pause.fill" : "play.fill",
                    width: 64
                ) {
                    playbackEngine.togglePlayPause()
                }
                stripButton("Next Track", systemImage: "forward.end.fill", width: 48) {
                    playbackEngine.playNext()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            PlaybackVolumeReader { volume in
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                        .accessibilityHidden(true)
                    Slider(
                        value: Binding(
                            get: { volume },
                            set: { playbackEngine.setVolume($0) }
                        ),
                        in: 0...1,
                        step: PlayerSliderBehavior.volumeIncrement
                    )
                    .controlSize(.mini)
                    .accessibilityLabel("Volume")
                }
                .frame(width: 128)
            }

            stripFaceplate
                .frame(minWidth: 320, maxWidth: .infinity)

            if let track = playbackPresentation.currentTrack {
                let isLoved = librarySnapshots.trackSnapshot(id: track.id)?.isLoved ?? false
                Button {
                    toggleFavorite()
                } label: {
                    Label(
                        isLoved ? "Remove Favorite" : "Favorite",
                        systemImage: isLoved ? "heart.fill" : "heart"
                    )
                    .labelStyle(.iconOnly)
                    .foregroundStyle(isLoved ? Color.accentColor : secondaryTextColor)
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(isLoved ? "Remove Favorite" : "Favorite")
            }

            Button {
                returnToFullPlayer()
            } label: {
                Label("Show Full Player", systemImage: "rectangle.on.rectangle")
                    .labelStyle(.iconOnly)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(textColor)
            .help("Show Full Player")

            Button {
                closeMiniPlayer()
            } label: {
                Label("Close Mini Player", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 18, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(textColor)
            .help("Close Mini Player")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .frame(height: stripChromeHeight)
        .background(
            LinearGradient(
                colors: [
                    SongbirdTheme.nowPlayingBar(for: colorScheme),
                    SongbirdTheme.background(for: colorScheme)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(SongbirdTheme.divider(for: colorScheme), lineWidth: 1)
        }
    }

    private var stripFaceplate: some View {
        Group {
            if let track = playbackPresentation.currentTrack {
                PlaybackClockReader { position, duration in
                    VStack(spacing: 1) {
                        HStack(spacing: 8) {
                            DiscogsTrackAttributionView(track: track, now: discogsClock.now)
                            Text(track.audioCDMetadata(at: discogsClock.now).title.isEmpty ? "Unknown" : track.audioCDMetadata(at: discogsClock.now).title)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(formatTime(position)) / \(formatTime(duration))")
                                .monospacedDigit()
                                .fixedSize()
                        }
                        .font(.caption2)

                        DiamondSeekBar(
                            progress: duration > 0 ? position / duration : 0,
                            duration: duration,
                            isEnabled: duration > 0,
                            lightChrome: false,
                            lcdText: SongbirdTheme.lcdTextColor(for: colorScheme)
                        ) { fraction in
                            playbackEngine.seekTo(fraction * duration)
                        }
                        .frame(height: 5)
                    }
                    .padding(.horizontal, 8)
                }
            } else {
                Text("Songbird")
                    .font(.caption2)
                    .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(SongbirdTheme.lcdTextColor(for: colorScheme))
        .frame(height: 22)
        .background(
            LinearGradient(
                colors: [
                    SongbirdTheme.faceplateTop(for: colorScheme),
                    SongbirdTheme.faceplateBottom(for: colorScheme)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(SongbirdTheme.divider(for: colorScheme), lineWidth: 1)
        }
    }

    private func stripButton(
        _ title: String,
        systemImage: String,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(textColor)
                .frame(width: width, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            LinearGradient(
                colors: [
                    SongbirdTheme.nowPlayingBar(for: colorScheme),
                    SongbirdTheme.background(for: colorScheme)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SongbirdTheme.divider(for: colorScheme))
                .frame(width: 1)
                .accessibilityHidden(true)
        }
        .help(title)
    }

    // MARK: - Classic (early iTunes mini player)

    private let classicChromeHeight: CGFloat = 32

    private var classicChrome: some View {
        HStack(spacing: 6) {
            classicTransportWell
            classicVolume
            classicLCD
                .frame(maxWidth: .infinity)
            classicRatingWell
            classicCloseButton
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .frame(height: classicChromeHeight)
        .background(classicMetalBackground)
        .overlay {
            // Top highlight + edge like brushed-metal iTunes mini.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.45),
                            Color.black.opacity(0.40)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    private var classicTransportWell: some View {
        HStack(spacing: 0) {
            classicTransportButton("backward.end.fill") {
                playbackEngine.playPrevious()
            }
            classicTransportButton(
                playbackPresentation.status == .playing ? "pause.fill" : "play.fill",
                glyphOffset: playbackPresentation.status == .playing ? 0 : 0.5
            ) {
                playbackEngine.togglePlayPause()
            }
            classicTransportButton("forward.end.fill") {
                playbackEngine.playNext()
            }
        }
        .padding(.horizontal, 1)
        .padding(.vertical, 1)
        .background(classicLightWell)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func classicTransportButton(
        _ systemName: String,
        glyphOffset: CGFloat = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color(white: 0.12))
                .offset(x: glyphOffset)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var classicVolume: some View {
        PlaybackVolumeReader { volume in
            HStack(spacing: 2) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(Color(white: 0.28))
                    .accessibilityHidden(true)
                Slider(
                    value: Binding(
                        get: { volume },
                        set: { playbackEngine.setVolume($0) }
                    ),
                    in: 0...1,
                    step: PlayerSliderBehavior.volumeIncrement
                )
                .controlSize(.mini)
                .frame(width: 48)
                .accessibilityLabel("Volume")
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(Color(white: 0.28))
                    .accessibilityHidden(true)
            }
        }
    }

    private var classicLCD: some View {
        HStack(spacing: 0) {
            Text(classicDisplayText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(white: 0.92))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if playbackPresentation.currentTrack != nil {
                Rectangle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 1, height: 11)
                    .padding(.horizontal, 5)

                PlaybackClockReader { position, duration in
                    Text("\(formatTime(position)) / \(formatTime(duration))")
                        .font(.system(size: 10, weight: .regular).monospacedDigit())
                        .foregroundStyle(Color(white: 0.88))
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(
            LinearGradient(
                colors: [
                    Color(white: 0.14),
                    Color(white: 0.07)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.black.opacity(0.55), lineWidth: 1)
        }
    }

    private var classicDisplayText: String {
        guard let track = playbackPresentation.currentTrack else { return "Songbird" }
        let parts = [track.audioCDMetadata(at: discogsClock.now).title, track.audioCDMetadata(at: discogsClock.now).artist, track.audioCDMetadata(at: discogsClock.now).album].filter { !$0.isEmpty }
        if parts.isEmpty { return "Songbird" }
        return parts.joined(separator: "  •  ")
    }

    private var classicRatingWell: some View {
        let isLoved = playbackPresentation.currentTrack.flatMap {
            librarySnapshots.trackSnapshot(id: $0.id)?.isLoved
        } ?? false
        return Button {
            toggleFavorite()
        } label: {
            Image(systemName: isLoved ? "heart.fill" : "heart")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(
                    isLoved
                        ? Color(red: 0.88, green: 0.18, blue: 0.26)
                        : Color(white: 0.42)
                )
                .frame(width: 18, height: 14)
        }
        .buttonStyle(.plain)
        .disabled(playbackPresentation.currentTrack == nil)
        .help(isLoved ? "Remove from Favorites" : "Add to Favorites")
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            LinearGradient(
                colors: [Color(white: 0.14), Color(white: 0.07)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.black.opacity(0.55), lineWidth: 1)
        }
    }

    private var classicCloseButton: some View {
        Button {
            returnToFullPlayer()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color(white: 0.28))
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show Full Player")
    }



    /// Light recessed well for transport (matches early iTunes mini).
    private var classicLightWell: some View {
        LinearGradient(
            colors: [
                Color(white: 0.92),
                Color(white: 0.78),
                Color(white: 0.86)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.black.opacity(0.35), lineWidth: 1)
        }
    }

    private var recessedWell: some View {
        LinearGradient(
            colors: [
                Color(white: 0.55),
                Color(white: 0.68),
                Color(white: 0.58)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.black.opacity(0.28), lineWidth: 1)
        }
    }

    /// Medium brushed-metal grey (closer to early iTunes than silver-white).
    @ViewBuilder
    private var classicMetalBackground: some View {
        if featherTreatment.usesBlueMondayChrome {
            LinearGradient(
                colors: [
                    Color(white: 0.94),
                    Color(white: 0.78),
                    Color(white: 0.86),
                    Color(white: 0.70),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if featherTreatment == .pinkMartini {
            LinearGradient(
                colors: [
                    Color(red: 0.88, green: 0.76, blue: 0.81),
                    Color(red: 0.72, green: 0.52, blue: 0.61),
                    Color(red: 0.79, green: 0.62, blue: 0.69),
                    Color(red: 0.62, green: 0.40, blue: 0.50),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if featherTreatment.usesGonzoChrome {
            LinearGradient(
                colors: [
                    Color(red: 0.88, green: 0.82, blue: 0.68),
                    Color(red: 0.78, green: 0.70, blue: 0.52),
                    Color(red: 0.83, green: 0.76, blue: 0.60),
                    Color(red: 0.72, green: 0.64, blue: 0.46),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if featherTreatment.usesPurpleChrome {
            LinearGradient(
                colors: [
                    Color(red: 0.38, green: 0.28, blue: 0.48),
                    Color(red: 0.22, green: 0.16, blue: 0.32),
                    Color(red: 0.30, green: 0.22, blue: 0.40),
                    Color(red: 0.18, green: 0.12, blue: 0.26),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: [
                    Color(white: 0.72),
                    Color(white: 0.58),
                    Color(white: 0.64),
                    Color(white: 0.52),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var modernBarBackground: some View {
        if featherTreatment.usesBlueMondayChrome {
            LinearGradient(
                colors: [
                    Color(white: 0.96),
                    Color(white: 0.86),
                    Color(white: 0.74),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if featherTreatment == .pinkMartini {
            LinearGradient(
                colors: [
                    Color(red: 0.90, green: 0.79, blue: 0.84),
                    Color(red: 0.82, green: 0.67, blue: 0.73),
                    Color(red: 0.72, green: 0.53, blue: 0.61),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if featherTreatment.usesGonzoChrome {
            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.86, blue: 0.72),
                    Color(red: 0.84, green: 0.76, blue: 0.58),
                    Color(red: 0.76, green: 0.66, blue: 0.48),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if featherTreatment.usesPurpleChrome {
            LinearGradient(
                colors: [
                    Color(red: 0.34, green: 0.24, blue: 0.44),
                    Color(red: 0.24, green: 0.16, blue: 0.34),
                    Color(red: 0.16, green: 0.10, blue: 0.24),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: isDark
                    ? [
                        Color(red: 0.28, green: 0.28, blue: 0.28),
                        Color(red: 0.14, green: 0.14, blue: 0.14),
                        Color(red: 0.10, green: 0.10, blue: 0.10),
                    ]
                    : [Color(white: 0.96), Color(white: 0.90), Color(white: 0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Shared

    private func artwork(for track: Track, size: CGFloat) -> some View {
        ArtworkThumbnailView(
            reference: ArtworkReference.resolved(for: track),
            pointSize: CGSize(width: size, height: size),
            accessibilityLabel: "Album artwork for \(track.audioCDMetadata(at: discogsClock.now).album)",
            placeholderColor: SongbirdTheme.lcdTextColor(for: colorScheme).opacity(0.12)
        )
    }

    private func flatWellButton(
        _ systemName: String,
        size: CGFloat,
        iconSize: CGFloat,
        glyphOffset: CGFloat = 0,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let title = controlTitle(for: systemName)
        let usesSourceWell = isGlass == false && featherTreatment.usesBlueControlRims
        let usesPinkWell = isGlass == false && featherTreatment.usesDarkControlWells
        let usesGoldWell = isGlass == false && featherTreatment.usesGoldControlRims
        let usesVioletWell = isGlass == false && featherTreatment.usesPurpleControlRims
        let usesDarkWell = isDark || usesPinkWell || usesVioletWell
        let wellColors: [Color] = isGlass
            ? [Color.white.opacity(0.14), Color.white.opacity(0.22)]
            : usesPinkWell
                ? [
                    Color(red: 0.20, green: 0.055, blue: 0.12),
                    Color(red: 0.38, green: 0.13, blue: 0.23),
                ]
                : usesVioletWell
                    ? [
                        Color(red: 0.14, green: 0.08, blue: 0.22),
                        Color(red: 0.26, green: 0.16, blue: 0.38),
                    ]
                : usesGoldWell
                    ? [Color(red: 0.92, green: 0.86, blue: 0.70), Color(red: 0.78, green: 0.68, blue: 0.46)]
                : usesSourceWell
                    ? [Color(white: 0.94), Color(white: 0.66)]
                : isDark
                    ? [Color(white: 0.12), Color(white: 0.20)]
                    : [Color(white: 0.78), Color(white: 0.88)]
        let wellGlyph = usesPinkWell
            ? Color(red: 0.96, green: 0.80, blue: 0.87)
            : usesVioletWell
                ? Color(red: 0.88, green: 0.78, blue: 0.96)
            : usesGoldWell
                ? Color(red: 0.22, green: 0.18, blue: 0.10)
            : usesSourceWell
                ? Color(red: 0.13, green: 0.15, blue: 0.17)
            : (isGlass ? .white : textColor)
        return Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: wellColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: isGlass
                                ? [
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0.28),
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.35)
                                ]
                                : usesSourceWell
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
                                    Color.black.opacity(usesDarkWell ? 0.65 : 0.28)
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
                    .foregroundStyle(tint ?? wellGlyph)
                    .offset(x: glyphOffset)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
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

    private func toggleFavorite() {
        guard let track = playbackPresentation.currentTrack else { return }
        let isLoved = librarySnapshots.trackSnapshot(id: track.id)?.isLoved ?? false
        libraryActions.setTrackLoved(!isLoved, trackIDs: [track.id])
    }

    private var favoriteAccessibilityActionName: String {
        guard let track = playbackPresentation.currentTrack else { return "Add to Favorites" }
        return (librarySnapshots.trackSnapshot(id: track.id)?.isLoved ?? false)
            ? "Remove from Favorites"
            : "Add to Favorites"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

}

/// Behind-window vibrancy for the Glass mini player (Apple Music–style).
private struct MiniPlayerVisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}
