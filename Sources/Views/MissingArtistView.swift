import SwiftUI
import SwiftData

/// Library health view for tracks missing artist metadata, with folder-based reconciliation.
public struct MissingArtistView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var reviewItems: [FolderReviewItem] = []
    @State private var showReview = false
    @State private var appliedCount = 0
    @State private var skippedCount = 0

    struct FolderReviewItem: Identifiable {
        let track: Track
        let parsedArtist: String
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
                    "No Unknown Artists",
                    systemImage: "person.crop.questionmark",
                    description: Text("All library tracks have an artist assigned.")
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
                    Text("\(tracks.count) track\(tracks.count == 1 ? "" : "s") missing artist")
                        .font(.headline)
                    Spacer()
                    Button("Reconcile from Folders…") {
                        startReconciliation()
                    }
                    .buttonStyle(.bordered)
                    .disabled(tracks.isEmpty)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            ForEach(tracks, id: \.id) { track in
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.questionmark")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title.isEmpty ? (track.path as NSString).lastPathComponent : track.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Text(track.path)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    if let parsed = Self.parseArtistFolder(from: track.path) {
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
                Text("Reconcile Artists")
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
                    description: Text("No artist names could be parsed from folders.")
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
                            subtitle: item.track.album,
                            parsedValue: item.parsedArtist,
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
            predicate: #Predicate {
                $0.artist.isEmpty || $0.artist == "Unknown Artist"
            },
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
            guard let artist = Self.parseArtistFolder(from: track.path) else { return nil }
            return FolderReviewItem(track: track, parsedArtist: artist)
        }
        showReview = true
    }

    private func applyReviewItem(_ item: FolderReviewItem) {
        item.track.artist = item.parsedArtist
        do {
            try modelContext.save()
            appliedCount += 1
            reviewItems.removeAll { $0.id == item.id }
            tracks.removeAll { $0.id == item.id }
            if reviewItems.isEmpty { showReview = false }
        } catch {
            modelContext.rollback()
            LibraryStatus.shared.showPlaybackError("Could not save artist: \(error.localizedDescription)")
        }
    }

    private func skipReviewItem(_ item: FolderReviewItem) {
        skippedCount += 1
        reviewItems.removeAll { $0.id == item.id }
        if reviewItems.isEmpty { showReview = false }
    }

    private func applyAll() {
        var applied = 0
        for item in reviewItems {
            item.track.artist = item.parsedArtist
            applied += 1
        }
        do {
            try modelContext.save()
            appliedCount += applied
            LibraryStatus.shared.showNotice(
                "Set \(applied) artist\(applied == 1 ? "" : "s") from folder names.",
                severity: .information,
                autoDismissAfter: 4
            )
            reviewItems = []
            tracks.removeAll { $0.artist.isEmpty || $0.artist == "Unknown Artist" }
            showReview = false
        } catch {
            modelContext.rollback()
            LibraryStatus.shared.showPlaybackError("Could not save artists: \(error.localizedDescription)")
        }
    }

    /// Extracts the grandparent folder name from a file path as the artist name.
    /// Assumes structure: .../Artist/Album/track.mp3
    /// Skips common non-artist folder names.
    static func parseArtistFolder(from path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let albumFolder = url.deletingLastPathComponent()
        let artistFolder = albumFolder.deletingLastPathComponent().lastPathComponent
        guard !artistFolder.isEmpty else { return nil }
        let lower = artistFolder.lowercased()
        let skipNames: Set<String> = [
            "music", "downloads", "audio", "media", "library",
            "itunes", "amarra", "home", "desktop", "documents",
        ]
        guard !skipNames.contains(lower) else { return nil }
        return artistFolder
    }
}
