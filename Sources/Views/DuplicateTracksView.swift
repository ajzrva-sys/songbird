import SwiftUI
import SwiftData

/// Browsable view showing duplicate track groups with per-group and bulk removal.
public struct DuplicateTracksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var actionHandler: LibraryItemActionHandler
    @State private var duplicateGroups: [[DuplicateTrackCandidate]] = []
    @State private var isLoading = true
    @State private var isAnalyzing = false
    @State private var analyzeProgress = 0
    @State private var analyzeTotal = 0
    @State private var tasks = ViewTaskSlot()
    @State private var removalTarget: RemovalTarget?
    @State private var keeperByChecksum: [String: UUID] = [:]
    @State private var isApplying = false
    @State private var notice: String?

    private enum RemovalTarget: Identifiable {
        case group([DuplicateTrackCandidate])

        var id: String {
            switch self {
            case .group(let tracks): "group:\(tracks.first?.checksum ?? "")"
            }
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duplicate Tracks").font(.title2.weight(.semibold))
                    if isLoading == false {
                        Text("\(duplicateGroups.count) verified group\(duplicateGroups.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(16)
            Divider()
            if isAnalyzing {
                analyzeProgressBanner
            }
            if let notice {
                HStack {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if actionHandler.healthUndoAvailable {
                        Button("Undo") { undoLatestDuplicateChange() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if isLoading {
                Spacer()
                ProgressView("Scanning for duplicates…")
                Spacer()
            } else if duplicateGroups.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Duplicate Tracks",
                    systemImage: "doc.on.doc",
                    description: Text("No tracks share the same content checksum.")
                )
                Spacer()
            } else {
                duplicateList
            }
        }
        .background(SongbirdTheme.background(for: colorScheme))
        .task { await loadGroups() }
        .confirmationDialog(
            removalConfirmationTitle,
            isPresented: Binding(
                get: { removalTarget != nil },
                set: { if !$0 { removalTarget = nil } }
            ),
            presenting: removalTarget
        ) { target in
            switch target {
            case .group:
                Button("Remove Other Copies") { removeGroup() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            switch target {
            case .group(let tracks):
                Text("\(tracks.count) tracks share the same content. The copy marked Keep remains; audio files are not deleted.")
            }
        }
    }

    private var analyzeProgressBanner: some View {
        VStack(spacing: 4) {
            ProgressView(
                value: Double(analyzeProgress),
                total: Double(max(analyzeTotal, 1))
            )
            Text(
                analyzeTotal > 0
                    ? "Computing checksums: \(analyzeProgress) of \(analyzeTotal) tracks…"
                    : "Preparing…"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var duplicateList: some View {
        List {
            Section {
                HStack {
                    Text("\(duplicateGroups.count) duplicate group\(duplicateGroups.count == 1 ? "" : "s")")
                        .font(.headline)
                    Spacer()
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            ForEach(Array(duplicateGroups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group.sorted(by: { $0.dateAdded < $1.dateAdded }), id: \.id) { track in
                        DuplicateTrackRow(
                            track: track,
                            isKeeper: keeperID(for: group) == track.id,
                            chooseKeeper: { keeperByChecksum[track.checksum] = track.id }
                        )
                    }
                } header: {
                    HStack {
                        Text(groupHeader(group))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Button("Remove Other Copies…") {
                            removalTarget = .group(group)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func groupHeader(_ group: [DuplicateTrackCandidate]) -> String {
        let track = group.first!
        let title = track.title.isEmpty ? (track.path as NSString).lastPathComponent : track.title
        let size = ByteCountFormatter.string(fromByteCount: track.fileSize, countStyle: .file)
        return "\(title) · \(group.count) copies · \(size)"
    }

    private var removalConfirmationTitle: String {
        switch removalTarget {
        case .group: "Remove Duplicate Copies?"
        case nil: ""
        }
    }

    private func loadGroups() async {
        let container = modelContext.container
        let needsChecksums = await needsChecksumComputation(container: container)
        if needsChecksums {
            await computeChecksums(container: container)
        }
        let groups: [[DuplicateTrackCandidate]] = await MainActor.run {
            LibraryHygiene.duplicateGroups(in: ModelContext(container)).map { group in
                group.map(DuplicateTrackCandidate.init)
            }
        }
        await MainActor.run {
            duplicateGroups = groups
            for group in groups {
                if let checksum = group.first?.checksum,
                   keeperByChecksum[checksum] == nil,
                   let earliest = group.min(by: { $0.dateAdded < $1.dateAdded }) {
                    keeperByChecksum[checksum] = earliest.id
                }
            }
            isLoading = false
        }
    }

    private func needsChecksumComputation(container: ModelContainer) async -> Bool {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.checksum.isEmpty })
        descriptor.fetchLimit = 1
        let empty = (try? context.fetch(descriptor)) ?? []
        return !empty.isEmpty
    }

    private func computeChecksums(container: ModelContainer) async {
        await MainActor.run { isAnalyzing = true }
        defer { Task { @MainActor in isAnalyzing = false } }
        _ = try? await DuplicateAnalysisService.analyze(container: container) { completed, total in
            await MainActor.run {
                analyzeProgress = completed
                analyzeTotal = total
            }
        }
    }

    private func removeGroup() {
        guard case .group(let group) = removalTarget else { return }
        removalTarget = nil
        guard let checksum = group.first?.checksum,
              let keeperID = keeperByChecksum[checksum] else { return }
        isApplying = true
        Task { @MainActor in
            let result = await actionHandler.consolidateDuplicateTracks(
                trackIDs: group.map(\.id),
                keeperID: keeperID,
                expectedChecksum: checksum
            )
            isApplying = false
            if case .success(let outcome) = result {
                notice = "Removed \(outcome.affectedTrackCount) duplicate catalog record\(outcome.affectedTrackCount == 1 ? "" : "s"). Files were not changed."
                reloadSnapshotGroups()
            }
        }
    }

    private func undoLatestDuplicateChange() {
        isApplying = true
        Task { @MainActor in
            let result = await actionHandler.undoLatestHealthMutation()
            isApplying = false
            if case .success(let outcome) = result {
                notice = "Restored \(outcome.affectedTrackCount) duplicate catalog record\(outcome.affectedTrackCount == 1 ? "" : "s")."
                await loadGroups()
            }
        }
    }

    private func reloadSnapshotGroups() {
        duplicateGroups = LibraryHygiene.duplicateGroups(in: modelContext).map { group in
            group.map(DuplicateTrackCandidate.init)
        }
    }

    private func keeperID(for group: [DuplicateTrackCandidate]) -> UUID? {
        guard let checksum = group.first?.checksum else { return nil }
        return keeperByChecksum[checksum]
            ?? group.min(by: { $0.dateAdded < $1.dateAdded })?.id
    }
}

private struct DuplicateTrackRow: View {
    let track: DuplicateTrackCandidate
    let isKeeper: Bool
    let chooseKeeper: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            if isKeeper {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .help("This catalog copy will be kept")
            } else {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

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
                Text(track.path)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(isKeeper ? "Keep" : "Keep This Copy", action: chooseKeeper)
                .buttonStyle(.borderless)
                .disabled(isKeeper)

            VStack(alignment: .trailing, spacing: 2) {
                Text(track.dateAdded, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ByteCountFormatter.string(fromByteCount: track.fileSize, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DuplicateTrackCandidate: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let path: String
    let checksum: String
    let fileSize: Int64
    let dateAdded: Date

    @MainActor
    init(_ track: Track) {
        id = track.id
        title = track.title
        artist = track.artist
        album = track.album
        path = track.path
        checksum = track.checksum
        fileSize = track.fileSize
        dateAdded = track.dateAdded
    }
}
