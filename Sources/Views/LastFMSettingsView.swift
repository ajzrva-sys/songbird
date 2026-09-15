import AppKit
import SwiftUI

struct LastFMSettingsView: View {
    @AppStorage(LastFMClient.enabledKey) private var enabled = false
    @AppStorage(LastFMClient.usernameKey) private var username = ""
    @ObservedObject var client: LastFMClient = .shared
    @State private var sessionActive = false
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var tasks = ViewTaskSlot()

    var body: some View {
        Form {
            Toggle("Enable Last.fm", isOn: $enabled)
            if sessionActive {
                Label("Signed in as \(username)", systemImage: "checkmark.circle.fill")
                Button("Sign Out") {
                    tasks.start {
                        do {
                            try await client.signOut()
                            sessionActive = false
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            } else {
                switch client.authenticationState {
                case .authenticating:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Connecting to Last.fm…")
                    }
                case .awaitingAuthorization:
                    Text("Approve Songbird in your browser, then return here.")
                    HStack {
                        Button("Finish Sign In") { finishSignIn() }
                        Button("Cancel") { client.cancelBrowserAuthentication() }
                    }
                case .idle, .failed, .authenticated:
                    Button("Sign in with Last.fm…") {
                        errorMessage = nil
                        tasks.start {
                            guard let url = await client.beginBrowserAuthentication(),
                                  !Task.isCancelled else { return }
                            if !NSWorkspace.shared.open(url) {
                                client.browserCouldNotOpen()
                            }
                        }
                    }
                    .disabled(loading)
                    Text("Sign in and approve Songbird on Last.fm.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if case .failed(let message) = client.authenticationState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            Text("Scrobbles when a track passes the halfway point.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .task {
            defer { loading = false }
            do {
                sessionActive = try await client.hasStoredSession()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            finishSignIn()
        }
        .onAppear { tasks.activate() }
        .onDisappear { tasks.invalidate() }
    }

    private func finishSignIn() {
        guard client.authenticationState == .awaitingAuthorization else { return }
        tasks.start {
            await client.completeBrowserAuthentication()
            guard !Task.isCancelled else { return }
            if client.authenticationState == .authenticated {
                sessionActive = true
                enabled = true
            }
        }
    }
}
