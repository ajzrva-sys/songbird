import Foundation

/// Compatibility facade for existing Discogs call sites. All Security
/// framework work is serialized by SongbirdCredentialStore.
public enum DiscogsKeychain {
    public static func save(token: String) async throws {
        try await SongbirdCredentialStore.shared.setValue(token, for: .discogsToken)
    }

    public static func load() async throws -> String {
        guard let token = try await SongbirdCredentialStore.shared.value(for: .discogsToken),
              token.isEmpty == false else {
            throw KeychainError.notFound
        }
        return token
    }

    public static func delete() async throws {
        try await SongbirdCredentialStore.shared.removeValue(for: .discogsToken)
    }

    public static func tokenExists() async -> Bool {
        (try? await load()) != nil
    }

    public enum KeychainError: Error, LocalizedError {
        case notFound

        public var errorDescription: String? {
            "No token found in Keychain."
        }
    }
}
