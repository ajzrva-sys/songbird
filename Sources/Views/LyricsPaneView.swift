import SwiftUI

public struct LyricsPaneView: View {
    private let target: LyricsTrackTarget
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var lyricsText: String?
    @State private var loadError: String?

    private var textColor: Color { SongbirdTheme.text(for: colorScheme) }
    private var secondaryColor: Color { SongbirdTheme.secondaryText(for: colorScheme) }

    @MainActor
    public init(track: Track) {
        target = LyricsTrackTarget(track: track)
    }

    init(target: LyricsTrackTarget) {
        self.target = target
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.title)
                        .font(.headline)
                        .foregroundColor(textColor)
                    Text(target.artist)
                        .font(.subheadline)
                        .foregroundColor(secondaryColor)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            Divider()
            ScrollView {
                if let loadError {
                    ContentUnavailableView(
                        "Lyrics Could Not Load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else if let lyricsText {
                    Text(lyricsText)
                        .font(.body)
                        .foregroundColor(textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else {
                    ProgressView("Loading Lyrics…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 360)
        .task(id: target.path) {
            let audioPath = target.path
            do {
                lyricsText = try await LibraryFileIO.shared.lyrics(forAudioPath: audioPath)
                    ?? "No lyrics found.\n\nPlace a .lrc or .txt file next to the audio with the same file name."
            } catch is CancellationError {
                return
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}
