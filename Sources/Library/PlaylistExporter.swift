import AppKit
import Foundation

public enum PlaylistExporter {
    @MainActor
    public static func exportM3U(playlist: Playlist, tracks: [Track]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(playlist.name).m3u"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            var lines = ["#EXTM3U"]
            for track in tracks {
                let seconds = Int(track.duration.rounded())
                lines.append("#EXTINF:\(seconds),\(track.artist) - \(track.title)")
                lines.append(track.path)
            }
            let contents = lines.joined(separator: "\n")
            Task { @MainActor in
                do {
                    try await LibraryFileIO.shared.write(contents, to: url)
                    LibraryStatus.shared.showNotice(
                        "Exported \(url.lastPathComponent) to \(url.deletingLastPathComponent().path).",
                        severity: .success,
                        autoDismissAfter: 4,
                        source: .fileIO
                    )
                } catch {
                    LibraryStatus.shared.showNotice(
                        "Could not export the playlist: \(error.localizedDescription)",
                        severity: .error,
                        source: .fileIO
                    )
                }
            }
        }
    }
}
