import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DropImportResolution: Equatable, Sendable {
    let urls: [URL]
    let unsupportedCount: Int
}

@MainActor
enum DropImportOperation {
    static func run(
        resolve: @escaping @MainActor () async -> DropImportResolution?,
        showSkippedNotice: @escaping @MainActor (Int) -> Void,
        importURLs: @escaping @MainActor ([URL]) async -> Void
    ) async {
        guard Task.isCancelled == false,
              let resolution = await resolve(),
              Task.isCancelled == false else {
            return
        }
        if resolution.unsupportedCount > 0 {
            showSkippedNotice(resolution.unsupportedCount)
        }
        guard Task.isCancelled == false else { return }
        await importURLs(resolution.urls)
    }
}

struct DropReceiver<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDragOver = false
    @State private var importTasks = ViewTaskSlot()

    var body: some View {
        content()
            .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                handleDrop(providers: providers)
                return true
            }
            .onReceive(NotificationCenter.default.publisher(for: .filesWereOpened)) { note in
                guard let urls = note.userInfo?["urls"] as? [URL] else { return }
                submitImport(urls)
            }
            .onAppear { importTasks.activate() }
            .onDisappear { importTasks.invalidate() }
            .background(SongbirdTheme.background(for: colorScheme))
            .overlay(
                isDragOver ? RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(10)
                    .padding(4)
                    : nil
            )
    }

    private func handleDrop(providers: [NSItemProvider]) {
        importTasks.start {
            await DropImportOperation.run(
                resolve: { await resolve(providers: providers) },
                showSkippedNotice: { showSkippedNotice(count: $0) },
                importURLs: { await importOpenedURLs($0) }
            )
        }
    }

    private func submitImport(_ urls: [URL]) {
        importTasks.start {
            await DropImportOperation.run(
                resolve: {
                    DropImportResolution(urls: urls, unsupportedCount: 0)
                },
                showSkippedNotice: { showSkippedNotice(count: $0) },
                importURLs: { await importOpenedURLs($0) }
            )
        }
    }

    @MainActor
    private func resolve(providers: [NSItemProvider]) async -> DropImportResolution? {
        var resolved: [URL] = []
        var seen = Set<URL>()
        var unsupportedCount = 0
        for provider in providers {
            guard Task.isCancelled == false else { return nil }
            do {
                let item = try await provider.loadItem(
                    forTypeIdentifier: UTType.fileURL.identifier
                )
                guard Task.isCancelled == false else { return nil }
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else {
                    unsupportedCount += 1
                    continue
                }
                let standardized = url.standardizedFileURL
                if seen.insert(standardized).inserted {
                    resolved.append(standardized)
                }
            } catch is CancellationError {
                return nil
            } catch {
                guard Task.isCancelled == false else { return nil }
                unsupportedCount += 1
            }
        }
        return DropImportResolution(urls: resolved, unsupportedCount: unsupportedCount)
    }

    @MainActor
    private func showSkippedNotice(count: Int) {
        LibraryStatus.shared.showNotice(
            "Skipped \(count) item\(count == 1 ? "" : "s") that could not be opened.",
            severity: .warning,
            source: .importing
        )
    }

    @MainActor
    private func importOpenedURLs(_ urls: [URL]) async {
        guard urls.isEmpty == false else { return }
        let scanner = LibraryScanner(
            modelContainer: modelContext.container,
            status: LibraryStatus.shared
        )
        await scanner.scanFolders(urls)
    }
}
