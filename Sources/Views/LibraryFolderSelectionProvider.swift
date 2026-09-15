import AppKit
import Foundation

public enum LibraryFolderSelectionPurpose: String, Sendable {
    case addAndScan
    case addWithoutScanning
    case initialImport

    fileprivate var usabilityDirectoryName: String {
        switch self {
        case .addAndScan: "AddAndScan"
        case .addWithoutScanning: "WithoutScanning"
        case .initialImport: "InitialImport"
        }
    }
}

@MainActor
public protocol LibraryFolderSelectionProviding {
    func selectFolders(
        for purpose: LibraryFolderSelectionPurpose,
        allowsMultipleSelection: Bool,
        initialDirectory: URL?,
        completion: @escaping ([URL]) -> Void
    )
}

@MainActor
public final class NativeLibraryFolderSelectionProvider: LibraryFolderSelectionProviding {
    public init() {}

    public func selectFolders(
        for purpose: LibraryFolderSelectionPurpose,
        allowsMultipleSelection: Bool,
        initialDirectory: URL?,
        completion: @escaping ([URL]) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.directoryURL = initialDirectory
        panel.begin { response in
            completion(response == .OK ? panel.urls : [])
        }
    }
}

/// A packaged-usability picker replacement that can return only a known child
/// directory of the validated disposable root. It never drives a system panel.
@MainActor
public final class DisposableLibraryFolderSelectionProvider: LibraryFolderSelectionProviding {
    private let root: URL
    private let fileManager: FileManager

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.fileManager = fileManager
    }

    public func selectFolders(
        for purpose: LibraryFolderSelectionPurpose,
        allowsMultipleSelection: Bool,
        initialDirectory: URL?,
        completion: @escaping ([URL]) -> Void
    ) {
        let candidate = root
            .appendingPathComponent("FolderSelections", isDirectory: true)
            .appendingPathComponent(purpose.usabilityDirectoryName, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(prefix),
              fileManager.fileExists(atPath: candidate.path) else {
            completion([])
            return
        }
        completion([candidate])
    }
}

@MainActor
public enum LibraryFolderSelectionProviderFactory {
    public static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> any LibraryFolderSelectionProviding {
        guard SongbirdUIRuntime.isTesting(
            environment: environment,
            infoDictionary: infoDictionary
        ), let rootPath = SongbirdUIRuntime.testRoot(
            environment: environment,
            infoDictionary: infoDictionary
        ) else {
            return NativeLibraryFolderSelectionProvider()
        }

        let defaultDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        guard let root = try? MediaLibraryStore.resolvedApplicationSupportDirectory(
            environment: [MediaLibraryStore.uiTestRootEnvironmentKey: rootPath],
            defaultDirectory: defaultDirectory
        ) else {
            return NativeLibraryFolderSelectionProvider()
        }
        return DisposableLibraryFolderSelectionProvider(root: root)
    }
}
