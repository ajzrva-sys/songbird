import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SwiftData

public struct SettingsView: View {
    @State private var selection: SettingsSection = .appearance
    @AppStorage(SongbirdThemeID.storageKey) private var themeID = SongbirdThemeID.blueMonday.rawValue
    @AppStorage(PlayerBarPlacement.storageKey) private var playerBarPlacement = PlayerBarPlacement.top.rawValue
    @AppStorage(MiniPlayerStyle.storageKey) private var miniPlayerStyle = MiniPlayerStyle.modern.rawValue
    @AppStorage("miniPlayer.floatOnTop") private var miniPlayerFloatOnTop = false
    @AppStorage(AlbumGridSettings.artworkSizeKey)
    private var albumArtworkSize = AlbumGridSettings.defaultArtworkSize
    @AppStorage(AlbumGridSettings.gridSpacingKey)
    private var albumGridSpacing = AlbumGridSettings.defaultGridSpacing
    @AppStorage(TrackTablePresentation.storageKey)
    private var tablePresentationRaw = TrackTablePresentation.classic.rawValue
    @State private var libraryFolderConfigurations: [LibraryFolderConfiguration] = []
    @State private var folderPendingForget: LibraryFolderConfiguration?
    @AppStorage(PlaybackSettings.volumeLimitKey) private var volumeLimit = 1.0
    @AppStorage(PlaybackSettings.resumeOnLaunchKey) private var resumeOnLaunch = true
    @AppStorage(PlaybackSettings.rememberPositionKey) private var rememberPosition = true
    @AppStorage(PlaybackSettings.crossfadeSecondsKey) private var crossfadeSeconds = 0.0
    @AppStorage(LibrarySettings.writeTagsToFilesKey) private var writeTagsToFiles = false
    @State private var duplicateTasks = ViewTaskSlot()
    @State private var duplicateProgress = 0
    @State private var duplicateTotal = 0
    @State private var duplicatePhase = LibraryOperationPhase.idle
    @State private var maintenanceTasks = ViewTaskSlot()
    @State private var maintenanceProgress: LibraryMaintenanceProgress?
    @State private var maintenancePhase = LibraryOperationPhase.idle
    @State private var exampleAlbumIDs: [String] = []
    @State private var showingResetConfirmation = false
    @State private var resetTask: Task<Void, Never>?
    @State private var resetPhase = LibraryOperationPhase.idle

    @EnvironmentObject private var playbackEngine: PlaybackEngine
    @EnvironmentObject private var librarySnapshots: LibrarySnapshotStore
    @EnvironmentObject private var albumProjectionStore: LibraryAlbumProjectionStore
    @EnvironmentObject private var libraryNavigation: LibraryNavigationCoordinator
    @EnvironmentObject private var libraryActions: LibraryItemActionHandler
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    private let folderSelectionProvider: any LibraryFolderSelectionProviding
    private let folderSetupCoordinator: LibraryFolderSetupCoordinator

    public init(
        folderSelectionProvider: (any LibraryFolderSelectionProviding)? = nil,
        folderSetupCoordinator: LibraryFolderSetupCoordinator? = nil
    ) {
        self.folderSelectionProvider = folderSelectionProvider
            ?? LibraryFolderSelectionProviderFactory.make()
        self.folderSetupCoordinator = folderSetupCoordinator ?? .live
    }

    private var libraryFolders: [String] {
        libraryFolderConfigurations.map(\.path)
    }

    private var maintenanceIsActive: Bool {
        maintenancePhase == .running || maintenancePhase == .cancelling
    }

    private var duplicateIsActive: Bool {
        duplicatePhase == .running || duplicatePhase == .cancelling
    }

    private var resetIsActive: Bool {
        resetPhase == .running
    }

    private var normalizedAlbumArtworkSize: Double {
        AlbumGridSettings.normalizedArtworkSize(albumArtworkSize)
    }

    private var albumArtworkSizeBinding: Binding<Double> {
        Binding(
            get: { normalizedAlbumArtworkSize },
            set: { albumArtworkSize = AlbumGridSettings.normalizedArtworkSize($0) }
        )
    }

    private var normalizedAlbumGridSpacing: Double {
        AlbumGridSettings.normalizedGridSpacing(albumGridSpacing)
    }

    private var albumGridSpacingBinding: Binding<Double> {
        Binding(
            get: { normalizedAlbumGridSpacing },
            set: { albumGridSpacing = AlbumGridSettings.normalizedGridSpacing($0) }
        )
    }

    private var exampleAlbums: [LibraryAlbumGroupSnapshot] {
        let groupsByID = Dictionary(
            uniqueKeysWithValues: albumProjectionStore.groups.map { ($0.id, $0) }
        )
        return exampleAlbumIDs.compactMap { groupsByID[$0] }
    }

    public var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            selectedDetail
                .navigationTitle(selection.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("settings.root")
        .frame(minWidth: 680, minHeight: 480)
        .onAppear {
            maintenanceTasks.activate()
            duplicateTasks.activate()
            libraryFolderConfigurations = LibraryFolderConfigurationStore.load()
            refreshExampleAlbums()
        }
        .onChange(of: albumProjectionStore.projectionRevision) { _, _ in
            refreshExampleAlbums()
        }
        .onDisappear {
            invalidateLibraryTasks()
        }
        .confirmationDialog(
            "Reset Library?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset and Re-import", role: .destructive) {
                resetLibrary(reimport: true)
            }
            Button("Reset Only", role: .destructive) {
                resetLibrary(reimport: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes all music, favorites, personal playlists, and playback history "
                    + "from Songbird. Audio files, library folders, and preferences are not deleted."
            )
        }
        .confirmationDialog(
            "Forget Library Folder?",
            isPresented: Binding(
                get: { folderPendingForget != nil },
                set: { if $0 == false { folderPendingForget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Forget Folder", role: .destructive) {
                if let configuration = folderPendingForget {
                    forgetFolder(configuration.path)
                }
                folderPendingForget = nil
            }
            Button("Cancel", role: .cancel) { folderPendingForget = nil }
        } message: {
            Text("Songbird will stop monitoring this folder. Imported library tracks and audio files remain unchanged.")
        }
    }

    @ViewBuilder
    private var selectedDetail: some View {
        switch selection {
        case .appearance:
            appearanceTab
        case .library:
            libraryTab
        case .playback:
            playbackTab
        case .audioDiagnostics:
            audioDiagnosticsTab
        case .lastFM:
            lastFMTab
        case .discogs:
            discogsTab
        }
    }

    private var appearanceTab: some View {
        Form {
            Picker("Theme", selection: $themeID) {
                Section("Classic Feathers") {
                    ForEach(SongbirdThemeID.allCases.filter(\.isClassicFeather)) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                Section("New Feathers") {
                    ForEach(SongbirdThemeID.allCases.filter { !$0.isClassicFeather }) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
            }
            Text("Themes style chrome, faceplate, and list selection colors.")
                .font(.caption)
                .foregroundStyle(.secondary)

            let selectedTheme = SongbirdThemeID.resolved(rawValue: themeID)
            if selectedTheme.dockIconChoices.isEmpty == false {
                FeatherDockIconPicker(theme: selectedTheme)
                    .id(selectedTheme)
            }

            Section("Albums") {
                LabeledContent("Artwork Size") {
                    Text("\(Int(normalizedAlbumArtworkSize)) × \(Int(normalizedAlbumArtworkSize))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Slider(
                    value: albumArtworkSizeBinding,
                    in: AlbumGridSettings.artworkSizeRange,
                    step: AlbumGridSettings.artworkSizeStep
                ) {
                    Text("Album artwork size")
                } minimumValueLabel: {
                    Image(systemName: "photo")
                        .font(.caption2)
                } maximumValueLabel: {
                    Image(systemName: "photo")
                        .font(.title2)
                }

                LabeledContent("Grid Spacing") {
                    Text("\(Int(normalizedAlbumGridSpacing)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Slider(
                    value: albumGridSpacingBinding,
                    in: AlbumGridSettings.gridSpacingRange,
                    step: AlbumGridSettings.gridSpacingStep
                ) {
                    Text("Album grid spacing")
                } minimumValueLabel: {
                    Image(systemName: "square.grid.2x2")
                        .font(.caption2)
                } maximumValueLabel: {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.title2)
                }
            }

            Section("Library Table") {
                Picker("Density", selection: $tablePresentationRaw) {
                    ForEach(TrackTablePresentation.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                let resolved = TrackTablePresentation.resolved(from: tablePresentationRaw)
                switch resolved {
                case .classic:
                    Text("Compact rows without per-row artwork.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .comfortable:
                    Text("Standard rows with artwork thumbnails.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Example") {
                if exampleAlbums.isEmpty {
                    Text("Albums with artwork will appear here.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        HStack(
                            alignment: .top,
                            spacing: CGFloat(normalizedAlbumGridSpacing)
                        ) {
                            ForEach(exampleAlbums) { album in
                                AlbumCard(
                                    title: album.title,
                                    artist: album.artist,
                                    artworkSize: CGFloat(normalizedAlbumArtworkSize),
                                    displayDetail: nil,
                                    discCount: album.discCount,
                                    isFavorite: album.isFavorite,
                                    artworkReference: album.artworkReference,
                                    textColor: SongbirdTheme.text(for: colorScheme),
                                    secondaryTextColor: SongbirdTheme.secondaryText(for: colorScheme),
                                    colorScheme: colorScheme
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .scrollIndicators(.hidden)
                }
            }

            Picker("Player Bar Position", selection: $playerBarPlacement) {
                ForEach(PlayerBarPlacement.allCases) { placement in
                    Text(placement.displayName).tag(placement.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text("Places the full player chrome (transport and now playing) above or below the library.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Mini Player", selection: $miniPlayerStyle) {
                ForEach(MiniPlayerStyle.allCases) { style in
                    Text(style.displayName).tag(style.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text("Modern matches the main chrome. Strip is a compact themed row. Classic is brushed metal. Glass uses Apple Music–style transparency.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Stay on Top", isOn: $miniPlayerFloatOnTop)
            Text("Keeps the mini player above other windows.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    private var libraryTab: some View {
        Form {
            Section("Library Folders") {
                ForEach(libraryFolderConfigurations) { configuration in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(configuration.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            Spacer()
                            Text(folderStatus(configuration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Scan Now") { scanFolder(configuration.path) }
                            if FileManager.default.fileExists(atPath: configuration.path) {
                                Button(configuration.mode == .watching ? "Stop Watching" : "Start Watching") {
                                    toggleWatching(configuration)
                                }
                            }
                            Spacer()
                            Button("Forget Folder…", role: .destructive) {
                                folderPendingForget = configuration
                            }
                        }
                    }
                }
                HStack {
                    Button("Add & Scan Folder…") { addFolder(scan: true) }
                        .accessibilityIdentifier("usability.folder.addAndScan")
                    Button("Add Folder Without Scanning…") { addFolder(scan: false) }
                        .accessibilityIdentifier("usability.folder.addWithoutScanning")
                }
            }
            Text("Automatic watching is available only for local volumes. Forgetting a folder never removes imported tracks or audio files.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Section("Hygiene") {
                Button("Remove Missing Files…") {
                    previewMissingFiles()
                }
                .disabled(maintenanceIsActive)
                Button("Locate Missing Files…") {
                    let roots = libraryFolders
                    startMaintenance { service, progress in
                        let found = try await service.locateMissingTracks(
                            searchRoots: roots,
                            progress: progress
                        )
                        return "Relocated \(found) track(s) by filename."
                    }
                }
                .disabled(maintenanceIsActive)
                Button("Find Missing Artwork…") {
                    showDiscogsBulkReview()
                }
                Button("Fix Missing Genre…") {
                    showDiscogsGenreReview()
                }
                Button("Remove Duplicates…") {
                    analyzeDuplicates()
                }
                .disabled(duplicateIsActive)
                if duplicateIsActive {
                    ProgressView(
                        value: Double(duplicateProgress),
                        total: Double(max(duplicateTotal, 1))
                    )
                    Text(
                        duplicateTotal > 0
                            ? "Analyzing \(duplicateProgress) of \(duplicateTotal) tracks…"
                            : "Preparing duplicate analysis…"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Button(duplicatePhase == .cancelling ? "Cancelling…" : "Cancel Duplicate Analysis") {
                        duplicatePhase = .cancelling
                        duplicateTasks.cancel()
                    }
                    .disabled(duplicatePhase == .cancelling)
                }
                Button("Clean Empty Albums/Artists…") {
                    previewEmptyAlbumsAndArtists()
                }
                .disabled(maintenanceIsActive)
                Button("Relocate Folder…") {
                    relocateFolder()
                }
                .disabled(maintenanceIsActive)

                if let maintenanceProgress {
                    if let total = maintenanceProgress.total, total > 0 {
                        ProgressView(
                            value: Double(maintenanceProgress.completed),
                            total: Double(total)
                        )
                    } else {
                        ProgressView()
                    }
                    Text(maintenanceProgress.operation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(maintenancePhase == .cancelling ? "Cancelling…" : "Cancel Maintenance") {
                        maintenancePhase = .cancelling
                        maintenanceTasks.cancel()
                    }
                    .disabled(maintenancePhase == .cancelling)
                }
            }

            Section("Metadata") {
                Toggle("Write tags to audio files", isOn: $writeTagsToFiles)
                Text("When enabled, editing track metadata also writes the changes back to the audio files on disk. Requires re-scanning files for other apps to see updates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Library Data") {
                Button("Reset Library…", role: .destructive) {
                    showingResetConfirmation = true
                }
                .disabled(maintenanceIsActive || duplicateIsActive || resetIsActive)

                if resetIsActive {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Resetting library…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Clears Songbird’s catalog without deleting audio files or folder settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            maintenanceTasks.activate()
            duplicateTasks.activate()
        }
        .onDisappear { invalidateLibraryTasks() }
    }

    private var playbackTab: some View {
        Form {
            Slider(value: $volumeLimit, in: 0.5...1.0, step: 0.05) {
                Text("Volume Limit")
            } minimumValueLabel: {
                Text("50%")
            } maximumValueLabel: {
                Text("100%")
            }
            .onChange(of: volumeLimit) { _, newValue in
                playbackEngine.applyVolumeLimit(newValue)
            }
            Text("Caps output volume at \(Int(volumeLimit * 100))%.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Resume last track on launch", isOn: $resumeOnLaunch)
            Toggle("Remember playback position", isOn: $rememberPosition)

            Slider(value: $crossfadeSeconds, in: 0...12, step: 0.5) {
                Text("Crossfade")
            }
            Text(crossfadeSeconds <= 0
                  ? "Gapless handoff (no crossfade)."
                  : String(format: "Crossfade %.1fs between tracks.", crossfadeSeconds))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    private var lastFMTab: some View {
        LastFMSettingsView()
    }

    private var discogsTab: some View {
        DiscogsSettingsView()
    }

    private var audioDiagnosticsTab: some View {
        AudioDiagnosticsSettingsView()
    }

    private func addFolder(scan: Bool) {
        folderSelectionProvider.selectFolders(
            for: scan ? .addAndScan : .addWithoutScanning,
            allowsMultipleSelection: true,
            initialDirectory: nil
        ) { urls in
            guard urls.isEmpty == false else { return }
            let outcome = folderSetupCoordinator.add(urls, scanImmediately: scan)
            libraryFolderConfigurations = outcome.configurations
            if outcome.manualOnlyPaths.isEmpty == false {
                LibraryStatus.shared.showNotice(
                    "Remote or unclassified folders were added as Manual Scan Only.",
                    severity: .warning
                )
            }
        }
    }

    private func forgetFolder(_ path: String) {
        libraryFolderConfigurations.removeAll { $0.path == path }
        LibraryFolderConfigurationStore.save(libraryFolderConfigurations)
        LibraryFolderWatcher.shared.applySettingsFromDefaults()
    }

    private func scanFolder(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            LibraryStatus.shared.showNotice("That library folder is unavailable.", severity: .warning)
            return
        }
        LibraryImportCoordinator.shared.start([URL(fileURLWithPath: path, isDirectory: true)])
    }

    private func toggleWatching(_ configuration: LibraryFolderConfiguration) {
        guard let index = libraryFolderConfigurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        if configuration.mode == .watching {
            libraryFolderConfigurations[index].mode = .manualScanOnly
        } else if LibraryFolderWatchPolicy.watchablePaths([configuration.path]).isEmpty == false {
            libraryFolderConfigurations[index].mode = .watching
        } else {
            LibraryStatus.shared.showNotice(
                "Automatic watching is available only for mounted local folders. Use Scan Now for this location.",
                severity: .warning
            )
        }
        LibraryFolderConfigurationStore.save(libraryFolderConfigurations)
        LibraryFolderWatcher.shared.applySettingsFromDefaults()
    }

    private func folderStatus(_ configuration: LibraryFolderConfiguration) -> String {
        guard FileManager.default.fileExists(atPath: configuration.path) else { return "Unavailable" }
        return configuration.mode == .watching ? "Watching" : "Manual Scan Only"
    }

    private func resetLibrary(reimport: Bool) {
        guard resetTask == nil else { return }
        let configuredFolders = libraryFolders.map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        let availableFolders = configuredFolders.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }

        resetPhase = .running
        LibraryFolderWatcher.shared.stop()
        LibraryStatus.shared.cancelImport()
        LibraryResetPresentation.prepare(
            queue: playbackEngine.queue,
            navigation: libraryNavigation,
            selection: LibraryStatus.shared.selection,
            stopPlayback: playbackEngine.stop
        )

        let service = LibraryResetService(modelContainer: librarySnapshots.modelContainer)
        resetTask = Task { @MainActor in
            defer {
                LibraryFolderWatcher.shared.applySettingsFromDefaults()
                resetTask = nil
            }
            do {
                _ = try await service.reset()
                await librarySnapshots.refresh()

                if reimport {
                    guard availableFolders.isEmpty == false else {
                        resetPhase = .succeeded
                        LibraryStatus.shared.showNotice(
                            "Library reset. No configured folders were available to re-import.",
                            severity: .warning
                        )
                        return
                    }
                    let scanner = LibraryScanner(modelContainer: librarySnapshots.modelContainer)
                    await scanner.scanFolders(availableFolders)
                } else {
                    LibraryStatus.shared.showNotice(
                        "Library reset",
                        severity: .success,
                        autoDismissAfter: 3
                    )
                }
                resetPhase = .succeeded
            } catch is CancellationError {
                resetPhase = .failed
                LibraryStatus.shared.showNotice(
                    "Library reset was canceled before it began.",
                    severity: .warning
                )
            } catch {
                resetPhase = .failed
                LibraryStatus.shared.showNotice(
                    "Could not reset the library: \(error.localizedDescription)",
                    severity: .error
                )
            }
        }
    }

    private func relocateFolder() {
        guard let maintenanceLease = maintenanceTasks.lease() else { return }
        let oldPanel = NSOpenPanel()
        oldPanel.message = "Select the old library folder root"
        oldPanel.canChooseDirectories = true
        oldPanel.canChooseFiles = false
        oldPanel.begin { oldResponse in
            guard oldResponse == .OK, let oldURL = oldPanel.url else { return }
            let newPanel = NSOpenPanel()
            newPanel.message = "Select the new folder root"
            newPanel.canChooseDirectories = true
            newPanel.canChooseFiles = false
            newPanel.begin { newResponse in
                guard newResponse == .OK, let newURL = newPanel.url else { return }
                let oldPath = oldURL.path
                let newPath = newURL.path
                startMaintenance(lease: maintenanceLease) { service, progress in
                    let count = try await service.relocateTracks(
                        from: oldPath,
                        to: newPath,
                        progress: progress
                    )
                    return "Updated \(count) track path(s)."
                }
            }
        }
    }

    private func startMaintenance(
        lease: ViewTaskSlot.Lease? = nil,
        _ operation: @escaping @Sendable (
            LibraryMaintenanceService,
            LibraryMaintenanceProgressReporter
        ) async throws -> String
    ) {
        guard maintenanceIsActive == false else { return }
        maintenancePhase = .running
        maintenanceProgress = .init(operation: "Preparing library maintenance", completed: 0)
        let service = LibraryMaintenanceService(modelContainer: modelContext.container)
        let started = maintenanceTasks.start(lease: lease) {
            LibrarySnapshotStore.active?.beginBulkUpdates()
            defer {
                maintenanceProgress = nil
                LibrarySnapshotStore.active?.endBulkUpdates()
            }
            let progress = LibraryMaintenanceProgressReporter { value in
                await MainActor.run {
                    maintenanceProgress = value
                }
            }
            do {
                let message = try await operation(service, progress)
                try Task.checkCancellation()
                maintenancePhase = .succeeded
                libraryAlert(message)
            } catch is CancellationError {
                maintenancePhase = .idle
                return
            } catch {
                maintenancePhase = .failed
                LibraryStatus.shared.showNotice(
                    "Library maintenance failed: \(error.localizedDescription)",
                    severity: .error
                )
            }
        }
        if started == false {
            maintenanceProgress = nil
            maintenancePhase = .idle
        }
    }

    private func previewMissingFiles() {
        guard maintenanceIsActive == false else { return }
        maintenancePhase = .running
        let service = LibraryMaintenanceService(modelContainer: modelContext.container)
        maintenanceProgress = .init(operation: "Counting missing files", completed: 0)
        maintenanceTasks.start {
            let progress = LibraryMaintenanceProgressReporter { value in
                await MainActor.run { maintenanceProgress = value }
            }
            do {
                let preview = try await service.previewMissingTracks(progress: progress)
                try Task.checkCancellation()
                maintenanceProgress = nil
                maintenancePhase = .succeeded
                guard preview.missingTracks > 0 else {
                    if preview.unavailableTracks > 0 {
                        libraryAlert(
                            "No missing files were found. \(preview.unavailableTracks) track(s) "
                            + "are on unavailable volumes and were left untouched."
                        )
                    } else {
                        libraryAlert("No missing library files were found.")
                    }
                    return
                }

                let alert = NSAlert()
                alert.messageText = "Remove \(preview.missingTracks) Missing Track\(preview.missingTracks == 1 ? "" : "s")?"
                alert.informativeText =
                    "Songbird will remove only the library entries whose files cannot be found. "
                    + "Songbird never deletes audio files from disk. "
                    + "\(preview.unavailableTracks) track(s) on unavailable volumes will be left untouched."
                alert.addButton(withTitle: "Remove from Library")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                startMaintenance { service, progress in
                    let removed = try await service.removeMissingTracks(progress: progress)
                    return "Removed \(removed) missing track(s)."
                }
            } catch is CancellationError {
                maintenanceProgress = nil
                maintenancePhase = .idle
            } catch {
                maintenanceProgress = nil
                maintenancePhase = .failed
                LibraryStatus.shared.showPlaybackError(
                    "Could not inspect missing files: \(error.localizedDescription)"
                )
            }
        }
    }

    private func previewEmptyAlbumsAndArtists() {
        guard maintenanceIsActive == false else { return }
        maintenancePhase = .running
        let service = LibraryMaintenanceService(modelContainer: modelContext.container)
        maintenanceProgress = .init(operation: "Counting empty albums and artists", completed: 0)
        maintenanceTasks.start {
            do {
                let preview = try await service.previewOrphanAlbumsAndArtists()
                try Task.checkCancellation()
                maintenanceProgress = nil
                maintenancePhase = .succeeded
                guard preview.emptyAlbums > 0 || preview.emptyArtists > 0 else {
                    libraryAlert("No empty albums or artists were found.")
                    return
                }

                let alert = NSAlert()
                alert.messageText = "Clean Empty Albums and Artists?"
                alert.informativeText =
                    "Songbird will remove \(preview.emptyAlbums) empty album(s) and "
                    + "\(preview.emptyArtists) empty artist(s). Audio files on disk are never deleted."
                alert.addButton(withTitle: "Clean Library")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                startMaintenance { service, progress in
                    let result = try await service.removeOrphanAlbumsAndArtists(progress: progress)
                    return "Removed \(result.albums) album(s) and \(result.artists) artist(s)."
                }
            } catch is CancellationError {
                maintenanceProgress = nil
                maintenancePhase = .idle
            } catch {
                maintenanceProgress = nil
                maintenancePhase = .failed
                LibraryStatus.shared.showPlaybackError(
                    "Could not inspect empty albums and artists: \(error.localizedDescription)"
                )
            }
        }
    }

    private func analyzeDuplicates() {
        guard duplicateIsActive == false else { return }
        duplicatePhase = .running
        duplicateProgress = 0
        duplicateTotal = 0
        let container = modelContext.container
        duplicateTasks.start {
            do {
                let result = try await DuplicateAnalysisService.analyze(
                    container: container
                ) { completed, total in
                    await MainActor.run {
                        duplicateProgress = completed
                        duplicateTotal = total
                    }
                }
                try Task.checkCancellation()
                guard !result.cancelled else {
                    duplicatePhase = .idle
                    return
                }
                duplicatePhase = .succeeded
                guard result.duplicateTrackCount > 0 else {
                    libraryAlert("No duplicate tracks found.")
                    return
                }

                let alert = NSAlert()
                alert.messageText = "Remove Duplicate Tracks?"
                alert.informativeText =
                    "Songbird found \(result.groupCount) duplicate group(s). "
                    + "\(result.duplicateTrackCount) track(s) will be removed; "
                    + "the oldest library entry in each group will be kept. "
                    + "Audio files on disk are never deleted."
                alert.addButton(withTitle: "Remove Duplicates")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }

                let removed = try await DuplicateAnalysisService.removeAnalyzedDuplicates(
                    result,
                    container: container
                )
                try Task.checkCancellation()
                libraryAlert("Removed \(removed) duplicate track(s).")
            } catch is CancellationError {
                duplicatePhase = .idle
            } catch {
                duplicatePhase = .failed
                LibraryStatus.shared.showPlaybackError(
                    "Could not analyze duplicate tracks: \(error.localizedDescription)"
                )
            }
        }
    }

    private func invalidateLibraryTasks() {
        maintenanceTasks.invalidate()
        duplicateTasks.invalidate()
        maintenanceProgress = nil
        maintenancePhase = .idle
        duplicatePhase = .idle
    }

    private func libraryAlert(_ message: String) {
        LibraryStatus.shared.showNotice(
            message,
            severity: .information,
            autoDismissAfter: 4
        )
    }

    private func showDiscogsBulkReview() {
        DiscogsBulkReviewWindowPresenter.show(
            modelContext: modelContext,
            actions: libraryActions
        )
    }

    private func showDiscogsGenreReview() {
        DiscogsGenreReviewWindowPresenter.show(modelContext: modelContext, actions: libraryActions)
    }

    private func refreshExampleAlbums() {
        let candidates = albumProjectionStore.groups.filter { $0.artworkReference != nil }
        let candidateIDs = candidates.map(\.id)
        let validIDs = Set(candidateIDs)
        let retainedIDs = exampleAlbumIDs.filter { validIDs.contains($0) }
        let targetCount = min(AlbumGridExampleSelection.count, candidateIDs.count)

        if retainedIDs.count == targetCount {
            exampleAlbumIDs = retainedIDs
        } else {
            exampleAlbumIDs = AlbumGridExampleSelection.choose(from: candidateIDs)
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case library
    case playback
    case audioDiagnostics
    case lastFM
    case discogs

    var id: Self { self }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .library: return "Library"
        case .playback: return "Playback"
        case .audioDiagnostics: return "Audio Diagnostics"
        case .lastFM: return "Last.fm"
        case .discogs: return "Discogs"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: return "paintpalette"
        case .library: return "folder"
        case .playback: return "speaker.wave.2"
        case .audioDiagnostics: return "waveform.path.ecg"
        case .lastFM: return "dot.radiowaves.left.and.right"
        case .discogs: return "record.circle"
        }
    }
}

private struct AudioDiagnosticsSettingsView: View {
    @EnvironmentObject private var playbackEngine: PlaybackEngine
    @StateObject private var poller = AudioDiagnosticsPoller()

    private var snapshot: AudioDiagnosticsSnapshot { poller.snapshot }

    var body: some View {
        Form {
            Section("Output") {
                metric("State", snapshot.transitionState.displayName)
                metric("Device Rate", rate(snapshot.deviceSampleRate))
                metric("Render Callbacks", number(snapshot.renderCallbacks))
                metric("Rendered Frames", number(snapshot.renderedFrames))
            }

            Section("Decoder Buffers") {
                bufferMetric("Current", frames: snapshot.currentBufferFrames)
                bufferMetric("Incoming", frames: snapshot.incomingBufferFrames)
                bufferMetric("Pending", frames: snapshot.pendingBufferFrames)
            }

            Section("Transition") {
                metric(
                    "Progress",
                    "\(number(snapshot.transitionProgressFrames)) / "
                        + number(snapshot.transitionLengthFrames) + " frames"
                )
            }

            Section("Continuity") {
                metric("Underflow Frames", number(snapshot.underflowFrames))
                metric(
                    "Last Underflow",
                    snapshot.lastUnderflowOutputFrame.map {
                        "output frame \(number($0))"
                    } ?? "—"
                )
                metric("Cancelled / Replaced", number(snapshot.cancelledDecodedFrames))
                metric("Overflow Rejected", number(snapshot.overflowRejectedFrames))
                metric("Late Transition Loss", number(snapshot.lateTransitionFrames))
                metric("Discarded Total", number(snapshot.discardedFrames))
            }

            Section("Latency") {
                latencyMetric("Decode", snapshot.decodeLatency)
                latencyMetric("Conversion", snapshot.conversionLatency)
            }

            HStack {
                Spacer()
                Button("Reset Counters") {
                    playbackEngine.resetAudioDiagnostics()
                    poller.start {
                        playbackEngine.audioDiagnosticsSnapshot()
                    }
                }
                .disabled(!playbackEngine.supportsAudioDiagnostics)
            }

            if !playbackEngine.supportsAudioDiagnostics {
                Text("The selected playback backend does not provide audio diagnostics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            poller.start {
                playbackEngine.audioDiagnosticsSnapshot()
            }
        }
        .onDisappear { poller.stop() }
    }

    @ViewBuilder
    private func metric(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).monospacedDigit()
        }
    }

    @ViewBuilder
    private func bufferMetric(_ label: String, frames: UInt64) -> some View {
        metric(
            label,
            "\(number(frames)) frames · "
                + String(format: "%.1f ms", milliseconds(frames))
        )
    }

    @ViewBuilder
    private func latencyMetric(
        _ label: String,
        _ latency: AudioLatencyStatistics
    ) -> some View {
        metric(
            label,
            latency.sampleCount == 0
                ? "—"
                : String(
                    format: "latest %.3f · avg %.3f · max %.3f · EWMA %.3f ms (%llu)",
                    latency.latestMilliseconds,
                    latency.averageMilliseconds,
                    latency.maximumMilliseconds,
                    latency.ewmaMilliseconds,
                    latency.sampleCount
                )
        )
    }

    private func milliseconds(_ frames: UInt64) -> Double {
        guard snapshot.deviceSampleRate > 0 else { return 0 }
        return Double(frames) * 1_000 / snapshot.deviceSampleRate
    }

    private func number(_ value: UInt64) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private func rate(_ value: Double) -> String {
        value > 0 ? "\(Int(value.rounded()).formatted()) Hz" : "—"
    }
}

private extension AudioTransitionState {
    var displayName: String {
        switch self {
        case .stopped: return "Stopped"
        case .playing: return "Playing"
        case .pendingGapless: return "Pending Gapless"
        case .pendingCrossfade: return "Pending Crossfade"
        case .gaplessHandoff: return "Gapless Handoff"
        case .crossfading: return "Crossfading"
        }
    }
}
