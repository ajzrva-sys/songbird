import SwiftUI
import SwiftData

/// Library health view for tracks with empty titles, with filename-based reconciliation.
public struct EmptyTitlesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var reviewItems: [FolderReconcileItem] = []
    @State private var showReview = false
    @State private var appliedCount = 0
    @State private var skippedCount = 0

    struct FolderReconcileItem: Identifiable {
        let track: Track
        let parsedTitle: String
        var id: UUID { track.id }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if showReview {
                reviewPhase
            } else if isLoading {
                Spacer()
                ProgressView("Scanning…")
                Spacer()
            } else if tracks.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Empty Titles",
                    systemImage: "textformat.abc",
                    description: Text("All library tracks have a title assigned.")
                )
                Spacer()
            } else {
                trackList
            }
        }
        .background(SongbirdTheme.background(for: colorScheme))
        .task { loadTracks() }
    }

    private var trackList: some View {
        List {
            Section {
                HStack {
                    Text("\(tracks.count) track\(tracks.count == 1 ? "" : "s") with empty title")
                        .font(.headline)
                    Spacer()
                    Button("Reconcile from Filenames…") {
                        startReconciliation()
                    }
                    .buttonStyle(.bordered)
                    .disabled(tracks.isEmpty)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            ForEach(tracks, id: \.id) { track in
                HStack(spacing: 8) {
                    Image(systemName: "textformat.abc")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text((track.path as NSString).lastPathComponent)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Text(track.path)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    if let parsed = Self.parseTitle(from: track.path) {
                        Text("→ \(parsed)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
    }

    // MARK: - Review phase

    private var reviewPhase: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reconcile Titles")
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

            if reviewItems.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "Nothing to Reconcile",
                    systemImage: "checkmark.circle",
                    description: Text("No titles could be parsed from filenames.")
                )
                Spacer()
                Button("Done") { showReview = false }
                    .keyboardShortcut(.return)
                    .padding()
            } else {
                List {
                    ForEach(reviewItems) { item in
                        FolderReconcileRow(
                            title: (item.track.path as NSString).lastPathComponent,
                            subtitle: item.track.artist,
                            parsedValue: item.parsedTitle,
                            onApply: { applyReviewItem(item) },
                            onSkip: { skipReviewItem(item) }
                        )
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
                        skippedCount += reviewItems.count
                        reviewItems = []
                        showReview = false
                    }
                    Button("Done") { showReview = false }
                        .keyboardShortcut(.return)
                }
                .padding()
            }
        }
    }

    // MARK: - Logic

    private func loadTracks() {
        let descriptor = FetchDescriptor<Track>(
            predicate: #Predicate { $0.title.isEmpty },
            sortBy: [SortDescriptor(\Track.path)]
        )
        do {
            tracks = try modelContext.fetch(descriptor)
        } catch {
            tracks = []
        }
        isLoading = false
    }

    private func startReconciliation() {
        appliedCount = 0
        skippedCount = 0
        reviewItems = tracks.compactMap { track in
            guard let title = Self.parseTitle(from: track.path) else { return nil }
            return FolderReconcileItem(track: track, parsedTitle: title)
        }
        showReview = true
    }

    private func applyReviewItem(_ item: FolderReconcileItem) {
        item.track.title = item.parsedTitle
        do {
            try modelContext.save()
            appliedCount += 1
            reviewItems.removeAll { $0.id == item.id }
            tracks.removeAll { $0.id == item.id }
            if reviewItems.isEmpty { showReview = false }
        } catch {
            modelContext.rollback()
            LibraryStatus.shared.showPlaybackError("Could not save title: \(error.localizedDescription)")
        }
    }

    private func skipReviewItem(_ item: FolderReconcileItem) {
        skippedCount += 1
        reviewItems.removeAll { $0.id == item.id }
        if reviewItems.isEmpty { showReview = false }
    }

    private func applyAll() {
        var applied = 0
        for item in reviewItems {
            item.track.title = item.parsedTitle
            applied += 1
        }
        do {
            try modelContext.save()
            appliedCount += applied
            LibraryStatus.shared.showNotice(
                "Set \(applied) title\(applied == 1 ? "" : "s") from filenames.",
                severity: .information,
                autoDismissAfter: 4
            )
            reviewItems = []
            tracks.removeAll { $0.title.isEmpty }
            showReview = false
        } catch {
            modelContext.rollback()
            LibraryStatus.shared.showPlaybackError("Could not save titles: \(error.localizedDescription)")
        }
    }

    /// Parses a display title from a file path.
    /// Strips extension, then tries to strip a leading track number pattern.
    static func parseTitle(from path: String) -> String? {
        let filename = (path as NSString).lastPathComponent
        let withoutExt = (filename as NSString).deletingPathExtension
        guard !withoutExt.isEmpty else { return nil }

        // Try stripping leading track number: "01 - Title" → "Title"
        let patterns = [
            try! NSRegularExpression(pattern: #"^\d{1,3}\s*[-._:]\s+"#),
            try! NSRegularExpression(pattern: #"^[Tt]rack\s+\d{1,3}\s*[-._:]?\s*"#),
            try! NSRegularExpression(pattern: #"^\d{1,3}\.\s+"#),
        ]
        for pattern in patterns {
            if let match = pattern.firstMatch(
                in: withoutExt,
                range: NSRange(withoutExt.startIndex..., in: withoutExt)
            ), let range = Range(match.range, in: withoutExt) {
                let stripped = withoutExt[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !stripped.isEmpty { return stripped }
            }
        }

        return withoutExt
    }
}
