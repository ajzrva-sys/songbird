import SwiftUI
import SwiftData

/// Library health view for tracks missing year metadata, with Discogs-based reconciliation.
public struct MissingYearView: View {
    @EnvironmentObject private var libraryActions: LibraryItemActionHandler
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    private let dependencies: DiscogsReviewDependencies

    @State private var albums: [Album] = []
    @State private var isLoading = true
    @State private var phase: Phase = .idle
    @State private var review = DiscogsReviewState<SearchResult>(evidence: { [$0.evidence] })
    @State private var isApplying = false
    private var searchResults: [SearchResult] {
        get { review.items }
        nonmutating set { review.items = newValue }
    }
    @State private var currentAlbumTitle = ""
    @State private var completedCount = 0
    @State private var totalCount = 0
    @State private var appliedCount = 0
    @State private var skippedCount = 0
    @State private var failedCount = 0
    @State private var searchTasks = ViewTaskSlot()

    private enum Phase: Equatable {
        case idle
        case searching
        case review
        case complete
        case error(String)
    }

    typealias SearchResult = DiscogsYearSuggestion

    private static let minimumRequestInterval: TimeInterval = 2.1

    public init(dependencies: DiscogsReviewDependencies = .live) {
        self.dependencies = dependencies
        _review = State(initialValue: DiscogsReviewState(clock: dependencies.clock, evidence: { [$0.evidence] }))
    }

    public var body: some View {
        DiscogsFreshnessView(clock: dependencies.clock, onTick: expireResults) { content }
    }

    private var content: some View {
        VStack(spacing: 0) {
            switch phase {
            case .idle:
                albumList
            case .searching:
                searchingView
            case .review:
                reviewView
            case .complete:
                completeView
            case .error(let message):
                errorView(message)
            }
        }
        .background(SongbirdTheme.background(for: colorScheme))
        .task { loadAlbums() }
        .onDisappear {
            review.invalidate()
            searchTasks.invalidate()
        }
    }

    // MARK: - Album list

    private var albumList: some View {
        List {
            Section {
                HStack {
                    Text("\(albums.count) album\(albums.count == 1 ? "" : "s") missing year")
                        .font(.headline)
                    Spacer()
                    Button("Lookup on Discogs…") {
                        startSearch()
                    }
                    .buttonStyle(.bordered)
                    .disabled(albums.isEmpty)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            ForEach(albums, id: \.id) { album in
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.title.isEmpty ? "Unknown Album" : album.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Text(album.artist.isEmpty ? "Unknown Artist" : album.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("\(album.tracks.count) track\(album.tracks.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
    }

    // MARK: - Searching

    private var searchingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Searching Discogs…")
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
                searchTasks.invalidate()
                phase = .idle
            }
            .keyboardShortcut(.cancelAction)
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Review

    private var reviewView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review \(searchResults.count) album\(searchResults.count == 1 ? "" : "s")")
                    .font(.headline)
                Spacer()
                Text("Applied \(appliedCount) · Skipped \(skippedCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 4)

            Divider().padding(.horizontal)

            List {
                ForEach(searchResults) { result in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.album.title.isEmpty ? "Unknown Album" : result.album.title)
                                .font(.system(size: 13))
                                .lineLimit(1)
                            Text(result.album.artist.isEmpty ? "Unknown Artist" : result.album.artist)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text("→ \(result.year)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.blue)

                        DiscogsAttributionView(sourcePageURL: result.sourcePageURL)

                        Button("Apply") { applyResult(result) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("Skip") { skipResult(result) }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)

            Divider()
            HStack {
                Button("Apply All") { applyAll() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Skip Remaining") {
                    skippedCount += searchResults.count
                    searchResults = []
                    phase = .complete
                }
                Button("Done") { resetToIdle() }
                    .keyboardShortcut(.return)
            }
            .padding()
        }
        .disabled(isApplying)
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
            Text("Applied \(appliedCount) · Skipped \(skippedCount) · Failed \(failedCount)")
                .foregroundStyle(.secondary)
            Button("Close") { resetToIdle() }
                .keyboardShortcut(.return)
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Search Stopped")
                .font(.title2)
            Text(message).foregroundStyle(.secondary)
            if review.requiresSearch { Button("Search again") { startSearch() } }
            Button("Close") { resetToIdle() }
                .keyboardShortcut(.return)
            Spacer()
        }
    }

    // MARK: - Logic

    private func loadAlbums() {
        let descriptor = FetchDescriptor<Album>(sortBy: [SortDescriptor(\Album.title)])
        do {
            let all = try modelContext.fetch(descriptor)
            albums = all.filter { $0.year == 0 }
        } catch {
            albums = []
        }
        isLoading = false
    }

    private func startSearch() {
        phase = .searching
        searchResults = []
        appliedCount = 0
        skippedCount = 0
        failedCount = 0
        completedCount = 0
        totalCount = albums.count
        searchTasks.activate()
        let generation = review.beginSearch(targets: albums.map(DiscogsArtworkAlbumTarget.init(album:)))
        searchTasks.start { await performSearch(generation: generation) }
    }

    private func performSearch(generation: UUID) async {
        let targets = review.targets

        var results: [SearchResult] = []
        var lastRequestDate: Date?

        for (index, album) in targets.enumerated() {
            guard !Task.isCancelled else { return }

            await MainActor.run {
                currentAlbumTitle = album.title
                completedCount = index
            }

            let query = DiscogsArtworkSearchQuery(
                albumTitle: album.title,
                albumArtist: album.artist,
                year: nil
            )

            // Check cache first — if we already searched this album, reuse the year.
            let cached: DiscogsArtworkSearchCache.Hit?
            do { cached = try await dependencies.cachedCandidates(for: query) }
            catch is CancellationError { return }
            catch { showExpiredResults(); return }
            if let cached,
               let first = cached.value.first(where: { $0.year != nil && $0.year! > 0 }) {
                guard !Task.isCancelled else { return }
                results.append(SearchResult(album: album, year: first.year!, evidence: first.evidence))
                continue
            }

            // Rate limit.
            if let lastRequestDate {
                let elapsed = Date().timeIntervalSince(lastRequestDate)
                let delay = Self.minimumRequestInterval - elapsed
                if delay > 0 {
                    do { try await Task.sleep(for: .seconds(delay)) }
                    catch is CancellationError { return }
                    catch { return }
                }
            }

            lastRequestDate = Date()
            do {
                let page = try await dependencies.search(query, page: 1)
                try Task.checkCancellation()
                let top = Array(page.candidates.prefix(5))
                try await dependencies.storeCandidates(top, for: query, fetches: [page.fetchedAt])
                guard !Task.isCancelled else { return }
                if let candidate = top.first(where: { $0.year != nil && $0.year! > 0 }), let year = candidate.year {
                    results.append(SearchResult(album: album, year: year, evidence: candidate.evidence))
                } else {
                    failedCount += 1
                }
            } catch is CancellationError {
                return
            } catch LibraryHealthMutationError.remoteEvidenceExpired {
                showExpiredResults()
                return
            } catch DiscogsError.tokenInvalid, DiscogsError.tokenMissing {
                await MainActor.run { phase = .error("Discogs token is invalid or missing.") }
                return
            } catch DiscogsError.rateLimited(let retryAfter) {
                let delay = max(retryAfter ?? 60, 60)
                await MainActor.run { currentAlbumTitle = "Rate limited — pausing \(Int(delay))s" }
                do { try await Task.sleep(for: .seconds(delay)) }
                catch is CancellationError { return }
                catch { return }
            } catch {
                failedCount += 1
            }

            await MainActor.run { completedCount = index + 1 }
        }

        guard !Task.isCancelled else { return }
        await MainActor.run {
            guard review.publish(results, generation: generation) else {
                if review.requiresSearch { showExpiredResults() }
                return
            }
            phase = searchResults.isEmpty ? .complete : .review
        }
    }

    private func applyResult(_ result: SearchResult) { applyResults([result]) }

    private func applyResults(_ results: [SearchResult]) {
        guard !isApplying else { return }
        isApplying = true
        let generation = review.generation
        review.task = Task { @MainActor in
            guard review.generation == generation, !Task.isCancelled else { return }
            let outcome = await libraryActions.applyDiscogsYears(results, clock: dependencies.clock)
            guard review.generation == generation else { return }
            isApplying = false
            switch outcome {
            case .success(let value):
                appliedCount += value.appliedAlbums
                skippedCount += value.skippedAlbums
                let ids = Set(results.map(\.id))
                searchResults.removeAll { ids.contains($0.id) }
                albums.removeAll { ids.contains($0.id) }
                if searchResults.isEmpty { phase = .complete }
            case .failure(let error):
                expireResults(at: dependencies.clock())
                if !review.requiresSearch { LibraryStatus.shared.showPlaybackError(error.localizedDescription) }
            }
        }
    }

    private func skipResult(_ result: SearchResult) {
        skippedCount += 1
        searchResults.removeAll { $0.id == result.id }
        if searchResults.isEmpty { phase = .complete }
    }

    private func applyAll() { applyResults(searchResults) }

    private func expireResults(at now: DiscogsFetchStamp?) {
        if review.expire(at: now) { showExpiredResults() }
    }

    private func showExpiredResults() {
        review.requiresSearch = true
        review.invalidate()
        searchTasks.invalidate()
        isApplying = false
        phase = .error("Discogs results expired. Search again.")
    }

    private func resetToIdle() {
        review.invalidate()
        isApplying = false
        phase = .idle
        searchResults = []
        loadAlbums()
    }
}
