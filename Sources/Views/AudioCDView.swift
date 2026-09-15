import SwiftUI
import SwiftData

public struct AudioCDView: View {
    public let discID: DiscIdentifier

    @EnvironmentObject private var opticalDiscs: OpticalDiscService
    @EnvironmentObject private var playbackSession: PlaybackSession
    @EnvironmentObject private var playbackActivity: PlaybackActivity
    @EnvironmentObject private var queue: PlaybackQueue
    @EnvironmentObject private var importProgress: ImportProgressState
    @EnvironmentObject private var librarySelection: LibrarySelectionState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var ripCoordinator = AudioCDRipCoordinator()
    @State private var selectedTrackID: AudioDiscTrack.ID?
    @State private var showingError = false
    @State private var showingMetadataChoices = false

    public init(discID: DiscIdentifier) {
        self.discID = discID
    }

    public var body: some View {
        Group {
            if let disc = opticalDiscs.discs.first(where: { $0.id == discID }) {
                discContent(disc)
            } else {
                ContentUnavailableView(
                    "Disc Unavailable",
                    systemImage: "opticaldiscdrive",
                    description: Text("Insert the audio CD again to view its tracks.")
                )
            }
        }
        .background(SongbirdTheme.background(for: colorScheme))
        .onChange(of: opticalDiscs.lastError) { _, error in
            showingError = error != nil
        }
        .alert("Audio CD Error", isPresented: $showingError) {
            Button("Retry") {
                Task { await opticalDiscs.refresh() }
            }
            Button("OK", role: .cancel) {
                opticalDiscs.clearError()
            }
        } message: {
            Text(opticalDiscs.lastError?.localizedDescription ?? "The CD operation failed.")
        }
    }

    private func discContent(_ disc: AudioDisc) -> some View {
        VStack(spacing: 0) {
            HStack {
                if let artworkReference = disc.artworkReference {
                    ArtworkThumbnailView(
                        reference: artworkReference,
                        pointSize: CGSize(width: 44, height: 44),
                        accessibilityLabel: "Album artwork for \(disc.title)",
                        cornerRadius: 4,
                        placeholderSymbol: "opticaldisc"
                    )
                } else {
                    AudioCDIcon(
                        color: SongbirdTheme.secondaryText(for: colorScheme),
                        isRotating: disc.status == .importing
                            || (playbackActivity.status == .playing
                                && queue.currentTrack?.audioDiscID == disc.id)
                    )
                        .padding(8)
                        .frame(width: 44, height: 44)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let evidence = disc.discogsEvidence, let page = evidence.sourcePageURL {
                        DiscogsAttributionView(sourcePageURL: page)
                    }
                    Text(disc.title)
                        .font(.title3)
                        .bold()
                    Text("\(disc.tracks.count) tracks · \(format(totalDuration(disc)))")
                        .font(.caption)
                        .foregroundStyle(SongbirdTheme.secondaryText(for: colorScheme))
                }
                Spacer()
                if (opticalDiscs.metadataCandidates[disc.id]?.count ?? 0) > 1 {
                    Button("Change Metadata…", systemImage: "info.circle") {
                        showingMetadataChoices = true
                    }
                }
                Button {
                    ripCoordinator.start(
                        disc: disc,
                        modelContext: modelContext,
                        playbackEngine: playbackSession.engine,
                        opticalDiscs: opticalDiscs,
                        libraryStatus: LibraryStatus.shared
                    )
                } label: {
                    Label(
                        ripCoordinator.isImported ? "Imported" : (ripCoordinator.needsMetadataRecovery ? "Resume Import" : "Import CD"),
                        systemImage: ripCoordinator.isImported
                            ? "checkmark.circle.fill"
                            : "square.and.arrow.down"
                    )
                }
                .disabled(
                    ripCoordinator.isImported
                        || disc.tracks.isEmpty
                        || disc.status != .ready
                        || ripCoordinator.isRipping
                        || importProgress.value.isRunning
                )

                Button {
                    Task { await opticalDiscs.eject(disc) }
                } label: {
                    Label("Eject", systemImage: "eject.fill")
                }
                .disabled(disc.status == .ejecting || ripCoordinator.isRipping)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 80)
            // These are standard macOS push buttons, not accent-colored
            // actions. Reset the app-wide feather tint so AppKit/SwiftUI can
            // render the key and inactive window states in the correct order.
            .tint(nil)

            ripStatus
                .tint(nil)

            Divider()

            Table(disc.tracks, selection: $selectedTrackID) {
                TableColumn("#") { track in
                    Text("\(track.number)")
                        .foregroundStyle(SongbirdTheme.secondaryText(for: colorScheme))
                }
                .width(34)
                TableColumn("Title") { track in
                    HStack(spacing: 7) {
                        Image(systemName: isCurrent(track)
                            ? "speaker.wave.2.fill"
                            : "music.note")
                            .foregroundStyle(isCurrent(track)
                                ? Color.accentColor
                                : SongbirdTheme.secondaryText(for: colorScheme))
                        Text(track.title)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Track \(track.number), \(track.title), \(format(track.duration))")
                    .accessibilityValue(isCurrent(track) ? "Playing" : "Not playing")
                    .accessibilityAction(named: "Play") {
                        play(track, on: disc)
                    }
                }
                TableColumn("Time") { track in
                    Text(format(track.duration))
                        .monospacedDigit()
                        .foregroundStyle(SongbirdTheme.secondaryText(for: colorScheme))
                }
                .width(70)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: selectedTrackID) { _, _ in
                publishSelection(from: disc)
            }
            .onDisappear {
                if librarySelection.selectedTrack?.audioDiscID == disc.id {
                    librarySelection.selectedTrack = nil
                }
            }
            .onKeyPress(.return) {
                playSelected(on: disc)
                return .handled
            }
            .onKeyPress(.space) {
                playSelected(on: disc)
                return .handled
            }
            .contextMenu(forSelectionType: AudioDiscTrack.ID.self) { selection in
                Button("Play", systemImage: "play.fill") {
                    if let id = selection.first,
                       let track = disc.tracks.first(where: { $0.id == id }) {
                        play(track, on: disc)
                    }
                }
                .disabled(selection.isEmpty)
            } primaryAction: { selection in
                if let id = selection.first,
                   let track = disc.tracks.first(where: { $0.id == id }) {
                    play(track, on: disc)
                }
            }
            .sheet(isPresented: $showingMetadataChoices) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose CD Metadata").font(.headline)
                    List(opticalDiscs.metadataCandidates[disc.id] ?? []) { candidate in
                        VStack(alignment: .leading, spacing: 4) {
                            Button("Use \(candidate.title) — \(candidate.artist)") {
                                opticalDiscs.selectMetadata(candidate, for: disc.id)
                                showingMetadataChoices = false
                            }
                            if let evidence = candidate.discogsEvidence {
                                DiscogsAttributionView(sourcePageURL: evidence.sourcePageURL)
                            }
                        }
                    }
                    Button("Cancel") { showingMetadataChoices = false }
                        .keyboardShortcut(.cancelAction)
                }
                .padding().frame(width: 480, height: 320)
            }
        }
        .task(id: disc) {
            ripCoordinator.refreshImportStatus(for: disc, modelContext: modelContext)
        }
    }

    @ViewBuilder
    private var ripStatus: some View {
        if ripCoordinator.isRipping, let progress = ripCoordinator.progress {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(ripCoordinator.isCancelling
                        ? "Finishing the current drive read…"
                        : "Importing track \(progress.trackIndex) of \(progress.totalTracks)…")
                    Spacer()
                    Button("Cancel") { ripCoordinator.cancel() }
                        .disabled(ripCoordinator.isCancelling)
                }
                ProgressView(value: progress.fractionCompleted)
                    .accessibilityLabel("CD import progress")
                    .accessibilityValue("\(Int(progress.fractionCompleted * 100)) percent")
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(SongbirdTheme.nowPlayingBar(for: colorScheme))
        } else if ripCoordinator.isRipping {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing CD import…")
                Spacer()
                Button("Cancel") { ripCoordinator.cancel() }
                    .disabled(ripCoordinator.isCancelling)
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(SongbirdTheme.nowPlayingBar(for: colorScheme))
        } else if ripCoordinator.needsMetadataRecovery {
            VStack(alignment: .leading, spacing: 6) {
                Text("Discogs results expired. Completed audio was kept.")
                HStack {
                    Button("Refresh Metadata") { Task { await opticalDiscs.refresh() } }
                    Button("Use CD-Text and Resume") {
                        if let disc = opticalDiscs.discs.first(where: { $0.id == discID }) {
                            ripCoordinator.start(disc: disc.restoringOriginalMetadata(),
                                modelContext: modelContext, playbackEngine: playbackSession.engine,
                                opticalDiscs: opticalDiscs, libraryStatus: LibraryStatus.shared)
                        }
                    }
                }
            }
            .font(.caption)
            .padding(8)
        } else if let message = ripCoordinator.completionMessage {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(message)
                Spacer()
                Button("Dismiss") { ripCoordinator.clearMessages() }
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(SongbirdTheme.nowPlayingBar(for: colorScheme))
        } else if let error = ripCoordinator.lastError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("CD import failed: \(error)")
                Spacer()
                Button("Dismiss") { ripCoordinator.clearMessages() }
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(SongbirdTheme.nowPlayingBar(for: colorScheme))
        }
    }

    private func play(_ selected: AudioDiscTrack?, on disc: AudioDisc) {
        guard let selected,
              let index = disc.tracks.firstIndex(where: { $0.id == selected.id }) else { return }
        let transient = disc.tracks.map {
            Track.transientAudioCDTrack(
                $0,
                album: disc.title,
                artworkURL: disc.artworkURL,
                discogsEvidence: disc.discogsEvidence,
                originalMetadata: disc.originalMetadata.trackMetadata(for: $0.number)
            )
        }
        _ = playbackSession.startReplacement(PlaybackStartRequest(
            tracks: transient,
            startingAt: index
        ))
    }

    private func playSelected(on disc: AudioDisc) {
        guard let selectedTrackID,
              let track = disc.tracks.first(where: { $0.id == selectedTrackID }) else { return }
        play(track, on: disc)
    }

    private func publishSelection(from disc: AudioDisc) {
        guard let selectedTrackID,
              let track = disc.tracks.first(where: { $0.id == selectedTrackID }) else {
            if librarySelection.selectedTrack?.audioDiscID == disc.id {
                librarySelection.selectedTrack = nil
            }
            return
        }
        librarySelection.selectedTrack = Track.transientAudioCDTrack(
            track,
            album: disc.title,
            artworkURL: disc.artworkURL,
            discogsEvidence: disc.discogsEvidence,
            originalMetadata: disc.originalMetadata.trackMetadata(for: track.number)
        )
    }

    private func isCurrent(_ track: AudioDiscTrack) -> Bool {
        queue.currentTrack?.audioCDSource == track.source
    }

    private func totalDuration(_ disc: AudioDisc) -> TimeInterval {
        disc.tracks.reduce(0) { $0 + $1.duration }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
