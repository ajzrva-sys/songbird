import SwiftUI
import SwiftData

/// Library health view showing tracks with low bitrate, excluding lossless formats.
public struct LowBitrateView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var tracks: [Track] = []
    @State private var isLoading = true

    /// Bitrate threshold in kbps. Tracks below this (excluding lossless) are flagged.
    private static let threshold = 128

    /// Lossless file extensions that report 0 or misleading bitrate.
    private static let losslessExtensions: Set<String> = [
        "flac", "alac", "m4a", "wav", "aiff", "aif", "ape", "wv", "ogg",
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Scanning…")
                Spacer()
            } else if tracks.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Low Bitrate Tracks",
                    systemImage: "waveform.badge.minus",
                    description: Text("All lossy tracks are at least \(Self.threshold) kbps.")
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
                    Text("\(tracks.count) track\(tracks.count == 1 ? "" : "s") below \(Self.threshold) kbps")
                        .font(.headline)
                    Spacer()
                    Text("Lossless formats excluded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            ForEach(tracks, id: \.id) { track in
                HStack(spacing: 8) {
                    Image(systemName: "waveform.badge.minus")
                        .foregroundStyle(track.bitrate > 0 ? .orange : .secondary)
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

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(track.bitrate > 0 ? "\(track.bitrate) kbps" : "unknown")
                            .font(.caption)
                            .foregroundStyle(track.bitrate > 0 ? .orange : .secondary)
                        Text(track.fileKind)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
    }

    private func loadTracks() {
        let descriptor = FetchDescriptor<Track>(
            sortBy: [SortDescriptor(\Track.bitrate)]
        )
        do {
            let all = try modelContext.fetch(descriptor)
            tracks = all.filter { track in
                let ext = (track.path as NSString).pathExtension.lowercased()
                guard !Self.losslessExtensions.contains(ext) else { return false }
                return track.bitrate > 0 && track.bitrate < Self.threshold
            }
        } catch {
            tracks = []
        }
        isLoading = false
    }
}
