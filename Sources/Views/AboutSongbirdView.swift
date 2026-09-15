import SwiftUI
import AppKit

/// Minimal About panel for Songbird.
public struct AboutSongbirdView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingLegal = false

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            if let image = NSImage(named: "AppIcon") ?? NSImage(named: "songbird-logo") {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 64, height: 64)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 40))
            }
            Text("Songbird")
                .font(.title2.bold())
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            Text("Local music player for macOS.\nPlayback powered by Songbird’s native audio engine.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Text("Copyright © 2026 Andrew Zimmerman\nGPL-3.0-or-later")
                .font(.caption)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Button("License, Notices & Source…") {
                showingLegal = true
            }
            .accessibilityIdentifier("legal.showDocuments")
            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 320)
        .sheet(isPresented: $showingLegal) {
            SongbirdLegalView()
        }
    }
}

private struct SongbirdLegalView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var contents = "Loading legal notices…"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("License, Notices & Source")
                .font(.headline)
            ScrollView {
                Text(contents)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("legal.contents")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("legal.close")
        }
        .padding()
        .frame(width: 640, height: 480)
        .task {
            do {
                contents = try LegalDocument.allCases.map {
                    $0.rawValue + "\n\n" + (try LegalResources.read($0))
                }.joined(separator: "\n\n────────\n\n")
            } catch {
                contents = "Legal resources are missing or unreadable. This package is incomplete."
            }
        }
    }
}
