import AppKit
import SwiftUI

public struct ImportSetupView: View {
    public static let completedKey = "songbird.importSetup.completed"
    static let folderPathKey = "songbird.importSetup.folderPath"

    private enum ImportChoice: String, CaseIterable, Identifiable {
        case folder
        case musicLibrary
        case none

        var id: String { rawValue }
    }

    @State private var choice: ImportChoice = .folder
    @State private var folderPath = Self.defaultMusicFolder.path
    @State private var keepUpdated = true
    @State private var validationMessage = ""
    @AppStorage(SongbirdThemeID.storageKey) private var themeID = SongbirdThemeID.blueMonday.rawValue
    @Environment(\.colorScheme) private var colorScheme
    private let onClose: () -> Void
    private let folderSelectionProvider: any LibraryFolderSelectionProviding
    private let folderSetupCoordinator: LibraryFolderSetupCoordinator

    private static var defaultMusicFolder: URL {
        FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music")
    }

    private static var detectedMusicMediaFolder: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Music/Music/Media.localized/Music"),
            home.appendingPathComponent("Music/Music/Media/Music"),
            home.appendingPathComponent("Music/iTunes/iTunes Media/Music"),
            home.appendingPathComponent("Music/iTunes/iTunes Music"),
        ]
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    private var palette: SongbirdThemePalette {
        SongbirdThemePalette.palette(for: selectedTheme, colorScheme: colorScheme)
    }

    private var selectedTheme: SongbirdThemeID {
        SongbirdThemeID.resolved(rawValue: themeID)
    }

    private var secondaryText: Color { palette.secondaryText }
    private var tintColor: Color {
        selectedTheme == .muse
            ? SongbirdThemePalette.museAccent
            : palette.lcdText
    }

    public init(
        onClose: @escaping () -> Void = {},
        folderSelectionProvider: (any LibraryFolderSelectionProviding)? = nil,
        folderSetupCoordinator: LibraryFolderSetupCoordinator? = nil
    ) {
        let savedPath = UserDefaults.standard.string(forKey: Self.folderPathKey)
        let watchedPath = LibraryFolderWatcher.folderPaths.first
        _folderPath = State(
            initialValue: savedPath?.isEmpty == false
                ? (savedPath ?? Self.defaultMusicFolder.path)
                : (watchedPath ?? Self.defaultMusicFolder.path)
        )
        self.onClose = onClose
        self.folderSelectionProvider = folderSelectionProvider
            ?? LibraryFolderSelectionProviderFactory.make()
        self.folderSetupCoordinator = folderSetupCoordinator ?? .live
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            options
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 440)
        .background(palette.background)
        .foregroundStyle(palette.text)
        .overlay {
            Rectangle()
                .stroke(palette.divider, lineWidth: 1)
        }
        .preferredColorScheme(selectedTheme.appearance.preferredColorScheme)
        .tint(tintColor)
        .id(themeID)
        .onChange(of: folderPath) { _, newPath in
            UserDefaults.standard.set(newPath, forKey: Self.folderPathKey)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import Media")
                .font(.title2.bold())
            Text("Choose what Songbird should import now. You can add more music later from the File menu.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Import source", selection: $choice) {
                Text("Scan a folder on this Mac").tag(ImportChoice.folder)
                Text("Import my Music or iTunes library")
                    .tag(ImportChoice.musicLibrary)
                    .disabled(Self.detectedMusicMediaFolder == nil)
                Text("Do not import media now").tag(ImportChoice.none)
            }
            .pickerStyle(.radioGroup)

            Group {
                switch choice {
                case .folder:
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Songbird will scan this folder for supported audio files.")
                            .font(.callout)
                            .foregroundStyle(secondaryText)
                        HStack(spacing: 8) {
                            TextField("Music folder", text: $folderPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse…", action: browse)
                                .accessibilityIdentifier("usability.folder.initialImport")
                        }
                        Toggle("Keep Songbird up to date when this folder changes", isOn: $keepUpdated)
                    }
                case .musicLibrary:
                    VStack(alignment: .leading, spacing: 12) {
                        Text(musicLibraryDescription)
                            .font(.callout)
                            .foregroundStyle(secondaryText)
                        Toggle("Keep Songbird up to date with changes to my music library", isOn: $keepUpdated)
                    }
                case .none:
                    Text("Songbird will open with an empty library.")
                        .font(.callout)
                        .foregroundStyle(secondaryText)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 144, alignment: .topLeading)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(palette.divider, lineWidth: 1)
            }

            if !validationMessage.isEmpty {
                Text(validationMessage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(palette.text)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                onClose()
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(ClassicSetupButtonStyle(palette: palette))

            Spacer()

            Button("Continue", action: continueImport)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(ClassicSetupButtonStyle(palette: palette))
        }
        .padding(.horizontal, 12)
        .frame(height: 29)
        .background(
            LinearGradient(
                colors: [palette.nowPlayingBar, palette.sidebar],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var musicLibraryDescription: String {
        if let folder = Self.detectedMusicMediaFolder {
            return "Import audio files from \(folder.path)."
        }
        return "No Apple Music or iTunes media folder was found."
    }

    private func browse() {
        folderSelectionProvider.selectFolders(
            for: .initialImport,
            allowsMultipleSelection: false,
            initialDirectory: URL(fileURLWithPath: folderPath, isDirectory: true)
        ) { urls in
            guard let url = urls.first else { return }
            folderPath = url.path
            choice = .folder
            validationMessage = ""
        }
    }

    private func continueImport() {
        if choice == .none {
            if keepUpdated == false {
                UserDefaults.standard.set(false, forKey: LibraryFolderWatcher.enabledKey)
                LibraryFolderWatcher.shared.applySettingsFromDefaults()
            }
            finish()
            return
        }

        let url: URL
        switch choice {
        case .folder:
            url = URL(fileURLWithPath: folderPath)
            UserDefaults.standard.set(url.path, forKey: Self.folderPathKey)
        case .musicLibrary:
            guard let detected = Self.detectedMusicMediaFolder else {
                validationMessage = "No Apple Music or iTunes media folder was found."
                return
            }
            url = detected
        case .none:
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            validationMessage = "Choose a folder that exists."
            return
        }

        let outcome = folderSetupCoordinator.add(
            [url],
            scanImmediately: true,
            preferredMode: keepUpdated ? .watching : .manualScanOnly
        )
        if outcome.manualOnlyPaths.isEmpty == false, keepUpdated {
            validationMessage = "This location was added as Manual Scan Only because automatic watching is unavailable."
        }
        finish()
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        onClose()
    }
}

private struct ClassicSetupButtonStyle: ButtonStyle {
    let palette: SongbirdThemePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                LinearGradient(
                    colors: configuration.isPressed
                        ? [palette.sidebar, palette.nowPlayingBar]
                        : [palette.nowPlayingBar, palette.sidebar],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(palette.divider, lineWidth: 1)
            }
            .shadow(color: palette.background.opacity(0.7), radius: 0, x: 0, y: 1)
    }
}
