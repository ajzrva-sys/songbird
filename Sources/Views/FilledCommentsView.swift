import SwiftUI
import SwiftData

/// Library health view showing tracks with filled comments, with junk detection and bulk clearing.
public struct FilledCommentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var items: [CommentItem] = []
    @State private var isLoading = true
    @State private var clearTarget: ClearTarget?

    private enum ClearTarget: Identifiable {
        case single(UUID)
        case junk
        case all

        var id: String {
            switch self {
            case .single(let id): "single:\(id)"
            case .junk: "junk"
            case .all: "all"
            }
        }
    }

    private struct CommentItem: Identifiable {
        let track: Track
        let isJunk: Bool
        var id: UUID { track.id }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Scanning…")
                Spacer()
            } else if items.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Filled Comments",
                    systemImage: "bubble.left.and.text.bubble.right",
                    description: Text("No library tracks have comment metadata.")
                )
                Spacer()
            } else {
                commentList
            }
        }
        .background(SongbirdTheme.background(for: colorScheme))
        .task { loadTracks() }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { clearTarget != nil },
                set: { if !$0 { clearTarget = nil } }
            ),
            presenting: clearTarget
        ) { target in
            switch target {
            case .single:
                Button("Clear Comment") { clearSingle() }
            case .junk:
                Button("Clear All Junk Comments") { clearJunk() }
            case .all:
                Button("Clear All Comments") { clearAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            switch target {
            case .single:
                Text("Remove this comment from the track?")
            case .junk:
                let junkCount = items.filter(\.isJunk).count
                Text("\(junkCount) comments match common junk patterns and will be cleared.")
            case .all:
                Text("All \(items.count) comments will be cleared. This cannot be undone.")
            }
        }
    }

    private var commentList: some View {
        List {
            Section {
                HStack {
                    let junkCount = items.filter(\.isJunk).count
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(items.count) track\(items.count == 1 ? "" : "s") with comments")
                            .font(.headline)
                        if junkCount > 0 {
                            Text("\(junkCount) detected as junk")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    if junkCount > 0 {
                        Button("Clear Junk…") {
                            clearTarget = .junk
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("Clear All…") {
                        clearTarget = .all
                    }
                    .buttonStyle(.bordered)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            ForEach(items) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.isJunk ? "exclamationmark.triangle.fill" : "bubble.left")
                        .foregroundStyle(item.isJunk ? .orange : .secondary)
                        .font(.caption)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.track.title.isEmpty ? (item.track.path as NSString).lastPathComponent : item.track.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if !item.track.artist.isEmpty {
                                Text(item.track.artist)
                                    .foregroundStyle(.secondary)
                            }
                            if !item.track.album.isEmpty {
                                Text(item.track.album)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 11))
                        .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(item.track.comment)
                            .font(.caption)
                            .foregroundStyle(item.isJunk ? .orange : .secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 200)
                    }

                    Button {
                        clearTarget = .single(item.track.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
    }

    private var confirmationTitle: String {
        switch clearTarget {
        case .single: "Clear Comment?"
        case .junk: "Clear Junk Comments?"
        case .all: "Clear All Comments?"
        case nil: ""
        }
    }

    // MARK: - Logic

    private func loadTracks() {
        let descriptor = FetchDescriptor<Track>(
            predicate: #Predicate { !$0.comment.isEmpty },
            sortBy: [SortDescriptor(\Track.artist), SortDescriptor(\Track.album)]
        )
        do {
            let tracks = try modelContext.fetch(descriptor)
            items = tracks.map { track in
                CommentItem(track: track, isJunk: Self.isJunkComment(track.comment))
            }
        } catch {
            items = []
        }
        isLoading = false
    }

    private func clearSingle() {
        guard case .single(let trackID) = clearTarget else { return }
        clearTarget = nil
        guard let track = items.first(where: { $0.track.id == trackID })?.track else { return }
        track.comment = ""
        do {
            try modelContext.save()
            items.removeAll { $0.id == trackID }
        } catch {
            modelContext.rollback()
            LibraryStatus.shared.showPlaybackError("Could not clear comment: \(error.localizedDescription)")
        }
    }

    private func clearJunk() {
        clearTarget = nil
        let junkItems = items.filter(\.isJunk)
        for item in junkItems {
            item.track.comment = ""
        }
        do {
            try modelContext.save()
            LibraryStatus.shared.showNotice(
                "Cleared \(junkItems.count) junk comment\(junkItems.count == 1 ? "" : "s").",
                severity: .information,
                autoDismissAfter: 4
            )
            items.removeAll { $0.isJunk }
        } catch {
            modelContext.rollback()
            LibraryStatus.shared.showPlaybackError("Could not clear comments: \(error.localizedDescription)")
        }
    }

    private func clearAll() {
        clearTarget = nil
        let count = items.count
        for item in items {
            item.track.comment = ""
        }
        do {
            try modelContext.save()
            LibraryStatus.shared.showNotice(
                "Cleared \(count) comment\(count == 1 ? "" : "s").",
                severity: .information,
                autoDismissAfter: 4
            )
            items = []
        } catch {
            modelContext.rollback()
            LibraryStatus.shared.showPlaybackError("Could not clear comments: \(error.localizedDescription)")
        }
    }

    /// Detects common junk comment patterns from rippers, download services, and players.
    static func isJunkComment(_ comment: String) -> Bool {
        let lower = comment.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return false }

        // URLs
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") {
            return true
        }

        // Common ripper/encoder signatures
        let junkPatterns = [
            "encoded by",
            "ripped by",
            "ripped with",
            "encoded with",
            "created with",
            "made with",
            "converted by",
            "processed by",
            "tagged with",
            "produced by lame",
            "lame",
            "exact audio copy",
            "eac ",
            "dbpoweramp",
            "foobar2000",
            "itunes",
            "windows media",
            "media monkey",
            "musicbrainz",
            "picard",
            "discogs",
            "freedb",
            "cddb",
            "www.",
            ".com",
            ".org",
            ".net",
            "visit us at",
            "downloaded from",
            "purchased from",
            "bought from",
            "available at",
            "get more at",
        ]

        for pattern in junkPatterns {
            if lower.contains(pattern) { return true }
        }

        // Pure numeric comments (often CD catalogue numbers or junk)
        if Int(lower) != nil { return true }

        // Very short random strings (1-3 chars) that aren't meaningful
        if lower.count <= 2 { return true }

        return false
    }
}
