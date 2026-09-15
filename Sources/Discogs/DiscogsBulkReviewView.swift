import SwiftUI
import SwiftData
import AppKit

/// Bulk search and review for albums missing artwork.
public struct DiscogsBulkReviewView: View {
    let modelContext: ModelContext
    let albumIDs: Set<UUID>?
    let applyArtworkChanges: @MainActor ([LibraryArtworkChange]) async
        -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError>
    let onDismiss: () -> Void

    private let dependencies: DiscogsReviewDependencies

    @State private var phase: Phase = .searching
    @State private var completedCount = 0
    @State private var totalCount = 0
    @State private var matchedCount = 0
    @State private var appliedCount = 0
    @State private var skippedCount = 0
    @State private var failedCount = 0
    @State private var failedAlbums: [DiscogsArtworkAlbumTarget] = []
    @State private var currentAlbumTitle = ""
    @State private var searchStatus = "Searching Discogs…"
    @State private var errorMessage: String?

    // Review phase
    @State private var review = DiscogsReviewState<ReviewItem>(evidence: { $0.candidates.map(\.evidence) })
    private var reviewItems: [ReviewItem] {
        get { review.items }
        nonmutating set { review.items = newValue }
    }
    private var reviewIndex: Int {
        get { review.reviewIndex }
        nonmutating set { review.reviewIndex = newValue }
    }
    @State private var isDownloading = false
    @State private var downloadError: String?
    private var downloadTask: Task<Void, Never>? {
        get { review.task }
        nonmutating set { review.task = newValue }
    }
    private var downloadGeneration: UUID {
        get { review.generation }
        nonmutating set { review.generation = newValue }
    }
    @State private var searchTasks = ViewTaskSlot()
    @State private var showsBulkApplyConfirmation = false
    @State private var bulkCompletedCount = 0
    @State private var bulkTotalCount = 0
    @State private var failedArtworkSuggestions: [DiscogsArtworkAlbumSuggestion] = []

    private enum Phase: Equatable {
        case searching
        case review
        case applying
        case complete
        case error
    }

    private static let minimumRequestInterval: TimeInterval = 2.1

    private struct ReviewItem: Identifiable {
        let album: DiscogsArtworkAlbumTarget
        let candidates: [DiscogsArtworkCandidate]
        var id: UUID { album.id }
    }

    private var currentReview: ReviewItem? {
        guard reviewIndex < reviewItems.count else { return nil }
        return reviewItems[reviewIndex]
    }

    private var bulkSuggestionCount: Int {
        reviewItems.dropFirst(reviewIndex).count { item in
            DiscogsArtworkSuggestionPolicy.suggestedCandidate(from: item.candidates, at: review.now) != nil
        }
    }

    public init(
        modelContext: ModelContext,
        albumIDs: Set<UUID>? = nil,
        applyArtworkChanges: @escaping @MainActor ([LibraryArtworkChange]) async
            -> Result<LibraryHealthMutationOutcome, LibraryHealthMutationError>,
        dependencies: DiscogsReviewDependencies = .live,
        onDismiss: @escaping () -> Void
    ) {
        self.modelContext = modelContext
        self.albumIDs = albumIDs
        self.applyArtworkChanges = applyArtworkChanges
        self.onDismiss = onDismiss
        self.dependencies = dependencies
        _review = State(initialValue: DiscogsReviewState(clock: dependencies.clock, evidence: { $0.candidates.map(\.evidence) }))
    }

    public var body: some View {
        DiscogsFreshnessView(clock: dependencies.clock, onTick: expireResults) { content }
    }

    private var content: some View {
        VStack(spacing: 0) {
            switch phase {
            case .searching:
                searchingView
            case .review:
                reviewView
            case .applying:
                applyingView
            case .complete:
                completeView
            case .error:
                errorView
            }
        }
        .frame(width: 600, height: 480)
        .confirmationDialog(
            "Apply \(bulkSuggestionCount) Artwork Suggestions?",
            isPresented: $showsBulkApplyConfirmation
        ) {
            Button("Apply to \(bulkSuggestionCount) Albums") {
                applyArtworkSuggestions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Songbird will use the first Discogs artwork result for each album. "
                    + "Existing artwork will not be changed."
            )
        }
        .task {
            searchTasks.activate()
            searchTasks.start { await performBulkSearch() }
        }
        .onDisappear {
            searchTasks.invalidate()
            review.invalidate()
        }
    }

    // MARK: - Searching

    private var searchingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text(searchStatus)
                .font(.headline)
            Text("\(completedCount) of \(totalCount) albums")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !currentAlbumTitle.isEmpty {
                Text(currentAlbumTitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Button("Cancel") {
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Review

    private var reviewView: some View {
        VStack(spacing: 0) {
            if let current = currentReview {
                HStack {
                    Text("Review \(reviewIndex + 1) of \(reviewItems.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProgressView(value: Double(reviewIndex), total: Double(reviewItems.count))
                        .frame(width: 120)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 4)

                Divider().padding(.horizontal)

                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(width: 60, height: 60)
                        .overlay(Image(systemName: "square.stack").foregroundStyle(.secondary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.album.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(current.album.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider().padding(.horizontal)

                if current.candidates.isEmpty {
                    Spacer()
                    Text("No results found for this album.")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(current.candidates) { candidate in
                                candidateButton(candidate, for: current.album)
                                Divider().padding(.leading, 68)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Divider()
                HStack {
                    Button("Apply All Suggestions") {
                        showsBulkApplyConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDownloading || bulkSuggestionCount == 0)
                    Spacer()
                    if isDownloading {
                        ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                    }
                    if let downloadError {
                        Text(downloadError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                    Button("Skip") { advanceReview(applied: false) }
                        .disabled(isDownloading)
                    Button("Skip Remaining") {
                        skippedCount += max(0, reviewItems.count - reviewIndex)
                        reviewItems = []
                        phase = .complete
                    }
                    .disabled(isDownloading)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
        }
    }

    private func candidateButton(
        _ candidate: DiscogsArtworkCandidate,
        for album: DiscogsArtworkAlbumTarget
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                applyCandidate(candidate, to: album)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    DiscogsReviewThumbnail(candidate: candidate, dependencies: dependencies)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.title).font(.body).lineLimit(2)
                        Text(candidate.artist).font(.caption).foregroundStyle(.secondary)
                        if let year = candidate.year {
                            Text(String(year)).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDownloading)
            DiscogsAttributionView(sourcePageURL: candidate.evidence.sourcePageURL)
                .padding(.leading, 76)
        }
    }

    // MARK: - Applying

    private var applyingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(
                value: Double(bulkCompletedCount),
                total: Double(max(1, bulkTotalCount))
            )
            .frame(width: 260)
            Text("Applying Artwork…")
                .font(.headline)
            Text("\(bulkCompletedCount) of \(bulkTotalCount) albums")
                .font(.caption)
                .foregroundStyle(.secondary)
            if currentAlbumTitle.isEmpty == false {
                Text(currentAlbumTitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Button("Cancel") { onDismiss() }
                .keyboardShortcut(.cancelAction)
                .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Complete / Error

    private var completeView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Done")
                .font(.title2)
            Text("Searched \(completedCount) · Matched \(matchedCount) · Applied \(appliedCount) · Skipped \(skippedCount) · Failed \(failedCount)")
                .foregroundStyle(failedCount > 0 ? .orange : .secondary)
                .multilineTextAlignment(.center)
            if failedAlbums.isEmpty == false {
                Text("Search failures can be retried without repeating completed searches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry Searches (\(failedAlbums.count))") {
                    retryFailedSearches()
                }
            }
            if failedArtworkSuggestions.isEmpty == false {
                Text("Artwork download failures can be retried without repeating successful albums.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry Artwork Downloads (\(failedArtworkSuggestions.count))") {
                    applyArtworkSuggestions(failedArtworkSuggestions)
                }
            }
            if let downloadError {
                Text(downloadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button("Close") { onDismiss() }
                .keyboardShortcut(.return)
            Spacer()
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Search Stopped")
                .font(.title2)
            if let msg = errorMessage {
                Text(msg).foregroundStyle(.secondary)
            }
            if review.requiresSearch { Button("Search again") { restartExpiredSearch() } }
            Button("Close") { onDismiss() }
                .keyboardShortcut(.return)
            Spacer()
        }
    }

    // MARK: - Logic

    private func performBulkSearch(
        albums retryAlbums: [DiscogsArtworkAlbumTarget]? = nil
    ) async {
        let allAlbums = retryAlbums ?? fetchEligibleAlbums()
        guard phase != .error else { return }
        let generation = review.beginSearch(targets: allAlbums)

        let startingCompleted = completedCount
        if retryAlbums == nil {
            totalCount = allAlbums.count
        } else {
            totalCount += allAlbums.count
        }

        if totalCount == 0 {
            await MainActor.run { phase = .complete }
            return
        }

        var items: [ReviewItem] = []
        var lastRequestDate: Date?

        for (index, album) in allAlbums.enumerated() {
            guard !Task.isCancelled else { return }

            await MainActor.run {
                currentAlbumTitle = album.title
                completedCount = startingCompleted + index
                searchStatus = "Searching Discogs…"
            }

            let query = DiscogsArtworkSearchQuery(
                albumTitle: album.title,
                albumArtist: album.artist,
                year: album.year > 0 ? album.year : nil
            )

            let cached: DiscogsArtworkSearchCache.Hit?
            do { cached = try await dependencies.cachedCandidates(for: query) }
            catch is CancellationError { return }
            catch { showExpiredResults(); return }
            if let cached {
                guard !Task.isCancelled else { return }
                if !cached.value.isEmpty {
                    items.append(ReviewItem(album: album, candidates: cached.value))
                    matchedCount += 1
                }
            } else {
                var finishedAlbum = false
                while !finishedAlbum {
                    guard !Task.isCancelled else { return }

                    if let lastRequestDate {
                        let elapsed = Date().timeIntervalSince(lastRequestDate)
                        let delay = Self.minimumRequestInterval - elapsed
                        if delay > 0 {
                            do {
                                try await Task.sleep(for: .seconds(delay))
                            } catch is CancellationError {
                                return
                            } catch {
                                return
                            }
                            guard !Task.isCancelled else { return }
                        }
                    }

                    lastRequestDate = Date()
                    do {
                        let page = try await dependencies.search(query, page: 1)
                        try Task.checkCancellation()
                        let top = Array(page.candidates.prefix(5))
                        try await dependencies.storeCandidates(top, for: query, fetches: [page.fetchedAt])
                        guard !Task.isCancelled else { return }
                        if !top.isEmpty {
                            items.append(ReviewItem(album: album, candidates: top))
                            matchedCount += 1
                        }
                        finishedAlbum = true
                    } catch is CancellationError {
                        return
                    } catch LibraryHealthMutationError.remoteEvidenceExpired {
                        showExpiredResults()
                        return
                    } catch DiscogsError.tokenInvalid, DiscogsError.tokenMissing {
                        await MainActor.run {
                            errorMessage = "Discogs token is invalid or missing."
                            phase = .error
                        }
                        return
                    } catch DiscogsError.rateLimited(let retryAfter) {
                        let delay = max(retryAfter ?? 60, 60)
                        await MainActor.run {
                            searchStatus = "Rate limit reached — pausing for \(Int(delay)) seconds"
                        }
                        do {
                            try await Task.sleep(for: .seconds(delay))
                        } catch is CancellationError {
                            return
                        } catch {
                            return
                        }
                    } catch {
                        // Leave transient failures uncached so a later scan retries them.
                        failedCount += 1
                        failedAlbums.append(album)
                        finishedAlbum = true
                    }
                }
            }

            await MainActor.run { completedCount = startingCompleted + index + 1 }
        }

        guard !Task.isCancelled else { return }
        await MainActor.run {
            guard review.publish(items, generation: generation) else {
                if review.requiresSearch { showExpiredResults() }
                return
            }
            phase = reviewItems.isEmpty ? .complete : .review
        }
    }

    private func expireResults(at now: DiscogsFetchStamp?) {
        let retryExpired = failedArtworkSuggestions.contains { !$0.candidate.evidence.isFresh(at: now) }
        if review.expire(at: now) || retryExpired { showExpiredResults() }
    }

    private func showExpiredResults() {
        review.requiresSearch = true
        review.invalidate()
        searchTasks.invalidate()
        failedArtworkSuggestions = []
        isDownloading = false
        showsBulkApplyConfirmation = false
        downloadError = nil
        errorMessage = "Discogs results expired. Search again."
        phase = .error
    }

    private func restartExpiredSearch() {
        let targets = review.targets
        phase = .searching
        errorMessage = nil
        searchTasks.activate()
        searchTasks.start { await performBulkSearch(albums: targets) }
    }

    private func retryFailedSearches() {
        let albums = failedAlbums
        guard albums.isEmpty == false else { return }
        failedCount = max(0, failedCount - albums.count)
        failedAlbums = []
        phase = .searching
        searchStatus = "Retrying failed Discogs searches…"
        searchTasks.activate()
        searchTasks.start { await performBulkSearch(albums: albums) }
    }

    private func fetchEligibleAlbums() -> [DiscogsArtworkAlbumTarget] {
        let descriptor = FetchDescriptor<Album>(sortBy: [SortDescriptor(\Album.title)])
        let all: [Album]
        do {
            all = try modelContext.fetch(descriptor)
        } catch {
            errorMessage = "Could not read albums: \(error.localizedDescription)"
            phase = .error
            return []
        }
        return all.compactMap { album in
            if let albumIDs, albumIDs.contains(album.id) == false { return nil }
            guard album.artworkData == nil,
                  album.title.trimmingCharacters(in: .whitespaces).isEmpty == false,
                  album.artist.trimmingCharacters(in: .whitespaces).isEmpty == false else {
                return nil
            }
            return DiscogsArtworkAlbumTarget(album: album)
        }
    }

    private func applyCandidate(
        _ candidate: DiscogsArtworkCandidate,
        to album: DiscogsArtworkAlbumTarget
    ) {
        guard isDownloading == false else { return }
        downloadTask?.cancel()
        let generation = UUID()
        downloadGeneration = generation
        isDownloading = true
        downloadError = nil

        downloadTask = Task {
            do {
                let client = dependencies.client
                _ = try await DiscogsArtworkApplication.apply(
                    [DiscogsArtworkAlbumSuggestion(album: album, candidate: candidate)],
                    clock: dependencies.clock,
                    download: { value in try await client.downloadImage(from: value.imageURL, evidence: value.evidence) },
                    isCurrent: { downloadGeneration == generation },
                    submit: applyArtworkChanges
                )
                guard downloadGeneration == generation else { return }
                isDownloading = false
                advanceReview(applied: true)
            } catch is CancellationError {
                await MainActor.run {
                    guard downloadGeneration == generation else { return }
                    isDownloading = false
                }
            } catch {
                expireResults(at: dependencies.clock())
                await MainActor.run {
                    guard downloadGeneration == generation else { return }
                    downloadError = "Download failed: \(error.localizedDescription)"
                    isDownloading = false
                }
            }
        }
    }

    private func applyArtworkSuggestions(
        _ retrySuggestions: [DiscogsArtworkAlbumSuggestion]? = nil
    ) {
        guard isDownloading == false else { return }

        let remainingItems = Array(reviewItems.dropFirst(reviewIndex))
        let suggestions = retrySuggestions ?? remainingItems.compactMap { item in
            guard let candidate = DiscogsArtworkSuggestionPolicy.suggestedCandidate(
                from: item.candidates, at: review.now
            ) else { return nil }
            return DiscogsArtworkAlbumSuggestion(album: item.album, candidate: candidate)
        }
        guard suggestions.isEmpty == false else { return }

        let returnPhase: Phase = retrySuggestions == nil ? .review : .complete
        let initiallySkipped = retrySuggestions == nil
            ? remainingItems.count - suggestions.count
            : 0
        let previousFailureCount = retrySuggestions?.count ?? 0

        downloadTask?.cancel()
        let generation = UUID()
        downloadGeneration = generation
        isDownloading = true
        downloadError = nil
        bulkCompletedCount = 0
        bulkTotalCount = suggestions.count
        phase = .applying

        downloadTask = Task {
            do {
                let client = dependencies.client
                let outcome = try await DiscogsArtworkApplication.apply(
                    suggestions,
                    clock: dependencies.clock,
                    download: { value in try await client.downloadImage(from: value.imageURL, evidence: value.evidence) },
                    isCurrent: { downloadGeneration == generation },
                    progress: { bulkCompletedCount = $0 },
                    submit: applyArtworkChanges
                )
                guard downloadGeneration == generation else { return }
                currentAlbumTitle = ""
                isDownloading = false
                appliedCount += outcome.affectedAlbumCount
                skippedCount += initiallySkipped
                failedCount = max(0, failedCount - previousFailureCount)
                failedArtworkSuggestions = []
                reviewItems = []
                reviewIndex = 0
                phase = .complete
            } catch is CancellationError {
                return
            } catch {
                expireResults(at: dependencies.clock())
                await MainActor.run {
                    guard downloadGeneration == generation else { return }
                    failedArtworkSuggestions = suggestions
                    failedCount = max(0, failedCount - previousFailureCount) + suggestions.count
                    downloadError = "Nothing was applied: \(error.localizedDescription)"
                    isDownloading = false
                    phase = returnPhase
                }
            }
        }
    }

    private func advanceReview(applied: Bool) {
        if applied {
            appliedCount += 1
        } else {
            skippedCount += 1
        }
        if review.advance() {
            phase = .complete
        }
    }
}

@MainActor
public enum DiscogsBulkReviewWindowPresenter {
    private static var coordinators: [String: DiscogsBulkReviewWindowCoordinator] = [:]

    public static func show(
        modelContext: ModelContext,
        albumIDs: Set<UUID>? = nil,
        actions: LibraryItemActionHandler,
        dependencies: DiscogsReviewDependencies = .live
    ) {
        let key = albumIDs.map { ids in
            ids.map(\.uuidString).sorted().joined(separator: "|")
        } ?? "all"
        if let window = coordinators[key]?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let coordinator = DiscogsBulkReviewWindowCoordinator()
        let rootView = DiscogsBulkReviewView(
            modelContext: modelContext,
            albumIDs: albumIDs,
            applyArtworkChanges: { changes in await actions.applyArtwork(changes, clock: dependencies.clock) },
            dependencies: dependencies,
            onDismiss: { [weak coordinator] in
                coordinator?.window?.close()
            }
        )
        let host = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: host)
        window.title = "Find Missing Artwork"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 480))
        window.contentMinSize = NSSize(width: 520, height: 400)
        window.isReleasedWhenClosed = false
        window.center()

        coordinator.window = window
        coordinator.onClose = {
            self.coordinators.removeValue(forKey: key)
        }
        window.delegate = coordinator
        self.coordinators[key] = coordinator

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class DiscogsBulkReviewWindowCoordinator: NSObject, NSWindowDelegate {
    weak var window: NSWindow?
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
