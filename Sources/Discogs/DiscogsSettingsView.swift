import SwiftUI

public enum DiscogsCredentialState: Equatable {
    case loading
    case missing
    case loaded
    case editingReplacement
    case testing
    case failed(String)
}

public struct DiscogsSettingsView: View {
    @State private var token = ""
    @State private var savedToken = ""
    @State private var state = DiscogsCredentialState.loading
    @State private var statusMessage = ""
    @State private var credentialTasks = ViewTaskSlot()

    public init() {}

    public var body: some View {
        Form {
            Section("Authentication") {
                HStack {
                    SecureField("Personal Access Token", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .disabled(state == .loaded || state == .testing || state == .loading)

                    credentialButtons
                }

                HStack {
                    Button("Test Connection", action: testConnection)
                        .disabled(
                            token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || state == .testing
                                || state == .loading
                        )
                    if state == .testing || state == .loading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            if statusMessage.isEmpty == false {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsFailure ? .red : .secondary)
            }

            Section {
                Link(
                    "Get a personal access token",
                    destination: URL(string: "https://www.discogs.com/settings/developers")!
                )
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await loadCredential() }
        .onAppear { credentialTasks.activate() }
        .onDisappear { credentialTasks.invalidate() }
    }

    @ViewBuilder
    private var credentialButtons: some View {
        switch state {
        case .loaded, .testing:
            Button("Change Token") {
                state = .editingReplacement
                statusMessage = "Enter the replacement token, then save it."
            }
            .disabled(state == .testing)
            Button("Remove Token", action: removeToken)
                .disabled(state == .testing)
        case .editingReplacement:
            Button("Cancel") {
                token = savedToken
                state = .loaded
                statusMessage = ""
            }
            Button("Save Token", action: saveToken)
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        case .missing, .failed:
            Button("Save Token", action: saveToken)
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        case .loading:
            EmptyView()
        }
    }

    private var statusIsFailure: Bool {
        if case .failed = state { return true }
        return false
    }

    @MainActor
    private func loadCredential() async {
        state = .loading
        do {
            let loaded = try await DiscogsKeychain.load()
            try Task.checkCancellation()
            token = loaded
            savedToken = loaded
            state = .loaded
        } catch is CancellationError {
            return
        } catch is DiscogsKeychain.KeychainError {
            guard Task.isCancelled == false else { return }
            token = ""
            savedToken = ""
            state = .missing
        } catch {
            guard Task.isCancelled == false else { return }
            state = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    private func saveToken() {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        state = .loading
        statusMessage = "Saving token…"
        let started = credentialTasks.start {
            do {
                try await DiscogsKeychain.save(token: trimmed)
                try Task.checkCancellation()
                guard try await DiscogsKeychain.load() == trimmed else {
                    throw SongbirdCredentialStoreError.verificationFailed
                }
                try Task.checkCancellation()
                token = trimmed
                savedToken = trimmed
                state = .loaded
                statusMessage = "Token saved."
            } catch is CancellationError {
                return
            } catch {
                guard Task.isCancelled == false else { return }
                state = .failed(error.localizedDescription)
                statusMessage = "Could not save the token: \(error.localizedDescription)"
            }
        }
        if started == false {
            state = savedToken.isEmpty ? .missing : .loaded
            statusMessage = ""
        }
    }

    private func removeToken() {
        state = .loading
        statusMessage = "Removing token…"
        let started = credentialTasks.start {
            do {
                try await DiscogsKeychain.delete()
                try Task.checkCancellation()
                token = ""
                savedToken = ""
                state = .missing
                statusMessage = "Token removed."
            } catch is CancellationError {
                return
            } catch {
                guard Task.isCancelled == false else { return }
                state = .failed(error.localizedDescription)
                statusMessage = "Could not remove the token: \(error.localizedDescription)"
            }
        }
        if started == false {
            state = savedToken.isEmpty ? .missing : .loaded
            statusMessage = ""
        }
    }

    private func testConnection() {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, credentialTasks.isRunning == false else { return }
        state = .testing
        statusMessage = "Testing connection…"

        let started = credentialTasks.start {
            let client = DiscogsClient(tokenProvider: { trimmed })
            do {
                _ = try await client.search(
                    DiscogsArtworkSearchQuery(albumTitle: "Test", albumArtist: "Test"),
                    page: 1
                )
                try Task.checkCancellation()
                state = savedToken.isEmpty ? .missing : .loaded
                statusMessage = "Connection successful."
            } catch is CancellationError {
                return
            } catch {
                guard Task.isCancelled == false else { return }
                state = .failed(error.localizedDescription)
                statusMessage = "Connection failed: \(error.localizedDescription)"
            }
        }
        if started == false {
            state = savedToken.isEmpty ? .missing : .loaded
            statusMessage = ""
        }
    }
}
