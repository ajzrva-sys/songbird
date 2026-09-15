import Combine
import CryptoKit
import Foundation

public enum LastFMAuthenticationState: Equatable, Sendable {
    case idle
    case authenticating
    case awaitingAuthorization
    case authenticated
    case failed(String)
}

public enum LastFMClientError: Error, LocalizedError {
    case incompleteCredentials
    case applicationNotConfigured
    case invalidResponse
    case service(String)
    case api(Int, String)

    public var errorDescription: String? {
        switch self {
        case .incompleteCredentials:
            return "Enter a username, password, API key, and shared secret."
        case .applicationNotConfigured:
            return "This build of Songbird isn’t configured for Last.fm sign-in yet."
        case .invalidResponse:
            return "Last.fm returned an invalid response."
        case .service(let message):
            return message
        case .api(_, let message):
            return message
        }
    }
}

public struct LastFMApplicationCredentials: Equatable, Sendable {
    let apiKey: String
    let apiSecret: String

    public init(apiKey: String, apiSecret: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiSecret = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isComplete: Bool { !apiKey.isEmpty && !apiSecret.isEmpty }

    public static func bundled() -> Self? {
        from(info: Bundle.main.infoDictionary ?? [:])
    }

    static func from(info: [String: Any]) -> Self? {
        let credentials = Self(
            apiKey: info["SongbirdLastFMAPIKey"] as? String ?? "",
            apiSecret: info["SongbirdLastFMAPISecret"] as? String ?? ""
        )
        return credentials.isComplete ? credentials : nil
    }
}

struct LastFMPostCredentials: Equatable, Sendable {
    let apiKey: String
    let apiSecret: String
    let sessionKey: String
}

/// Last.fm browser authentication and best-effort scrobbling.
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
    private let session: URLSession
    private let defaults: UserDefaults
    private let applicationCredentials: LastFMApplicationCredentials?
    private var pendingAuthorization: (token: String, credentials: LastFMApplicationCredentials)?

    public init(
        credentialStore: any SongbirdCredentialStoring = SongbirdCredentialStore.shared,
        session: URLSession = URLSession(configuration: .ephemeral),
        defaults: UserDefaults = .standard,
        applicationCredentials: LastFMApplicationCredentials? = .bundled()
    ) {
        self.credentialStore = credentialStore
        self.session = session
        self.defaults = defaults
        self.applicationCredentials = applicationCredentials
    }

    public var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    public func storedCredential(_ credential: SongbirdCredential) async throws -> String {
        try await credentialStore.value(for: credential) ?? ""
    }

    public func hasStoredSession() async throws -> Bool {
        let key = try await credentialStore.value(for: .lastFMAPIKey) ?? ""
        let secret = try await credentialStore.value(for: .lastFMAPISecret) ?? ""
        let session = try await credentialStore.value(for: .lastFMSessionKey) ?? ""
        return !key.isEmpty && !secret.isEmpty && !session.isEmpty
    }

    public func beginBrowserAuthentication() async -> URL? {
        guard authenticationState != .authenticating else { return nil }
        pendingAuthorization = nil
        authenticationState = .authenticating
        do {
            let stored = LastFMApplicationCredentials(
                apiKey: try await storedCredential(.lastFMAPIKey),
                apiSecret: try await storedCredential(.lastFMAPISecret)
            )
            guard let credentials = stored.isComplete ? stored : applicationCredentials,
                  credentials.isComplete else {
                throw LastFMClientError.applicationNotConfigured
            }
            let response = try await request("auth.getToken", credentials: credentials)
            try Task.checkCancellation()
            guard let token = response["token"] as? String, !token.isEmpty else {
                throw LastFMClientError.invalidResponse
            }
            var url = URLComponents(string: "https://www.last.fm/api/auth/")!
            url.queryItems = [
                URLQueryItem(name: "api_key", value: credentials.apiKey),
                URLQueryItem(name: "token", value: token),
            ]
            pendingAuthorization = (token, credentials)
            authenticationState = .awaitingAuthorization
            return url.url
        } catch is CancellationError {
            authenticationState = .idle
        } catch {
            authenticationState = Task.isCancelled ? .idle : .failed(error.localizedDescription)
        }
        return nil
    }

    public func completeBrowserAuthentication() async {
        guard authenticationState == .awaitingAuthorization,
              let pending = pendingAuthorization else { return }
        authenticationState = .authenticating
        do {
            let response = try await request(
                "auth.getSession", parameters: ["token": pending.token],
                credentials: pending.credentials
            )
            try Task.checkCancellation()
            guard let session = response["session"] as? [String: Any],
                  let key = session["key"] as? String, !key.isEmpty,
                  let username = session["name"] as? String, !username.isEmpty else {
                throw LastFMClientError.invalidResponse
            }
            try await saveSession(key, username: username, credentials: pending.credentials)
            pendingAuthorization = nil
            authenticationState = .authenticated
        } catch LastFMClientError.api(14, _) {
            // Returning from the browser before granting access is retryable.
            authenticationState = .awaitingAuthorization
        } catch is CancellationError {
            pendingAuthorization = nil
            authenticationState = .idle
        } catch {
            pendingAuthorization = nil
            authenticationState = Task.isCancelled ? .idle : .failed(error.localizedDescription)
        }
    }

    public func cancelBrowserAuthentication() {
        pendingAuthorization = nil
        authenticationState = .idle
    }

    public func browserCouldNotOpen() {
        pendingAuthorization = nil
        authenticationState = .failed("Could not open Last.fm in your browser. Try signing in again.")
    }

    public func signOut() async throws {
        try await credentialStore.removeValue(for: .lastFMSessionKey)
        defaults.set(false, forKey: Self.enabledKey)
        cancelBrowserAuthentication()
    }

    private func request(
        _ method: String, parameters: [String: String] = [:],
        credentials: LastFMApplicationCredentials
    ) async throws -> [String: Any] {
        var params = parameters
        params["method"] = method
        params["api_key"] = credentials.apiKey
        params["api_sig"] = sign(params, secret: credentials.apiSecret)
        params["format"] = "json"
        let data = try await send(params)
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LastFMClientError.invalidResponse
        }
        return response
    }

    private func saveSession(
        _ sessionKey: String, username: String, credentials: LastFMApplicationCredentials
    ) async throws {
        let entries: [(SongbirdCredential, String)] = [
            (.lastFMAPIKey, credentials.apiKey),
            (.lastFMAPISecret, credentials.apiSecret),
            (.lastFMSessionKey, sessionKey),
        ]
        var previous: [(SongbirdCredential, String?)] = []
        for (credential, _) in entries {
            previous.append((credential, try await credentialStore.value(for: credential)))
        }
        var written = 0
        do {
            for (credential, value) in entries {
                try Task.checkCancellation()
                try await credentialStore.setValue(value, for: credential)
                written += 1
            }
            try Task.checkCancellation()
        } catch {
            for (credential, value) in previous.prefix(written).reversed() {
                if let value {
                    try? await credentialStore.setValue(value, for: credential)
                } else {
                    try? await credentialStore.removeValue(for: credential)
                }
            }
            throw error
        }
        defaults.set(username, forKey: Self.usernameKey)
        defaults.removeObject(forKey: Self.passwordKey)
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
            defaults.set(user, forKey: Self.usernameKey)
            defaults.removeObject(forKey: Self.passwordKey)
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
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(params).data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["error"] as? Int {
            throw LastFMClientError.api(code, json["message"] as? String ?? "Last.fm request failed.")
        }
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
