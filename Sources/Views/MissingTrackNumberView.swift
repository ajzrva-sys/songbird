import SwiftUI
import SwiftData

/// Library health view for tracks missing track numbers, with title-based reconciliation.
public struct MissingTrackNumberView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var reviewItems: [ReviewItem] = []
    @State private var showReview = false
    @State private var appliedCount = 0
    @State private var skippedCount = 0

    struct ReviewItem: Identifiable {
        let track: Track
        let parsedNumber: Int
        let matchText: String
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
                    "No Missing Track Numbers",
                    systemImage: "number",
                    description: Text("All library tracks have a track number assigned.")
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
                    Text("\(tracks.count) track\(tracks.count == 1 ? "" : "s") missing track number")
                        .font(.headline)
                    Spacer()
                    Button("Reconcile from Titles…") {
                        startReconciliation()
                    }
                    .buttonStyle(.bordered)
                    .disabled(tracks.isEmpty)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            ForEach(tracks, id: \.id) { track in
                HStack(spacing: 8) {
                    Image(systemName: "number")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title.isEmpty ? (track.path as NSString).lastPathComponent : track.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if !track.artist.isEmpty {
                                Text(track.artist)
                                    .foregroundStyle(.secondary)
                            }
                            if !track.album.isEmpty {
                                Text(track.album)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 11))
                        .lineLimit(1)
                    }

                    Spacer()

                    if let parsed = Self.parseTrackNumber(from: track.title) {
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
                Text("Reconcile Track Numbers")
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
                    description: Text("No track numbers could be parsed from titles.")
                )
                Spacer()
                Button("Done") { showReview = false }
                    .keyboardShortcut(.return)
                    .padding()
            } else {
                List {
                    ForEach(reviewItems) { item in
                        FolderReconcileRow(
                            title: item.track.title.isEmpty
                                ? (item.track.path as NSString).lastPathComponent
                                : item.track.title,
                            subtitle: item.track.artist,
                            parsedValue: String(item.parsedNumber),
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
            predicate: #Predicate { $0.trackNumber == 0 },
            sortBy: [SortDescriptor(\Track.album), SortDescriptor(\Track.title)]
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
            guard let number = Self.parseTrackNumber(from: track.title) else { return nil }
            return ReviewItem(track: track, parsedNumber: number, matchText: track.title)
        }
        showReview = true
    }

    private func applyReviewItem(_ item: ReviewItem) {
        item.track.trackNumber = item.parsedNumber
        do {
            try modelContext.save()
            appliedCount += 1
            reviewItems.removeAll { $0.id == item.id }
            tracks.removeAll { $0.id == item.id }
            if reviewItems.isEmpty { showReview = false }
        } catch {
            modelContext.rollback()
            LibraryStatus.shared.showPlaybackError("Could not save track number: \(error.localizedDescription)")
        }
    }

    private func skipReviewItem(_ item: ReviewItem) {
        skippedCount += 1
        reviewItems.removeAll { $0.id == item.id }
        if reviewItems.isEmpty { showReview = false }
    }

    private func applyAll() {
        var applied = 0
        for item in reviewItems {
            item.track.trackNumber = item.parsedNumber
            applied += 1
        }
        do {
            try modelContext.save()
            appliedCount += applied
            LibraryStatus.shared.showNotice(
                "Set \(applied) track number\(applied == 1 ? "" : "s") from titles.",
                severity: .information,
                autoDismissAfter: 4
            )
            reviewItems = []
            tracks.removeAll { track in
                track.trackNumber > 0
            }
            showReview = false
        } catch {
            modelContext.rollback()
            LibraryStatus.shared.showPlaybackError("Could not save track numbers: \(error.localizedDescription)")
        }
    }

    /// Parses a leading track number from common title patterns:
    /// "01 - Title", "01. Title", "01 Title", "Track 01 - Title", etc.
    static func parseTrackNumber(from title: String) -> Int? {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Pattern 1: Leading digits followed by separator (dash, dot, underscore, colon)
        // "01 - Song", "01. Song", "1 - Song", "01_Song"
        let leadingPattern = try! NSRegularExpression(pattern: #"^(\d{1,3})\s*[-._:]\s+"#)
        if let match = leadingPattern.firstMatch(
            in: trimmed,
            range: NSRange(trimmed.startIndex..., in: trimmed)
        ), let range = Range(match.range(at: 1), in: trimmed) {
            return Int(trimmed[range])
        }

        // Pattern 2: "Track N" or "track N" prefix
        // "Track 01 - Song", "track 5. Song"
        let trackPrefixPattern = try! NSRegularExpression(pattern: #"^[Tt]rack\s+(\d{1,3})\s*[-._:]?\s*"#)
        if let match = trackPrefixPattern.firstMatch(
            in: trimmed,
            range: NSRange(trimmed.startIndex..., in: trimmed)
        ), let range = Range(match.range(at: 1), in: trimmed) {
            return Int(trimmed[range])
        }

        // Pattern 3: "N. Song" (digit + period + space)
        // "1. Song Name"
        let dotPattern = try! NSRegularExpression(pattern: #"^(\d{1,3})\.\s+"#)
        if let match = dotPattern.firstMatch(
            in: trimmed,
            range: NSRange(trimmed.startIndex..., in: trimmed)
        ), let range = Range(match.range(at: 1), in: trimmed) {
            return Int(trimmed[range])
        }

        return nil
    }
}
