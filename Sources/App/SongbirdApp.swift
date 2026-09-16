import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import SongbirdLib

@main
struct SongbirdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var session: PlaybackSession
    @StateObject private var opticalDiscs: OpticalDiscService
    @StateObject private var librarySnapshots: LibrarySnapshotStore
    @StateObject private var libraryHealth: LibraryHealthProjectionStore
    @StateObject private var albumProjectionStore: LibraryAlbumProjectionStore
    @StateObject private var libraryNavigation: LibraryNavigationCoordinator
    @StateObject private var libraryActions: LibraryItemActionHandler
    @StateObject private var librarySearch = LibrarySearchCoordinator()
    @State private var sidebarShown = true
    @State private var nowPlayingPaneShown = false
    @State private var showingAbout = false
    @AppStorage(SongbirdThemeID.storageKey) private var themeID = SongbirdThemeID.blueMonday.rawValue
    @AppStorage("miniPlayer.floatOnTop") private var miniFloatOnTop = false
    @AppStorage(MiniPlayerStyle.storageKey) private var miniPlayerStyle = MiniPlayerStyle.modern.rawValue
    @AppStorage(PlayerWindowMode.miniModeKey) private var miniMode = false
    @AppStorage("cascadeFilter.visible") private var cascadeVisible = true
    @AppStorage(TrackTableColumnPrefs.storageKey) private var columnPrefsRaw = TrackTableColumnPrefs.encode(TrackTableColumnPrefs.defaults)
    @AppStorage(PlayerBarPlacement.storageKey) private var playerBarPlacement = PlayerBarPlacement.top.rawValue
    private let isUsabilityTesting: Bool
    private let startsPastImportSetup: Bool

    private var selectedTheme: SongbirdThemeID {
        SongbirdThemeID.resolved(rawValue: themeID)
    }

    private var themeAccent: Color {
        switch SongbirdThemeID.resolved(rawValue: themeID) {
        case .blueMonday:
            return SongbirdThemePalette.blueMondayAccent
        case .musicLight:
            return Color(red: 0.98, green: 0.12, blue: 0.25)
        case .musicDark:
            return Color(red: 1.0, green: 0.22, blue: 0.38)
        case .muse:
            return SongbirdThemePalette.museAccent
        case .terminal:
            return SongbirdThemePalette.terminalAccent
        default:
            return Color(white: 0.45)
        }
    }

    private var columnPrefs: [TrackColumnPref] {
        TrackTableColumnPrefs.decode(columnPrefsRaw)
    }

    init() {
        SongbirdDockIconPreference.migrateLegacyBlueMondaySourceChoiceIfNeeded()
        SongbirdThemeID.migrateLegacySelectionIfNeeded()
        let environment = ProcessInfo.processInfo.environment
        let infoDictionary = Bundle.main.infoDictionary ?? [:]
        isUsabilityTesting = SongbirdUIRuntime.isTesting(
            environment: environment,
            infoDictionary: infoDictionary
        )
        startsPastImportSetup = SongbirdUIRuntime.importSetupIsCompleted(
            environment: environment,
            infoDictionary: infoDictionary
        )
        let observesPhysicalDiscs = !isUsabilityTesting
        _opticalDiscs = StateObject(wrappedValue: OpticalDiscService(startsObserving: observesPhysicalDiscs))
        let session = PlaybackSession()
        let snapshots = LibrarySnapshotStore(
            modelContainer: MediaLibrary.shared.container,
            startsImmediately: true,
            artworkService: ArtworkThumbnailService.shared
        )
        let navigation = LibraryNavigationCoordinator()
        _session = StateObject(wrappedValue: session)
        _librarySnapshots = StateObject(wrappedValue: snapshots)
        _libraryHealth = StateObject(wrappedValue: LibraryHealthProjectionStore(snapshots: snapshots))
        _albumProjectionStore = StateObject(wrappedValue: LibraryAlbumProjectionStore())
        _libraryNavigation = StateObject(wrappedValue: navigation)
        _libraryActions = StateObject(wrappedValue: LibraryItemActionHandler(
            modelContainer: MediaLibrary.shared.container,
            playbackSession: session,
            librarySnapshots: snapshots,
            navigation: navigation
        ))
    }

    var body: some Scene {
        WindowGroup("Songbird", id: "main-player") {
            MainView(sidebarShown: $sidebarShown, nowPlayingPaneShown: $nowPlayingPaneShown)
                .frame(minWidth: PlayerWindowMetrics.mainMinimumWidth, alignment: .topLeading)
                .ignoresSafeArea(.container, edges: .top)
                .environmentObject(session.engine)
                .environmentObject(session)
                .environmentObject(session.engine.activity)
                .environmentObject(session.clock)
                .environmentObject(session.volumeState)
                .environmentObject(session.presentation)
                .environmentObject(session.queue)
                .environmentObject(session.audioOutput)
                .environmentObject(LibraryStatus.shared.importProgress)
                .environmentObject(LibraryStatus.shared.selection)
                .environmentObject(LibraryStatus.shared.summary)
                .environmentObject(LibraryStatus.shared.notices)
                .environmentObject(librarySnapshots)
                .environmentObject(libraryHealth)
                .environmentObject(albumProjectionStore)
                .environmentObject(libraryNavigation)
                .environmentObject(libraryActions)
                .environmentObject(librarySearch)
                .environmentObject(opticalDiscs)
                .modelContainer(MediaLibrary.shared.container)
                .preferredColorScheme(selectedTheme.appearance.preferredColorScheme)
                .tint(themeAccent)
                .fontDesign(selectedTheme == .terminal ? .monospaced : nil)
                .background(WindowConfigurator(
                    autosaveName: "SongbirdMain",
                    isMain: true,
                    sidebarShown: sidebarShown,
                    rightPaneShown: nowPlayingPaneShown
                ))
                .background(OpenWindowBridge())
                .id(themeID)
                .onAppear {
                    appDelegate.session = session
                    SongbirdDockIconManager.apply(for: selectedTheme)
                    if isUsabilityTesting == false {
                        LibraryFolderWatcher.shared.applySettingsFromDefaults()
                        ArtworkMaintenance.startIfNeeded(in: MediaLibrary.shared.container)
                    }
                    if let startupError = MediaLibrary.shared.startupError {
                        LibraryStatus.shared.showPlaybackError(startupError)
                    }
                    if startsPastImportSetup == false,
                       !UserDefaults.standard.bool(forKey: ImportSetupView.completedKey) {
                        DispatchQueue.main.async {
                            ImportSetupWindowPresenter.show()
                        }
                    }
                }
                .task {
                    _ = await AlbumRelationshipMaintenance.runIfNeeded(
                        in: MediaLibrary.shared.container
                    )
                }
                .task {
                    guard isUsabilityTesting == false else { return }
                    do {
                        try await LastFMCredentialMigration.migrateIfNeeded()
                    } catch {
                        LibraryStatus.shared.showNotice(
                            "Credential migration needs attention: \(error.localizedDescription)",
                            severity: .warning
                        )
                    }
                }
                .task(id: librarySnapshots.snapshot.revision) {
                    await albumProjectionStore.update(from: librarySnapshots.snapshot)
                }
                .onChange(of: themeID) { _, newThemeID in
                    SongbirdDockIconManager.apply(
                        for: SongbirdThemeID.resolved(rawValue: newThemeID)
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: .showAbout)) { _ in
                    showingAbout = true
                }
                .sheet(isPresented: $showingAbout) {
                    AboutSongbirdView()
                }
                .background(ResumePlaybackOnLaunch(engine: session.engine))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1090, height: 728)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Songbird") {
                    NotificationCenter.default.post(name: .showAbout, object: nil)
                }
                if DiscogsUsabilityFixture.isEnabled {
                    Button("Discogs Fixture…") {
                        DiscogsUsabilityFixture.show(context: MediaLibrary.shared.container.mainContext,
                            actions: libraryActions)
                    }
                }
            }

            CommandGroup(after: .newItem) {
                Button("Import Files…") {
                    NSApp.sendAction(#selector(AppDelegate.openFiles(_:)), to: nil, from: nil)
                }

                Button("Import Library…") {
                    ImportSetupWindowPresenter.show()
                }

                Divider()

                Button("Scan Folder…") {
                    scanFolder(preferSaved: true)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Scan Other Folder…") {
                    scanFolder(preferSaved: false)
                }

                Divider()

                Button("Analyze BPM for Library") {
                    libraryActions.reanalyzeBPM()
                }
            }

            LibraryEditingCommands()

            CommandMenu("Controls") {
                Button(session.engine.status == .playing ? "Pause" : "Play") {
                    session.engine.togglePlayPause()
                }
                .keyboardShortcut("p", modifiers: .command)

                Divider()

                Button("Next") { session.engine.playNext() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous") { session.engine.playPrevious() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)

                Divider()

                Button("Volume Up") {
                    session.engine.setVolume(session.engine.volume + 0.05)
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Volume Down") {
                    session.engine.setVolume(session.engine.volume - 0.05)
                }
                .keyboardShortcut(.downArrow, modifiers: .command)

                Divider()

                Toggle("Shuffle", isOn: Binding(
                    get: { session.queue.shuffleEnabled },
                    set: { session.queue.shuffleEnabled = $0 }
                ))
                .keyboardShortcut("s", modifiers: [.command, .option])

                Picker("Repeat", selection: Binding(
                    get: { session.queue.repeatMode },
                    set: { session.queue.repeatMode = $0 }
                )) {
                    Text("Off").tag(PlaybackQueue.RepeatMode.off)
                    Text("All").tag(PlaybackQueue.RepeatMode.all)
                    Text("One").tag(PlaybackQueue.RepeatMode.one)
                }

                Divider()

                Toggle("Stop After Current", isOn: Binding(
                    get: { session.engine.stopAfterCurrent },
                    set: { session.engine.stopAfterCurrent = $0 }
                ))

                Picker("Sleep Timer", selection: Binding(
                    get: { session.engine.sleepTimerMinutes ?? 0 },
                    set: { minutes in
                        if minutes == 0 { session.engine.clearSleepTimer() }
                        else { session.engine.setSleepTimer(minutes: minutes) }
                    }
                )) {
                    Text("Off").tag(0)
                    Text("15 Minutes").tag(15)
                    Text("30 Minutes").tag(30)
                    Text("45 Minutes").tag(45)
                    Text("60 Minutes").tag(60)
                }

                Divider()

                Button("Show Lyrics") {
                    NotificationCenter.default.post(name: .showLyrics, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
            }

            // Use CommandGroup (not CommandMenu("View")) so items join the system
            // View menu instead of creating a duplicate second View menu.
            CommandGroup(after: .sidebar) {
                Button(sidebarShown ? "Hide Sidebar" : "Show Sidebar") {
                    withAnimation { sidebarShown.toggle() }
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Button(cascadeVisible ? "Hide Browser" : "Show Browser") {
                    cascadeVisible.toggle()
                }
                .keyboardShortcut("b", modifiers: [.command, .option])

                Button(nowPlayingPaneShown ? "Hide Now Playing Pane" : "Show Now Playing Pane") {
                    withAnimation { nowPlayingPaneShown.toggle() }
                }
                .keyboardShortcut("p", modifiers: [.command, .option])

                Divider()

                Picker("Player Bar", selection: $playerBarPlacement) {
                    Text("Top").tag(PlayerBarPlacement.top.rawValue)
                    Text("Bottom").tag(PlayerBarPlacement.bottom.rawValue)
                }

                Menu("Columns") {
                    ForEach(columnPrefs) { pref in
                        if let column = TrackSortColumn(rawValue: pref.id), column.isSupported {
                            Toggle(column.label, isOn: columnVisibilityBinding(column))
                            .disabled(column == .title)
                        }
                    }
                    Divider()
                    Button("Reset Columns") {
                        NotificationCenter.default.post(name: .resetTrackColumns, object: nil)
                    }
                }

                Divider()

                Picker("Feathers", selection: $themeID) {
                    Section("Classic") {
                        ForEach(SongbirdThemeID.allCases.filter(\.isClassicFeather)) { theme in
                            Text(theme.displayName).tag(theme.rawValue)
                        }
                    }
                    Section("New") {
                        ForEach(SongbirdThemeID.allCases.filter { !$0.isClassicFeather }) { theme in
                            Text(theme.displayName).tag(theme.rawValue)
                        }
                    }
                }
            }

            CommandGroup(after: .windowSize) {
                Button(miniMode ? "Show Full Player" : "Switch to Mini Player") {
                    if miniMode {
                        NotificationCenter.default.post(name: .showMainPlayer, object: nil)
                    } else {
                        openMiniPlayer()
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .option])

                Toggle("Stay on Top", isOn: $miniFloatOnTop)
            }
        }

        Window("Mini Player", id: "mini-player") {
            MiniPlayerView()
                .environmentObject(session.engine)
                .environmentObject(session)
                .environmentObject(session.clock)
                .environmentObject(session.volumeState)
                .environmentObject(session.presentation)
                .environmentObject(session.queue)
                .environmentObject(session.audioOutput)
                .environmentObject(librarySnapshots)
                .environmentObject(libraryNavigation)
                .environmentObject(libraryActions)
                .modelContainer(MediaLibrary.shared.container)
                .preferredColorScheme(selectedTheme.appearance.preferredColorScheme)
                .tint(themeAccent)
                .fontDesign(selectedTheme == .terminal ? .monospaced : nil)
                .background(
                    MiniPlayerWindowConfigurator(
                        autosaveName: "SongbirdMiniPlayer.v5",
                        floatOnTop: miniFloatOnTop,
                        style: MiniPlayerStyle(rawValue: miniPlayerStyle) ?? .modern
                    )
                )
                .modifier(MiniPlayerContainerBackground())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.trailing)
        .defaultSize(width: 520, height: 32)

        Settings {
            SettingsView()
                .environmentObject(session.engine)
                .environmentObject(librarySnapshots)
                .environmentObject(albumProjectionStore)
                .environmentObject(libraryNavigation)
                .modelContainer(MediaLibrary.shared.container)
                .background(SettingsWindowConfigurator())
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 560)
    }

    private func openMiniPlayer() {
        NotificationCenter.default.post(name: .openMiniPlayer, object: nil)
    }

    private func columnVisibilityBinding(_ column: TrackSortColumn) -> Binding<Bool> {
        Binding(
            get: {
                column == .title
                    || columnPrefs.first(where: { $0.id == column.rawValue })?.visible == true
            },
            set: { visible in
                guard column != .title else { return }
                var preferences = columnPrefs
                guard let index = preferences.firstIndex(where: { $0.id == column.rawValue }) else { return }
                preferences[index].visible = visible
                columnPrefsRaw = TrackTableColumnPrefs.encode(preferences)
            }
        )
    }

    private func scanFolder(preferSaved: Bool) {
        LibraryFolderWatcher.migrateLegacyPathIfNeeded()
        let saved = LibraryFolderWatcher.folderPaths
        if preferSaved, !saved.isEmpty {
            let urls = saved
                .filter { FileManager.default.fileExists(atPath: $0) }
                .map { URL(fileURLWithPath: $0) }
            if !urls.isEmpty {
                Task { @MainActor in
                    let scanner = LibraryScanner(modelContainer: MediaLibrary.shared.container)
                    await scanner.scanFolders(urls)
                }
                return
            }
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in
                let scanner = LibraryScanner(modelContainer: MediaLibrary.shared.container)
                await scanner.scanFolders(panel.urls)
            }
        }
    }
}

/// Observe focused commands here so a view publishing new command closures does
/// not rebuild the app's windows and publish those closures again.
private struct LibraryEditingCommands: Commands {
    @FocusedValue(\.trackTableCommands) private var trackTableCommands
    @FocusedValue(\.librarySearchCommands) private var librarySearchCommands

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            if let trackTableCommands {
                Button("Select All") {
                    trackTableCommands.selectAll()
                }
                .keyboardShortcut("a", modifiers: .command)
            }
        }

        CommandGroup(after: .textEditing) {
            if let librarySearchCommands {
                Button("Find…") {
                    librarySearchCommands.focusSearch()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}

/// One-shot resume of the last track after the library is queryable.
private struct ResumePlaybackOnLaunch: View {
    let engine: PlaybackEngine
    @Environment(\.modelContext) private var modelContext
    @State private var didAttempt = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task { attemptResume() }
    }

    private func attemptResume() {
        guard !didAttempt,
              let path = UserDefaults.standard.string(forKey: PlaybackSettings.lastTrackPathKey),
              path.isEmpty == false else { return }
        didAttempt = true
        var descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.path == path })
        descriptor.fetchLimit = 1
        do {
            guard let track = try modelContext.fetch(descriptor).first else { return }
            engine.resumeLastTrackIfNeeded(from: [track])
        } catch {
            LibraryStatus.shared.showNotice(
                "Could not restore the last track: \(error.localizedDescription)",
                severity: .warning
            )
        }
    }
}

private struct OpenWindowBridge: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                // Restore mini-only mode after relaunch if we quit while mini was active.
                guard PlayerWindowMode.isMiniMode else { return }
                DispatchQueue.main.async {
                    openWindow(id: "mini-player")
                    PlayerWindowMode.enterMiniMode()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMiniPlayer)) { _ in
                openWindow(id: "mini-player")
                // Defer hide so the mini window can finish opening.
                DispatchQueue.main.async {
                    PlayerWindowMode.enterMiniMode()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showMainPlayer)) { _ in
                PlayerWindowMode.enterFullMode(closeMini: false)
                dismissWindow(id: "mini-player")
                // Fallback if dismissWindow doesn't close an already-open mini.
                DispatchQueue.main.async {
                    for window in PlayerWindowMode.miniWindows() {
                        window.close()
                    }
                }
            }
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView) }
    }

    private func configure(_ view: NSView) {
        guard let window = view.window else { return }
        window.identifier = NSUserInterfaceItemIdentifier("songbird-settings")
        // The Settings scene owns restoration. Assigning an AppKit autosave name
        // after this representable attaches restores a second frame after the
        // window is already visible, which makes Preferences jump on opening.
        window.styleMask.insert(.resizable)
        window.contentMinSize = NSSize(width: 680, height: 480)
    }
}

/// Makes the window title bar transparent so the sidebar sits under the traffic lights.
private struct WindowConfigurator: NSViewRepresentable {
    var autosaveName: String
    var isMain: Bool
    var sidebarShown = false
    var rightPaneShown = false

    func makeCoordinator() -> PlayerWindowConfigurationOwner {
        PlayerWindowConfigurationOwner()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view, owner: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView, owner: context.coordinator) }
    }

    private func configure(_ view: NSView, owner: PlayerWindowConfigurationOwner) {
        guard let window = view.window else { return }
        owner.configureMain(
            window,
            autosaveName: autosaveName,
            isMain: isMain,
            sidebarShown: sidebarShown,
            rightPaneShown: rightPaneShown
        ) {
            clearTitlebarBackground(window)
        }
    }

    /// The titlebar container stays opaque by default even with
    /// `titlebarAppearsTransparent`, which hides a full-height sidebar.
    private func clearTitlebarBackground(_ window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton) else { return }

        var node: NSView? = closeButton
        while let current = node {
            let className = String(describing: type(of: current))

            if className.contains("NSTitlebarContainerView") {
                current.wantsLayer = true
                current.layer?.backgroundColor = NSColor.clear.cgColor
                for subview in current.subviews {
                    let subName = String(describing: type(of: subview))
                    // Fade only the fill / vibrancy layer — keep the button strip opaque.
                    if subName.contains("NSVisualEffectView"), let effect = subview as? NSVisualEffectView {
                        effect.alphaValue = 0
                    } else if subName.contains("NSTitlebarView") {
                        subview.wantsLayer = true
                        subview.layer?.backgroundColor = NSColor.clear.cgColor
                        for nested in subview.subviews {
                            if String(describing: type(of: nested)).contains("NSVisualEffectView"),
                               let effect = nested as? NSVisualEffectView {
                                effect.alphaValue = 0
                            }
                        }
                    }
                }
            }

            if className.contains("NSThemeFrame") { break }
            node = current.superview
        }
    }
}

/// Clears SwiftUI’s default window fill so mini chrome owns every pixel.
private struct MiniPlayerContainerBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.containerBackground(.clear, for: .window)
        } else {
            content.background(Color.clear)
        }
    }
}

private struct MiniPlayerWindowConfigurator: NSViewRepresentable {
    var autosaveName: String
    var floatOnTop: Bool
    var style: MiniPlayerStyle

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView, coordinator: context.coordinator) }
    }

    private func configure(_ view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }
        coordinator.configurationOwner.configureMini(
            window, autosaveName: autosaveName, floatOnTop: floatOnTop, style: style
        )
        coordinator.attach(to: window)
    }


    @MainActor
    final class Coordinator {
        let configurationOwner = PlayerWindowConfigurationOwner()
        private var observer: NSObjectProtocol?
        private var keyMonitor: Any?
        private weak var window: NSWindow?

        func attach(to window: NSWindow) {
            guard self.window !== window else { return }
            detach()
            self.window = window
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                // Closing mini restores the full player.
                Task { @MainActor in
                    if PlayerWindowMode.isMiniMode {
                        NotificationCenter.default.post(name: .showMainPlayer, object: nil)
                    }
                }
            }
            // Borderless windows don't always honor File > Close; handle ⌘W directly.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let isTrackedWindowKey = MainActor.assumeIsolated {
                    self?.window?.isKeyWindow == true
                }
                guard isTrackedWindowKey,
                      event.modifierFlags.contains(.command),
                      !event.modifierFlags.contains(.shift),
                      !event.modifierFlags.contains(.option),
                      !event.modifierFlags.contains(.control),
                      event.charactersIgnoringModifiers == "w" else {
                    return event
                }
                // Don't rely on the orderOut main window receiving notifications.
                MainActor.assumeIsolated {
                    PlayerWindowMode.enterFullMode(closeMini: true)
                    NotificationCenter.default.post(name: .showMainPlayer, object: nil)
                }
                return nil
            }
        }

        func detach() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            window = nil
        }

        isolated deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
        }
    }
}
