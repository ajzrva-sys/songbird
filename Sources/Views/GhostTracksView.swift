import AppKit
import SwiftUI

public enum FileHealthMode: Equatable, Sendable {
    case missing
    case unavailable
}

/// Library health view for tracks whose files are missing from disk,
/// with bulk removal and file-location actions.
public struct GhostTracksView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var importProgress: ImportProgressState
    @EnvironmentObject private var libraryActions: LibraryItemActionHandler
    @EnvironmentObject private var librarySnapshots: LibrarySnapshotStore
    @State private var tracks: [LibraryTrackSnapshot] = []
    @State private var unavailableReasons: [UUID: FileUnavailableReason] = [:]
    @State private var isLoading = true
    @State private var removeTarget: RemoveTarget?
    @State private var isLocating = false
    @State private var locateResult: String?
    @State private var availabilityRevision = 0
    private let fileAvailabilityWorker: FileAvailabilityWorker
    private let mode: FileHealthMode

    private struct LoadID: Equatable {
        let snapshotRevision: Int
        let availabilityRevision: Int
    }

    private enum RemoveTarget: Identifiable {
        case single(UUID)
        case all

        var id: String {
            switch self {
            case .single(let id): "single:\(id)"
            case .all: "all"
            }
        }
    }

    public init(
        mode: FileHealthMode = .missing,
        fileAvailabilityWorker: FileAvailabilityWorker = FileAvailabilityWorker()
    ) {
        self.mode = mode
        self.fileAvailabilityWorker = fileAvailabilityWorker
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Scanning…")
                Spacer()
            } else if tracks.isEmpty {
                Spacer()
                ContentUnavailableView(
                    mode == .missing ? "No Missing Files" : "No Unavailable Volumes",
                    systemImage: mode == .missing
                        ? "doc.questionmark"
                        : "externaldrive.badge.checkmark",
                    description: Text(
                        mode == .missing
                            ? "All files on available library volumes are present."
                            : "All configured library volumes are available."
                    )
                )
                Spacer()
            } else {
                trackList
            }
        }
        .background(SongbirdTheme.background(for: colorScheme))
        .task(id: LoadID(
            snapshotRevision: librarySnapshots.snapshot.revision,
            availabilityRevision: availabilityRevision
        )) {
            await loadTracks()
        }
        .onChange(of: importProgress.value.phase) { previous, current in
            if GhostTracksRefreshPolicy.shouldRefresh(from: previous, to: current) {
                availabilityRevision &+= 1
            }
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.didMountNotification
            )
        ) { _ in
            availabilityRevision &+= 1
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.didUnmountNotification
            )
        ) { _ in
            availabilityRevision &+= 1
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            availabilityRevision &+= 1
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { removeTarget != nil },
                set: { if !$0 { removeTarget = nil } }
            ),
            presenting: removeTarget
        ) { target in
            if mode == .missing {
                switch target {
                case .single:
                    Button("Remove from Library") { removeSingle() }
                case .all:
                    Button("Remove All Missing Tracks") { removeAll() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            switch target {
            case .single:
                Text("Remove this track from the library? The audio file is already missing.")
            case .all:
                Text("\(tracks.count) tracks with missing files will be removed from the library. Audio files are not deleted.")
            }
        }
    }

    private var trackList: some View {
        List {
            Section {
                HStack {
                    Text(headerText)
                        .font(.headline)
                    Spacer()
                    if mode == .missing, isLocating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    }
                    if mode == .missing {
                        Button("Locate Files…") {
                            locateFiles()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLocating)
                        Button("Remove All…") {
                            removeTarget = .all
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Retry") {
                            availabilityRevision &+= 1
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                if let locateResult {
                    Text(locateResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                }
            }

            ForEach(tracks, id: \.id) { track in
                HStack(spacing: 8) {
                    Image(systemName: mode == .missing
                        ? "doc.questionmark"
                        : "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.orange)
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
                        Text(track.path)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if mode == .unavailable,
                           let reason = unavailableReasons[track.id] {
                            Text(reason.message)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if mode == .missing {
                        Button {
                            removeTarget = .single(track.id)
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
    }

    private var headerText: String {
        switch mode {
        case .missing:
            "\(tracks.count) track\(tracks.count == 1 ? "" : "s") with missing files"
        case .unavailable:
            "\(tracks.count) track\(tracks.count == 1 ? "" : "s") on unavailable volumes"
        }
    }

    private var confirmationTitle: String {
        switch removeTarget {
        case .single: "Remove Track?"
        case .all: "Remove All Missing Tracks?"
        case nil: ""
        }
    }

    // MARK: - Logic

    private func loadTracks() async {
        isLoading = true
        let all = librarySnapshots.snapshot.tracks.sorted { $0.path < $1.path }
        let requests = all.map { FileAvailabilityRequest(id: $0.id, path: $0.path) }
        let availability = await fileAvailabilityWorker.availability(requests)
        guard Task.isCancelled == false else { return }
        switch mode {
        case .missing:
            tracks = all.filter { availability.missingIDs.contains($0.id) }
            unavailableReasons = [:]
        case .unavailable:
            unavailableReasons = availability.unavailableReasons
            tracks = all.filter { availability.unavailableReasons[$0.id] != nil }
        }
        isLoading = false
    }

    private func removeSingle() {
        guard mode == .missing else { return }
        guard case .single(let trackID) = removeTarget else { return }
        removeTarget = nil
        guard tracks.contains(where: { $0.id == trackID }) else { return }
        if case .success = libraryActions.deleteTracks(trackIDs: [trackID]) {
            tracks.removeAll { $0.id == trackID }
        }
    }

    private func removeAll() {
        guard mode == .missing else { return }
        removeTarget = nil
        let count = tracks.count
        let trackIDs = tracks.map(\.id)
        if case .success = libraryActions.deleteTracks(trackIDs: trackIDs) {
            LibraryStatus.shared.showNotice(
                "Removed \(count) missing track\(count == 1 ? "" : "s") from the library.",
                severity: .information,
                autoDismissAfter: 4
            )
            tracks = []
        }
    }

    private func locateFiles() {
        guard mode == .missing else { return }
        isLocating = true
        locateResult = nil
        let container = librarySnapshots.modelContainer
        Task {
            let service = LibraryMaintenanceService(modelContainer: container)
            let roots = libraryFolderPaths()
            let found = try? await service.locateMissingTracks(searchRoots: roots)
            await MainActor.run {
                isLocating = false
                if let found, found > 0 {
                    locateResult = "Relocated \(found) track\(found == 1 ? "" : "s") by filename."
                    availabilityRevision &+= 1
                } else {
                    locateResult = "No missing tracks could be located in the library folders."
                }
            }
        }
    }

    private func libraryFolderPaths() -> [String] {
        // Reuse the same logic as Settings — read from the import exclusion store
        // or fall back to the standard Music directory.
        let musicDir = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
        return [musicDir?.path].compactMap { $0 }
    }
}

struct GhostTracksRefreshPolicy {
    static func shouldRefresh(
        from previous: LibraryOperationPhase,
        to current: LibraryOperationPhase
    ) -> Bool {
        let wasRunning = previous == .running || previous == .cancelling
        let isRunning = current == .running || current == .cancelling
        return wasRunning && isRunning == false
    }
}
