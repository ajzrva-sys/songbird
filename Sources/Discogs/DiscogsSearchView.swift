import SwiftUI
import SwiftData
import AppKit

enum DiscogsSearchPaging {
    static func page(currentPage: Int, startsNewQuery: Bool) -> Int {
        startsNewQuery ? 1 : max(1, currentPage)
    }
}

/// Modal sheet for manually searching Discogs and selecting a cover for one album.
public struct DiscogsSearchView: View {
    private let albumTargets: [DiscogsArtworkAlbumTarget]
    let modelContext: ModelContext
    let applyArtworkChanges: @MainActor ([LibraryArtworkChange]) async
        -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError>
    let onDismiss: (Bool) -> Void

    private let dependencies: DiscogsReviewDependencies

    @State private var searchTitle: String
    @State private var searchArtist: String
    @State private var searchYear: String
    @State private var review = DiscogsReviewState<DiscogsArtworkCandidate>(evidence: { [$0.evidence] })
    private var candidates: [DiscogsArtworkCandidate] { review.items }
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var isLoading = false
    @State private var errorMessage: String?
    private var selectedCandidate: DiscogsArtworkCandidate? {
        get { review.selectedItem }
        nonmutating set { review.selectedID = newValue?.id }
    }
    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var searchTasks = ViewTaskSlot()
    private var downloadTask: Task<Void, Never>? {
        get { review.task }
        nonmutating set { review.task = newValue }
    }
    private var downloadGeneration: UUID {
        get { review.generation }
        nonmutating set { review.generation = newValue }
    }

    private var canSearch: Bool {
        !searchTitle.trimmingCharacters(in: .whitespaces).isEmpty
        || !searchArtist.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public init(
        album: Album,
        relatedAlbums: [Album]? = nil,
        searchTitle: String? = nil,
        modelContext: ModelContext,
        applyArtworkChanges: @escaping @MainActor ([LibraryArtworkChange]) async
            -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError>,
        dependencies: DiscogsReviewDependencies = .live,
        onDismiss: @escaping (Bool) -> Void
    ) {
        albumTargets = (relatedAlbums ?? [album]).map(DiscogsArtworkAlbumTarget.init(album:))
        self.modelContext = modelContext
        self.applyArtworkChanges = applyArtworkChanges
        self.onDismiss = onDismiss
        self.dependencies = dependencies
        _review = State(initialValue: DiscogsReviewState(clock: dependencies.clock, evidence: { [$0.evidence] }))
        _searchTitle = State(initialValue: searchTitle ?? album.title)
        _searchArtist = State(initialValue: album.artist)
        _searchYear = State(initialValue: album.year > 0 ? String(album.year) : "")
    }

    public var body: some View {
        DiscogsFreshnessView(clock: dependencies.clock, onTick: expireResults) { content }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Search fields
            VStack(spacing: 8) {
                HStack {
                    TextField("Title", text: $searchTitle)
                        .textFieldStyle(.roundedBorder)
                    TextField("Artist", text: $searchArtist)
                        .textFieldStyle(.roundedBorder)
                    TextField("Year", text: $searchYear)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                    Button("Search") {
                        performSearch(startsNewQuery: true)
                    }
                    .disabled(!canSearch || isLoading)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }

            Divider()
                .padding(.horizontal)

            // Results
            if isLoading && candidates.isEmpty {
                Spacer()
                ProgressView("Searching Discogs…")
                Spacer()
            } else if candidates.isEmpty && errorMessage == nil {
                Spacer()
                Text("Search for album artwork on Discogs.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(candidates) { candidate in
                            candidateRow(candidate)
                            Divider().padding(.leading, 68)
                        }
                    }
                    .padding(.vertical, 4)

                    // Pagination
                    if totalPages > 1 {
                        HStack {
                            Button("Previous") {
                                currentPage -= 1
                                performSearch()
                            }
                            .disabled(currentPage <= 1 || isLoading)
                            Text("Page \(currentPage) of \(totalPages)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Next") {
                                currentPage += 1
                                performSearch()
                            }
                            .disabled(currentPage >= totalPages || isLoading)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }

            // Footer
            Divider()
            HStack {
                Spacer()
                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                if let downloadError {
                    Text(downloadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Button("Cancel") { onDismiss(false) }
                    .keyboardShortcut(.cancelAction)
                Button("Use Selected") {
                    downloadAndApply()
                }
                .disabled(selectedCandidate == nil || isDownloading || isLoading)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .frame(width: 600, height: 480)
        .task {
            searchTasks.activate()
            if canSearch { performSearch(startsNewQuery: true) }
        }
        .onDisappear {
            searchTasks.invalidate()
            review.invalidate()
        }
    }

    private func candidateRow(_ candidate: DiscogsArtworkCandidate) -> some View {
        let isSelected = selectedCandidate?.id == candidate.id
        return VStack(alignment: .leading, spacing: 2) {
            Button {
                review.select(id: candidate.id)
                if review.requiresSearch { showExpiredResults() }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    DiscogsReviewThumbnail(candidate: candidate, dependencies: dependencies)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.title)
                            .font(.body)
                            .lineLimit(2)
                        Text(candidate.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatsAndYear(candidate))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(isSelected ? .primary : .secondary)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDownloading || isLoading)
            .accessibilityLabel("\(candidate.title) by \(candidate.artist)")
            DiscogsAttributionView(sourcePageURL: candidate.evidence.sourcePageURL)
                .padding(.leading, 76)
        }
    }

    private func formatsAndYear(_ candidate: DiscogsArtworkCandidate) -> String {
        var parts: [String] = []
        if let year = candidate.year { parts.append(String(year)) }
        if let country = candidate.country { parts.append(country) }
        if !candidate.formats.isEmpty { parts.append(candidate.formats.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private func performSearch(startsNewQuery: Bool = false) {
        searchTasks.activate()
        guard let searchLease = searchTasks.lease() else { return }
        let generation = review.beginSearch(targets: albumTargets)
        currentPage = DiscogsSearchPaging.page(
            currentPage: currentPage,
            startsNewQuery: startsNewQuery
        )
        let requestedPage = currentPage
        selectedCandidate = nil
        isLoading = true
        errorMessage = nil
        downloadError = nil

        let yearInt = Int(searchYear)
        let query = DiscogsArtworkSearchQuery(
            albumTitle: searchTitle,
            albumArtist: searchArtist,
            year: (yearInt ?? 0) > 0 ? yearInt : nil
        )

        let started = searchTasks.start(lease: searchLease) {
            do {
                let page = try await dependencies.search(query, page: requestedPage)
                try Task.checkCancellation()
                guard review.publish(page.candidates, generation: generation) else {
                    if review.requiresSearch { showExpiredResults() }
                    return
                }
                totalPages = page.totalPages
                isLoading = false
                if candidates.isEmpty {
                    errorMessage = "No matching releases found."
                }
            } catch is CancellationError {
                return
            } catch LibraryHealthMutationError.remoteEvidenceExpired {
                guard review.generation == generation else { return }
                showExpiredResults()
            } catch let error as DiscogsError {
                guard !Task.isCancelled, review.generation == generation else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            } catch {
                guard !Task.isCancelled, review.generation == generation else { return }
                errorMessage = "Search failed: \(error.localizedDescription)"
                isLoading = false
            }
        }
        if started == false {
            isLoading = false
        }
    }

    private func expireResults(at now: DiscogsFetchStamp?) {
        if review.expire(at: now) { showExpiredResults() }
    }

    private func showExpiredResults() {
        review.requiresSearch = true
        review.invalidate()
        searchTasks.invalidate()
        isLoading = false
        isDownloading = false
        currentPage = 1
        totalPages = 1
        errorMessage = "Discogs results expired. Search again."
        downloadError = nil
    }

    private func downloadAndApply() {
        guard let candidate = selectedCandidate, isDownloading == false else { return }
        downloadTask?.cancel()
        let generation = UUID()
        downloadGeneration = generation
        isDownloading = true
        downloadError = nil

        downloadTask = Task {
            do {
                let client = dependencies.client
                _ = try await DiscogsArtworkApplication.apply(
                    albumTargets.map { DiscogsArtworkAlbumSuggestion(album: $0, candidate: candidate) },
                    clock: dependencies.clock,
                    download: { value in try await client.downloadImage(from: value.imageURL, evidence: value.evidence) },
                    isCurrent: { downloadGeneration == generation },
                    submit: applyArtworkChanges
                )
                guard downloadGeneration == generation else { return }
                isDownloading = false
                onDismiss(true)
            } catch is CancellationError {
                await MainActor.run {
                    guard downloadGeneration == generation else { return }
                    isDownloading = false
                }
            } catch {
                expireResults(at: dependencies.clock())
                await MainActor.run {
                    guard downloadGeneration == generation else { return }
                    downloadError = "Failed to download artwork: \(error.localizedDescription)"
                    isDownloading = false
                }
            }
        }
    }
}

/// Presents artwork search as an independent macOS window so it can be moved
/// and resized without moving or blocking the library window.
@MainActor
public enum DiscogsSearchWindowPresenter {
    private static var coordinators: [ObjectIdentifier: DiscogsSearchWindowCoordinator] = [:]

    public static func show(
        album: Album,
        relatedAlbums: [Album] = [],
        searchTitle: String? = nil,
        modelContext: ModelContext,
        actions: LibraryItemActionHandler,
        dependencies: DiscogsReviewDependencies = .live,
        completion: @escaping () -> Void = {}
    ) {
        let coordinator = DiscogsSearchWindowCoordinator()
        let rootView = DiscogsSearchView(
            album: album,
            relatedAlbums: relatedAlbums.isEmpty ? [album] : relatedAlbums,
            searchTitle: searchTitle,
            modelContext: modelContext,
            applyArtworkChanges: { changes in await actions.applyArtwork(changes, clock: dependencies.clock) },
            dependencies: dependencies,
            onDismiss: { [weak coordinator] didApply in
                if didApply { completion() }
                coordinator?.window?.close()
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Find Artwork — \(album.title)"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 480))
        window.contentMinSize = NSSize(width: 520, height: 400)
        window.isReleasedWhenClosed = false
        window.center()

        coordinator.window = window
        coordinator.onClose = {
            coordinators.removeValue(forKey: ObjectIdentifier(window))
        }
        window.delegate = coordinator
        coordinators[ObjectIdentifier(window)] = coordinator

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class DiscogsSearchWindowCoordinator: NSObject, NSWindowDelegate {
    weak var window: NSWindow?
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
