import AppKit
import Foundation
import SwiftData
import SwiftUI

/// Available only in the signed disposable usability identity, never as a live-client override.
@MainActor
public enum DiscogsUsabilityFixture {
    public static var isEnabled: Bool {
        eligible(bundleIdentifier: Bundle.main.bundleIdentifier,
            info: Bundle.main.infoDictionary ?? [:], environment: ProcessInfo.processInfo.environment)
    }

    static func eligible(bundleIdentifier: String?, info: [String: Any], environment: [String: String]) -> Bool {
        guard bundleIdentifier?.hasPrefix("com.songbird.player.usability.") == true,
              SongbirdUIRuntime.isTesting(environment: [:], infoDictionary: info),
              let root = info[SongbirdUIRuntime.testRootInfoDictionaryKey] as? String,
              environment[MediaLibraryStore.uiTestRootEnvironmentKey].map({ $0 == root }) ?? true,
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              (try? MediaLibraryStore.resolvedApplicationSupportDirectory(environment: [:],
                packagedUITestRoot: root, defaultDirectory: support)) != nil else { return false }
        return true
    }

    private static var window: NSWindow?

    public static func show(context: ModelContext, actions: LibraryItemActionHandler) {
        guard isEnabled,
              let album = try? context.fetch(FetchDescriptor<Album>()).sorted(by: { $0.title < $1.title }).first,
              let root = Bundle.main.infoDictionary?[SongbirdUIRuntime.testRootInfoDictionaryKey] as? String,
              let url = Bundle.main.url(forResource: "songbird-logo", withExtension: "png"),
              let bytes = try? Data(contentsOf: url) else { return }
        let panel = DiscogsFixturePanel(album: album, context: context, actions: actions,
            root: URL(fileURLWithPath: root), imageData: bytes)
        let host = NSHostingController(rootView: panel)
        let panelWindow = NSWindow(contentViewController: host)
        panelWindow.title = "Discogs Fixture"
        panelWindow.styleMask = [.titled, .closable, .resizable]
        panelWindow.setContentSize(NSSize(width: 640, height: 540))
        panelWindow.isReleasedWhenClosed = false
        window?.close()
        window = panelWindow
        panelWindow.center()
        panelWindow.makeKeyAndOrderFront(nil)
    }
}

private final class DiscogsFixtureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var offset: TimeInterval = 0
    func expire() { lock.lock(); offset += 21_600; lock.unlock() }
    func sample() -> DiscogsFetchStamp {
        lock.lock(); defer { lock.unlock() }
        return DiscogsFetchStamp(wall: Date(timeIntervalSince1970: 1_000 + offset),
            continuousSeconds: 100 + offset, bootID: "disposable-ui-fixture")
    }
}

private struct DiscogsFixtureClient: DiscogsReviewClient {
    let clock: DiscogsFixtureClock
    let imageData: Data
    func search(_ query: DiscogsArtworkSearchQuery, page: Int) async throws -> DiscogsSearchPage {
        let stamp = clock.sample()
        let image = URL(string: "https://fixture.invalid/cover.png")!
        let candidate = DiscogsArtworkCandidate(id: 42, title: "Fixture Album", artist: "Fixture Artist",
            year: 1997, country: "Fixture", formats: ["CD"], genres: ["Rock"], styles: [],
            thumbnailURL: image, imageURL: image,
            sourcePageURL: URL(string: "https://www.discogs.com/release/42")!, fetchedAt: stamp)
        return DiscogsSearchPage(candidates: [candidate], page: 1, totalPages: 1, fetchedAt: stamp)
    }
    func downloadImage(from url: URL, evidence: DiscogsContentEvidence) async throws -> Data {
        guard url.host == "fixture.invalid", evidence.isFresh(at: clock.sample()) else {
            throw DiscogsError.resultsExpired
        }
        return imageData
    }
}

private struct DiscogsFixturePanel: View {
    let album: Album
    let context: ModelContext
    let actions: LibraryItemActionHandler
    private let clock: DiscogsFixtureClock
    private let dependencies: DiscogsReviewDependencies
    @State private var showingLookup = true
    @State private var message = ""

    init(album: Album, context: ModelContext, actions: LibraryItemActionHandler, root: URL, imageData: Data) {
        self.album = album
        self.context = context
        self.actions = actions
        let clock = DiscogsFixtureClock()
        self.clock = clock
        dependencies = DiscogsReviewDependencies(client: DiscogsFixtureClient(clock: clock, imageData: imageData),
            cacheURL: root.appendingPathComponent("discogs-smoke-cache.json"), clock: { clock.sample() })
    }

    var body: some View {
        VStack {
            HStack {
                Button("Expire Fixture Results") {
                    clock.expire()
                    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
                }
                Button("Open Fixture Lookup") { showingLookup = true }
            }
            Text(album.artworkData?.isEmpty == false ? "Saved artwork available offline" : "No saved artwork")
            Text(message)
            if showingLookup {
                DiscogsSearchView(album: album, modelContext: context,
                    applyArtworkChanges: { await actions.applyArtwork($0, clock: dependencies.clock) },
                    dependencies: dependencies, onDismiss: { saved in
                        message = saved ? "Fixture cover saved" : "Lookup closed"
                        showingLookup = false
                    })
            } else if let bytes = album.artworkData, let image = NSImage(data: bytes) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 160, height: 160)
                Spacer()
            }
        }.padding()
    }
}
