import Foundation
import XCTest

@testable import SongbirdLib

/// Each test owns its clock. No shared mutable handler or clock override.
final class TestDiscogsClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [DiscogsFetchStamp?]
    init(_ values: [DiscogsFetchStamp?] = [TestDiscogsClock.stamp()]) { self.values = values }
    static func stamp(_ offset: TimeInterval = 0, boot: String = "fixture-boot")
        -> DiscogsFetchStamp
    {
        DiscogsFetchStamp(
            wall: Date(timeIntervalSince1970: 1_000 + offset),
            continuousSeconds: 100 + offset, bootID: boot)
    }
    func sample() -> DiscogsFetchStamp? {
        lock.lock()
        defer { lock.unlock() }
        if values.count > 1 { return values.removeFirst() }
        return values.first ?? nil
    }
    func set(_ value: DiscogsFetchStamp?) {
        lock.lock()
        defer { lock.unlock() }
        values = [value]
    }
}

/// Request recordings live only in this fixture's disposable directory.
/// The protocol has immutable routing rules and no global mutable callbacks.
final class DiscogsHTTPFixture {
    let directory: URL
    let session: URLSession
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "discogs-http-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscogsRecordedFixtureProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Songbird-Fixture": directory.path]
        session = URLSession(configuration: configuration)
    }
    deinit {
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: directory)
    }
    func requests() throws -> [[String: String]] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode([String: String].self, from: Data(contentsOf: $0)) }
    }
}

private final class DiscogsRecordedFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let directory = request.value(forHTTPHeaderField: "X-Songbird-Fixture") else {
            XCTFail("Unscoped request rejected")
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let url = request.url!
        let query =
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "q" }?.value ?? ""
        let record = [
            "path": url.path, "query": query,
            "cacheControl": request.value(forHTTPHeaderField: "Cache-Control") ?? "",
            "cachePolicy": String(request.cachePolicy.rawValue),
        ]
        do {
            try JSONEncoder().encode(record).write(
                to: URL(fileURLWithPath: directory)
                    .appendingPathComponent(UUID().uuidString + ".json"))
        } catch { XCTFail("Could not record synthetic request") }
        if url.path.contains("transport-failure") {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        var status = 200
        if query.contains("status-") { status = Int(query.split(separator: "-").last!) ?? 500 }
        if url.path.contains("retry") { status = 503 }
        if url.path.contains("rate") { status = 429 }
        let data: Data
        if url.path == "/database/search" {
            let results: [[String: Any]] =
                query.contains("empty") || status != 200
                ? []
                : (1...8).map {
                    [
                        "id": $0, "title": "Artist - Album",
                        "cover_image": "https://example.invalid/image", "format": ["CD"],
                    ]
                }
            data = try! JSONSerialization.data(withJSONObject: ["results": results])
        } else if url.path.hasPrefix("/releases/") {
            data = Data(#"{"id":42,"title":"Album","tracklist":[]}"#.utf8)
        } else {
            data = Data([1, 2, 3])
        }
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Retry-After": "7"])!
        let finish = {
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if url.path.contains("delayed") {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.01, execute: finish)
        } else {
            finish()
        }
    }
    override func stopLoading() {}
}
