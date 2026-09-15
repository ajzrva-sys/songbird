import Combine
import CryptoKit
import Foundation

public enum LastFMAuthenticationState: Equatable, Sendable {
    case idle
    case authenticating
    case authenticated
    case failed(String)
}

public enum LastFMClientError: Error, LocalizedError {
    case incompleteCredentials
    case invalidResponse
    case service(String)

    public var errorDescription: String? {
        switch self {
        case .incompleteCredentials:
            return "Enter a username, password, API key, and shared secret."
        case .invalidResponse:
            return "Last.fm returned an invalid response."
        case .service(let message):
            return message
        }
    }
}

struct LastFMPostCredentials: Equatable, Sendable {
    let apiKey: String
    let apiSecret: String
    let sessionKey: String
}

/// Minimal Last.fm scrobbling client (mobile session + track.scrobble / updateNowPlaying).
@MainActor
public final class LastFMClient: ObservableObject {
    public static let shared = LastFMClient()

    public static let enabledKey = "lastfm.enabled"
    public static let usernameKey = "lastfm.username"
    public static let apiKeyKey = "lastfm.apiKey"
    public static let apiSecretKey = "lastfm.apiSecret"
    public static let sessionKeyKey = "lastfm.sessionKey"
    public static let passwordKey = "lastfm.password" // legacy key; never written

    @Published public private(set) var authenticationState: LastFMAuthenticationState = .idle

    private let credentialStore: any SongbirdCredentialStoring

    public init(credentialStore: any SongbirdCredentialStoring = SongbirdCredentialStore.shared) {
        self.credentialStore = credentialStore
    }

    public var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    public func storedCredential(_ credential: SongbirdCredential) async throws -> String {
        try await credentialStore.value(for: credential) ?? ""
    }

    public func authenticate(
        username: String,
        password: String,
        apiKey: String,
        apiSecret: String
    ) async {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard user.isEmpty == false,
              password.isEmpty == false,
              key.isEmpty == false,
              secret.isEmpty == false else {
            authenticationState = .failed(LastFMClientError.incompleteCredentials.localizedDescription)
            return
        }

        authenticationState = .authenticating
        do {
            var params: [String: String] = [
                "method": "auth.getMobileSession",
                "username": user,
                "password": password,
                "api_key": key,
            ]
            params["api_sig"] = sign(params, secret: secret)
            params["format"] = "json"

            let data = try await send(params)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LastFMClientError.invalidResponse
            }
            if let message = json["message"] as? String {
                throw LastFMClientError.service(message)
            }
            guard let session = json["session"] as? [String: Any],
                  let sessionKey = session["key"] as? String,
                  sessionKey.isEmpty == false else {
                throw LastFMClientError.invalidResponse
            }

            try await credentialStore.setValue(key, for: .lastFMAPIKey)
            try await credentialStore.setValue(secret, for: .lastFMAPISecret)
            try await credentialStore.setValue(sessionKey, for: .lastFMSessionKey)
            UserDefaults.standard.set(user, forKey: Self.usernameKey)
            UserDefaults.standard.removeObject(forKey: Self.passwordKey)
            authenticationState = .authenticated
        } catch is CancellationError {
            authenticationState = .idle
        } catch {
            authenticationState = .failed(error.localizedDescription)
        }
    }

    public func updateNowPlaying(artist: String, track: String, album: String?) {
        guard isEnabled else { return }
        Task { [weak self] in
            await self?.post(
                method: "track.updateNowPlaying",
                artist: artist,
                track: track,
                album: album,
                timestamp: nil
            )
        }
    }

    public func scrobble(artist: String, track: String, album: String?, startedAt: Date) {
        guard isEnabled else { return }
        Task { [weak self] in
            await self?.post(
                method: "track.scrobble",
                artist: artist,
                track: track,
                album: album,
                timestamp: Int(startedAt.timeIntervalSince1970)
            )
        }
    }

    func credentialsForBackgroundPost() async -> LastFMPostCredentials? {
        do {
            let interaction = SongbirdCredentialInteractionPolicy.failIfAuthenticationRequired
            let apiKey = try await credentialStore.value(
                for: .lastFMAPIKey,
                interaction: interaction
            ) ?? ""
            let apiSecret = try await credentialStore.value(
                for: .lastFMAPISecret,
                interaction: interaction
            ) ?? ""
            let sessionKey = try await credentialStore.value(
                for: .lastFMSessionKey,
                interaction: interaction
            ) ?? ""
            guard apiKey.isEmpty == false,
                  apiSecret.isEmpty == false,
                  sessionKey.isEmpty == false else { return nil }
            return LastFMPostCredentials(
                apiKey: apiKey,
                apiSecret: apiSecret,
                sessionKey: sessionKey
            )
        } catch {
            return nil
        }
    }

    private func post(
        method: String,
        artist: String,
        track: String,
        album: String?,
        timestamp: Int?
    ) async {
        do {
            guard let credentials = await credentialsForBackgroundPost() else { return }

            var params: [String: String] = [
                "method": method,
                "artist": artist,
                "track": track,
                "api_key": credentials.apiKey,
                "sk": credentials.sessionKey,
            ]
            if let album, album.isEmpty == false { params["album"] = album }
            if let timestamp { params["timestamp"] = "\(timestamp)" }
            params["api_sig"] = sign(params, secret: credentials.apiSecret)
            params["format"] = "json"
            _ = try await send(params)
        } catch {
            // Scrobbling is best-effort and must never interrupt playback.
        }
    }

    private func send(_ params: [String: String]) async throws -> Data {
        guard let url = URL(string: "https://ws.audioscrobbler.com/2.0/") else {
            throw LastFMClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = formEncode(params).data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        if !(200...299).contains(response.statusCode) {
            throw LastFMClientError.service("Last.fm request failed (HTTP \(response.statusCode)).")
        }
        return data
    }

    private func sign(_ params: [String: String], secret: String) -> String {
        let sorted = params.keys.sorted().map { "\($0)\(params[$0] ?? "")" }.joined()
        let digest = Insecure.MD5.hash(data: Data((sorted + secret).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return params.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }
}
