import Foundation
import Testing

/// Immutable URLProtocol routing, per-fixture disk barriers and request records; never contacts a host.
final class ThumbnailHTTPFixture {
    let directory: URL
    let session: URLSession
    init(data: Data, delayed: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("thumbnail-http-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("image.png"))
        if !delayed { try Data().write(to: directory.appendingPathComponent("ready")) }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.protocolClasses = [ThumbnailFixtureProtocol.self]
        config.httpAdditionalHeaders = ["X-Thumbnail-Fixture": directory.path]
        session = URLSession(configuration: config)
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
    func release() throws { try Data().write(to: directory.appendingPathComponent("ready")) }
}

private final class ThumbnailFixtureProtocol: URLProtocol {
    private let lock = NSLock()
    private var work: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let path = request.value(forHTTPHeaderField: "X-Thumbnail-Fixture"), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let directory = URL(fileURLWithPath: path)
        let record = ["cacheControl": request.value(forHTTPHeaderField: "Cache-Control") ?? "",
                      "cachePolicy": String(request.cachePolicy.rawValue), "path": url.path]
        do {
            try JSONEncoder().encode(record).write(to: directory.appendingPathComponent(UUID().uuidString + ".json"))
        } catch { client?.urlProtocol(self, didFailWithError: error); return }
        let task = Task {
            for _ in 0..<400 {
                guard !Task.isCancelled else { return }
                if FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path) {
                    do {
                        let data = try Data(contentsOf: directory.appendingPathComponent("image.png"))
                        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                            headerFields: ["Content-Type": "image/png", "Cache-Control": "max-age=999999"])!
                        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                        self.client?.urlProtocol(self, didLoad: data)
                        self.client?.urlProtocolDidFinishLoading(self)
                    } catch { self.client?.urlProtocol(self, didFailWithError: error) }
                    return
                }
                do { try await Task.sleep(for: .milliseconds(5)) } catch { return }
            }
            self.client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
        }
        lock.withLock { work = task }
    }
    override func stopLoading() { lock.withLock { work?.cancel() } }
}
