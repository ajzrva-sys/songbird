import Foundation

public actor DiscogsResponseCache<Value: Codable & Sendable> {
    public struct Hit: Codable, Sendable {
        public let value: Value
        public let fetches: [DiscogsFetchStamp]
    }
    private struct Envelope: Codable {
        let version: Int
        let entries: [String: Hit]
    }
    private let fileURL: URL
    private let maximumAge: TimeInterval
    private let clock: @Sendable () -> DiscogsFetchStamp?
    private var entries: [String: Hit]?

    init(
        fileURL: URL,
        maximumAge: TimeInterval = DiscogsFreshness.maximumAge,
        clock: @escaping @Sendable () -> DiscogsFetchStamp? = { DiscogsClock.sample() }
    ) {
        self.fileURL = fileURL
        self.maximumAge = maximumAge
        self.clock = clock
    }

    func value(for key: String) -> Hit? {
        loadIfNeeded()

        prune(at: clock())
        return entries?[key]
    }

    @discardableResult
    func store(_ value: Value, fetches: [DiscogsFetchStamp], for key: String) -> Bool {
        loadIfNeeded()

        let now = clock()
        prune(at: now)
        let hit = Hit(value: value, fetches: fetches)
        guard fresh(hit, at: now) else { return false }

        entries?[key] = hit
        persist()
        return true
    }

    private func fresh(_ hit: Hit, at now: DiscogsFetchStamp?) -> Bool {
        !hit.fetches.isEmpty
            && hit.fetches.allSatisfy {
                DiscogsFreshness.isFresh($0, at: now, maximumAge: maximumAge)
            }
    }

    private func prune(at now: DiscogsFetchStamp?) {
        guard let old = entries else { return }
        let valid = old.filter { fresh($0.value, at: now) }
        if valid.count != old.count {
            entries = valid
            persist()
        }
    }

    private func loadIfNeeded() {
        guard entries == nil else { return }
        guard let data = try? Data(contentsOf: fileURL),
            let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
            envelope.version == 2
        else {
            entries = [:]
            // This file is an explicitly owned Discogs response cache, not a library.
            persist()
            return
        }
        entries = envelope.entries
    }

    private func persist() {
        guard let entries,
            let data = try? JSONEncoder().encode(Envelope(version: 2, entries: entries))
        else {
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Disk-cache failure must not turn stale content into a usable result.
            // Keep this cache best-effort; do not log URLs/tokens or touch the library.
        }
    }
}
