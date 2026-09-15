import SwiftUI
import SwiftData
import AppKit

/// Bulk search and review for tracks missing genre metadata.
public struct DiscogsGenreReviewView: View {
    let modelContext: ModelContext
    let actions: LibraryItemActionHandler
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
    @State private var isApplying = false
    @State private var applyError: String?
    private var applyTask: Task<Void, Never>? {
        get { review.task }
        nonmutating set { review.task = newValue }
    }
    private var applyGeneration: UUID {
        get { review.generation }
        nonmutating set { review.generation = newValue }
    }
    @State private var searchTasks = ViewTaskSlot()
    @State private var showsBulkApplyConfirmation = false

    private enum Phase: Equatable {
        case searching
        case review
        case complete
        case error
    }

    private static let minimumRequestInterval: TimeInterval = 2.1

    private struct ReviewItem: Identifiable {
        let album: DiscogsArtworkAlbumTarget
        let candidates: [DiscogsGenreCandidate]
        var id: UUID { album.id }
    }

    struct DiscogsGenreCandidate: Identifiable {
        let id: Int
        let title: String
        let genres: [String]
        let styles: [String]
        let evidence: DiscogsContentEvidence

        var allTags: [String] {
            genres + styles
        }

        var primaryGenre: String? {
            DiscogsGenreSuggestionPolicy.suggestedGenre(from: [genres])
        }
    }

    private var currentReview: ReviewItem? {
        guard reviewIndex < reviewItems.count else { return nil }
        return reviewItems[reviewIndex]
    }

    private var bulkSuggestionCount: Int {
        reviewItems.dropFirst(reviewIndex).count { item in
            suggestedGenre(for: item) != nil
        }
    }

    public init(modelContext: ModelContext, actions: LibraryItemActionHandler, dependencies: DiscogsReviewDependencies = .live, onDismiss: @escaping () -> Void) {
        self.actions = actions
        self.modelContext = modelContext
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
            case .complete:
                completeView
            case .error:
                errorView
            }
        }
        .frame(width: 600, height: 480)
        .confirmationDialog(
            "Apply \(bulkSuggestionCount) Suggested Genres?",
            isPresented: $showsBulkApplyConfirmation
        ) {
            Button("Apply to \(bulkSuggestionCount) Albums") {
                applyAllSuggestions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Songbird will use the primary genre from each album's first Discogs result. "
                    + "Existing genres will not be changed."
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
                        .overlay(Image(systemName: "tag").foregroundStyle(.secondary))
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
                                Divider().padding(.leading, 12)
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
                    .disabled(isApplying || bulkSuggestionCount == 0)
                    Spacer()
                    if isApplying {
                        ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                    }
                    if let applyError {
                        Text(applyError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                    Button("Skip") { advanceReview(applied: false) }
                        .disabled(isApplying)
                    Button("Skip Remaining") {
                        skippedCount += max(0, reviewItems.count - reviewIndex)
                        reviewItems = []
                        phase = .complete
                    }
                    .disabled(isApplying)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
        }
    }

    private func candidateButton(
        _ candidate: DiscogsGenreCandidate,
        for album: DiscogsArtworkAlbumTarget
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                applyCandidate(candidate, to: album)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "tag.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.title)
                            .font(.body)
                            .lineLimit(1)
                        FlowLayout(spacing: 4) {
                            ForEach(candidate.allTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isApplying)
            DiscogsAttributionView(sourcePageURL: candidate.evidence.sourcePageURL)
                .padding(.leading, 56)
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
            if failedCount > 0 {
                Text("Failed albums can be retried without repeating completed searches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry Failed (\(failedCount))") {
                    retryFailedSearches()
                }
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
                let genreCandidates = Self.genreCandidates(from: cached.value)
                if !genreCandidates.isEmpty {
                    items.append(ReviewItem(album: album, candidates: genreCandidates))
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
                        let genreCandidates = Self.genreCandidates(from: top)
                        if !genreCandidates.isEmpty {
                            items.append(ReviewItem(album: album, candidates: genreCandidates))
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

    static func genreCandidates(
        from candidates: [DiscogsArtworkCandidate]
    ) -> [DiscogsGenreCandidate] {
        candidates.compactMap { candidate in
            guard !candidate.genres.isEmpty else { return nil }
            return DiscogsGenreCandidate(
                id: candidate.id,
                title: candidate.title,
                genres: candidate.genres,
                styles: candidate.styles,
                evidence: candidate.evidence
            )
        }
    }

    private func expireResults(at now: DiscogsFetchStamp?) {
        if review.expire(at: now) { showExpiredResults() }
    }

    private func showExpiredResults() {
        review.requiresSearch = true
        review.invalidate()
        searchTasks.invalidate()
        isApplying = false
        showsBulkApplyConfirmation = false
        applyError = nil
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
        failedAlbums = []
        failedCount = 0
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
            guard album.title.trimmingCharacters(in: .whitespaces).isEmpty == false,
                  album.artist.trimmingCharacters(in: .whitespaces).isEmpty == false,
                  album.tracks.contains(where: { GenreMetadata.isMissing($0.genre) }) else {
                return nil
            }
            return DiscogsArtworkAlbumTarget(album: album)
        }
    }

    private func applyCandidate(
        _ candidate: DiscogsGenreCandidate,
        to album: DiscogsArtworkAlbumTarget
    ) {
        guard isApplying == false, let genre = candidate.primaryGenre else { return }
        applyTask?.cancel()
        let generation = UUID()
        applyGeneration = generation
        isApplying = true
        applyError = nil
        applyTask = Task { @MainActor in
            guard applyGeneration == generation, !Task.isCancelled else { return }
            let result = await actions.applyDiscogsGenres([
                DiscogsGenreAlbumSuggestion(album: album, genre: genre, evidence: candidate.evidence)
            ], clock: dependencies.clock)
            guard applyGeneration == generation else { return }
            isApplying = false
            switch result {
            case .success(let outcome): advanceReview(applied: outcome.appliedAlbums > 0)
            case .failure(let error):
                expireResults(at: dependencies.clock())
                if !review.requiresSearch { applyError = error.localizedDescription }
            }
        }
    }

    private func suggestedGenre(for item: ReviewItem) -> String? {
        DiscogsGenreSuggestionPolicy.suggestedGenre(
            from: item.candidates.map(\.genres)
        )
    }

    private func applyAllSuggestions() {
        guard isApplying == false else { return }
        let remainingItems = Array(reviewItems.dropFirst(reviewIndex))
        let suggestions = remainingItems.compactMap { item -> DiscogsGenreAlbumSuggestion? in
            guard let candidate = item.candidates.first(where: { $0.primaryGenre != nil }),
                  let genre = candidate.primaryGenre else { return nil }
            return DiscogsGenreAlbumSuggestion(album: item.album, genre: genre, evidence: candidate.evidence)
        }
        guard suggestions.isEmpty == false else { return }

        applyTask?.cancel()
        let generation = UUID()
        applyGeneration = generation
        isApplying = true
        applyError = nil

        applyTask = Task { @MainActor in
            guard applyGeneration == generation else { return }
            do {
                let result = try await actions.applyDiscogsGenres(suggestions, clock: dependencies.clock).get()
                guard applyGeneration == generation else { return }
                appliedCount += result.appliedAlbums
                skippedCount += result.skippedAlbums
                    + (remainingItems.count - suggestions.count)
                reviewIndex = reviewItems.count
                reviewItems = []
                isApplying = false
                phase = .complete
            } catch {
                guard applyGeneration == generation else { return }
                expireResults(at: dependencies.clock())
                if !review.requiresSearch { applyError = error.localizedDescription }
                isApplying = false
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

// MARK: - Flow layout for genre/style tags

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> Arrangement {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            sizes.append(size)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return Arrangement(
            size: CGSize(width: maxWidth, height: y + rowHeight),
            positions: positions,
            sizes: sizes
        )
    }

    private struct Arrangement {
        let size: CGSize
        let positions: [CGPoint]
        let sizes: [CGSize]
    }
}

// MARK: - Window presenter

@MainActor
public enum DiscogsGenreReviewWindowPresenter {
    private static var coordinator: DiscogsGenreReviewWindowCoordinator?

    public static func show(modelContext: ModelContext, actions: LibraryItemActionHandler, dependencies: DiscogsReviewDependencies = .live) {
        if let window = coordinator?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let coordinator = DiscogsGenreReviewWindowCoordinator()
        let rootView = DiscogsGenreReviewView(
            modelContext: modelContext,
            actions: actions,
            dependencies: dependencies,
            onDismiss: { [weak coordinator] in
                coordinator?.window?.close()
            }
        )
        let host = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: host)
        window.title = "Fix Missing Genre"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 480))
        window.contentMinSize = NSSize(width: 520, height: 400)
        window.isReleasedWhenClosed = false
        window.center()

        coordinator.window = window
        coordinator.onClose = {
            self.coordinator = nil
        }
        window.delegate = coordinator
        self.coordinator = coordinator

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class DiscogsGenreReviewWindowCoordinator: NSObject, NSWindowDelegate {
    weak var window: NSWindow?
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
