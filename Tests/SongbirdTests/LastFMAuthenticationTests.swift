import Foundation
import XCTest
@testable import SongbirdLib

private actor LastFMTestCredentials: SongbirdCredentialStoring {
    var values: [SongbirdCredential: String]
    var failWrite: SongbirdCredential?

    init(_ values: [SongbirdCredential: String] = [:], failWrite: SongbirdCredential? = nil) {
        self.values = values
        self.failWrite = failWrite
    }

    func value(for credential: SongbirdCredential, interaction: SongbirdCredentialInteractionPolicy) -> String? {
        values[credential]
    }

    func setValue(_ value: String, for credential: SongbirdCredential) throws {
        if failWrite == credential {
            failWrite = nil
            throw CocoaError(.fileWriteUnknown)
        }
        values[credential] = value
    }

    func removeValue(for credential: SongbirdCredential) { values[credential] = nil }
    func snapshot() -> [SongbirdCredential: String] { values }
}

private final class LastFMFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responses: [String: [[String: Any]]] = [:]
    private static var requests: [String: [[String: String]]] = [:]

    static func prepare(key: String, responses: [[String: Any]]) {
        lock.lock()
        defer { lock.unlock() }
        self.responses[key] = responses
        requests[key] = []
    }

    static func captured(key: String) -> [[String: String]] {
        lock.lock()
        defer { lock.unlock() }
        return requests[key] ?? []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        var components = URLComponents()
        components.percentEncodedQuery = String(decoding: body, as: UTF8.self)
        let params = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let key = params["api_key"] ?? ""
        Self.lock.lock()
        Self.requests[key, default: []].append(params)
        let response = Self.responses[key]?.isEmpty == false ? Self.responses[key]!.removeFirst() : nil
        Self.lock.unlock()
        guard let response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: response))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
final class LastFMAuthenticationTests: XCTestCase {
    private func makeClient(
        key: String, store: LastFMTestCredentials = LastFMTestCredentials(),
        configured: Bool = true, responses: [[String: Any]] = []
    ) -> (LastFMClient, UserDefaults) {
        LastFMFixtureProtocol.prepare(key: key, responses: responses)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LastFMFixtureProtocol.self]
        let suite = "Songbird.LastFMTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (LastFMClient(
            credentialStore: store, session: URLSession(configuration: config), defaults: defaults,
            applicationCredentials: configured ? .init(apiKey: key, apiSecret: "fixture-secret") : nil
        ), defaults)
    }

    func testBrowserApprovalStoresSessionWithoutRequestingPassword() async throws {
        let store = LastFMTestCredentials()
        let (client, defaults) = makeClient(key: "success", store: store, responses: [
            ["token": "fixture-token"], ["session": ["name": "listener", "key": "fixture-session"]],
        ])
        let authorizationURL = await client.beginBrowserAuthentication()
        let url = try XCTUnwrap(authorizationURL)
        XCTAssertEqual(url.host, "www.last.fm")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertFalse(url.absoluteString.contains("fixture-secret"))
        XCTAssertEqual(client.authenticationState, .awaitingAuthorization)
        await client.completeBrowserAuthentication()
        XCTAssertEqual(client.authenticationState, .authenticated)
        XCTAssertEqual(defaults.string(forKey: LastFMClient.usernameKey), "listener")
        XCTAssertNil(defaults.string(forKey: LastFMClient.passwordKey))
        let saved = await store.snapshot()
        XCTAssertEqual(saved[.lastFMSessionKey], "fixture-session")
        XCTAssertEqual(saved[.lastFMAPIKey], "success")
        let requests = LastFMFixtureProtocol.captured(key: "success")
        XCTAssertEqual(requests.map { $0["method"]! }, ["auth.getToken", "auth.getSession"])
        XCTAssertEqual(requests[0]["api_sig"], "a44216e24c3e8c897d9c3587c746369c")
        XCTAssertEqual(requests[1]["api_sig"], "5531c38fc6bb4b79879aa07e89ff3a59")
        XCTAssertTrue(requests.allSatisfy { $0["password"] == nil && $0["api_sig"]?.count == 32 })
        let background = await client.credentialsForBackgroundPost()
        XCTAssertEqual(background?.sessionKey, "fixture-session")
    }

    func testUnapprovedTokenCanBeRetriedWithoutNewSignIn() async {
        let (client, _) = makeClient(key: "pending", responses: [
            ["token": "pending-token"], ["error": 14, "message": "Not authorized"],
            ["session": ["name": "listener", "key": "session"]],
        ])
        _ = await client.beginBrowserAuthentication()
        await client.completeBrowserAuthentication()
        XCTAssertEqual(client.authenticationState, .awaitingAuthorization)
        await client.completeBrowserAuthentication()
        XCTAssertEqual(client.authenticationState, .authenticated)
        XCTAssertEqual(LastFMFixtureProtocol.captured(key: "pending").count, 3)
    }

    func testExpiredTokenShowsServiceErrorAndCanRestart() async {
        let (client, _) = makeClient(key: "expired", responses: [
            ["token": "old-token"], ["error": 15, "message": "Token expired"], ["token": "new-token"],
        ])
        _ = await client.beginBrowserAuthentication()
        await client.completeBrowserAuthentication()
        XCTAssertEqual(client.authenticationState, .failed("Token expired"))
        let url = await client.beginBrowserAuthentication()
        XCTAssertTrue(url?.absoluteString.contains("new-token") == true)
    }

    func testExistingApplicationCredentialsAndSessionRemainUsable() async throws {
        let original: [SongbirdCredential: String] = [
            .lastFMAPIKey: "existing", .lastFMAPISecret: "old-secret", .lastFMSessionKey: "old-session",
        ]
        let store = LastFMTestCredentials(original)
        let (client, _) = makeClient(key: "existing", store: store, configured: false, responses: [["token": "token"]])
        let active = try await client.hasStoredSession()
        XCTAssertTrue(active)
        let url = await client.beginBrowserAuthentication()
        XCTAssertNotNil(url)
        client.cancelBrowserAuthentication()
        await client.completeBrowserAuthentication()
        let saved = await store.snapshot()
        XCTAssertEqual(saved, original)
        XCTAssertEqual(LastFMFixtureProtocol.captured(key: "existing").count, 1)
    }

    func testUnconfiguredBuildDoesNotOpenBrowserOrChangeSavedSession() async {
        let store = LastFMTestCredentials([.lastFMSessionKey: "existing-session"])
        let (client, _) = makeClient(key: "unconfigured", store: store, configured: false)
        let url = await client.beginBrowserAuthentication()
        XCTAssertNil(url)
        XCTAssertEqual(client.authenticationState, .failed(LastFMClientError.applicationNotConfigured.localizedDescription))
        XCTAssertTrue(LastFMFixtureProtocol.captured(key: "unconfigured").isEmpty)
        let saved = await store.snapshot()
        XCTAssertEqual(saved, [.lastFMSessionKey: "existing-session"])
    }

    func testMalformedResponseDoesNotReplaceCredentials() async {
        let original: [SongbirdCredential: String] = [.lastFMAPIKey: "malformed", .lastFMAPISecret: "secret", .lastFMSessionKey: "old"]
        let store = LastFMTestCredentials(original)
        let (client, _) = makeClient(key: "malformed", store: store, responses: [["token": "token"], ["session": ["name": "listener"]]])
        _ = await client.beginBrowserAuthentication()
        await client.completeBrowserAuthentication()
        XCTAssertEqual(client.authenticationState, .failed(LastFMClientError.invalidResponse.localizedDescription))
        let saved = await store.snapshot()
        XCTAssertEqual(saved, original)
    }

    func testCredentialWriteFailureRestoresPreviousValues() async {
        let original: [SongbirdCredential: String] = [.lastFMAPIKey: "partial-key", .lastFMSessionKey: "old-session"]
        let store = LastFMTestCredentials(original, failWrite: .lastFMSessionKey)
        let (client, defaults) = makeClient(key: "write-failure", store: store, responses: [
            ["token": "token"], ["session": ["name": "listener", "key": "new-session"]],
        ])
        _ = await client.beginBrowserAuthentication()
        await client.completeBrowserAuthentication()
        guard case .failed = client.authenticationState else { return XCTFail("Expected write failure") }
        let saved = await store.snapshot()
        XCTAssertEqual(saved, original)
        XCTAssertNil(defaults.string(forKey: LastFMClient.usernameKey))
    }

    func testSignOutRemovesOnlySessionAndDisablesScrobbling() async throws {
        let store = LastFMTestCredentials([.lastFMAPIKey: "signout", .lastFMAPISecret: "secret", .lastFMSessionKey: "session"])
        let (client, defaults) = makeClient(key: "signout", store: store)
        defaults.set(true, forKey: LastFMClient.enabledKey)
        try await client.signOut()
        let saved = await store.snapshot()
        XCTAssertEqual(saved, [.lastFMAPIKey: "signout", .lastFMAPISecret: "secret"])
        XCTAssertFalse(client.isEnabled)
        XCTAssertEqual(client.authenticationState, .idle)
    }

    func testCancelledRequestPreservesSavedCredentials() async {
        let original: [SongbirdCredential: String] = [.lastFMSessionKey: "old-session"]
        let store = LastFMTestCredentials(original)
        let (client, _) = makeClient(key: "cancelled", store: store, responses: [["token": "token"]])
        let task = Task { await client.beginBrowserAuthentication() }
        task.cancel()
        let url = await task.value
        XCTAssertNil(url)
        XCTAssertEqual(client.authenticationState, .idle)
        let saved = await store.snapshot()
        XCTAssertEqual(saved, original)
    }

    func testBrowserLaunchFailureDiscardsPendingToken() async {
        let (client, _) = makeClient(key: "browser-failure", responses: [["token": "token"]])
        _ = await client.beginBrowserAuthentication()
        client.browserCouldNotOpen()
        await client.completeBrowserAuthentication()
        guard case .failed = client.authenticationState else { return XCTFail("Expected browser failure") }
        XCTAssertEqual(LastFMFixtureProtocol.captured(key: "browser-failure").count, 1)
    }

    func testBundledCredentialsRequireACompletePair() {
        XCTAssertNil(LastFMApplicationCredentials.from(info: [:]))
        XCTAssertNil(LastFMApplicationCredentials.from(info: ["SongbirdLastFMAPIKey": "key"]))
        XCTAssertEqual(LastFMApplicationCredentials.from(info: ["SongbirdLastFMAPIKey": " key ", "SongbirdLastFMAPISecret": "secret"]),
                       LastFMApplicationCredentials(apiKey: "key", apiSecret: "secret"))
    }
}
