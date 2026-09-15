import XCTest

@testable import SongbirdLib

final class DiscogsResponseCacheTests: XCTestCase {
    func testInvalidClockEvidenceAndLongTTLFailClosed() async throws {
        for now in [
            TestDiscogsClock.stamp(-1), TestDiscogsClock.stamp(1, boot: "reboot"),
            TestDiscogsClock.stamp(18_000), nil,
        ] {
            let url = file()
            defer { try? FileManager.default.removeItem(at: url) }
            let clock = TestDiscogsClock()
            let cache = DiscogsResponseCache<[Int]>(
                fileURL: url, maximumAge: 30 * 24 * 60 * 60,
                clock: { clock.sample() })
            await cache.store([], fetches: [TestDiscogsClock.stamp()], for: "key")
            clock.set(now)
            let hit = await cache.value(for: "key")
            XCTAssertNil(hit)
            let stored = await cache.store([], fetches: [TestDiscogsClock.stamp()], for: "key")
            XCTAssertFalse(stored)
        }
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = TestDiscogsClock()
        let cache = DiscogsResponseCache<[Int]>(fileURL: url, clock: { clock.sample() })
        let stored = await cache.store([], fetches: [], for: "key")
        XCTAssertFalse(stored)
    }

    func testExpiredStoreRejectedWithoutRenewingOrRetainingStaleEntries() async throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = TestDiscogsClock()
        let cache = DiscogsResponseCache<[Int]>(
            fileURL: url, maximumAge: 60, clock: { clock.sample() })
        await cache.store([42], fetches: [TestDiscogsClock.stamp()], for: "old")
        clock.set(TestDiscogsClock.stamp(60))
        let accepted = await cache.store([], fetches: [TestDiscogsClock.stamp()], for: "refresh")
        XCTAssertFalse(accepted)
        let envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual((envelope["entries"] as? [String: Any])?.count, 0)
    }

    func testAllEntriesArePrunedAtFreshnessBoundary() async throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = TestDiscogsClock()
        let cache = DiscogsResponseCache<[Int]>(
            fileURL: url, maximumAge: 60, clock: { clock.sample() })
        await cache.store([], fetches: [TestDiscogsClock.stamp()], for: "negative")
        await cache.store([42], fetches: [TestDiscogsClock.stamp()], for: "positive")
        clock.set(TestDiscogsClock.stamp(60))
        let result = await cache.value(for: "negative")
        XCTAssertNil(result)
        let envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual((envelope["entries"] as? [String: Any])?.count, 0)
    }

    func testLegacyEnvelopeIsRejectedAndReplaced() async throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = TestDiscogsClock()
        let cache = DiscogsResponseCache<[Int]>(fileURL: url, clock: { clock.sample() })
        await cache.store([], fetches: [TestDiscogsClock.stamp()], for: "key")
        var envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        envelope["version"] = 1
        try JSONSerialization.data(withJSONObject: envelope).write(to: url)
        let reloaded = DiscogsResponseCache<[Int]>(fileURL: url, clock: { clock.sample() })
        let result = await reloaded.value(for: "key")
        XCTAssertNil(result)
        let migrated = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(migrated["version"] as? Int, 2)
    }

    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "discogs-kernel-" + UUID().uuidString + ".json")
    }
    func testRoundTripPreservesOriginalAcquisitionInsteadOfStoreTime() async throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = TestDiscogsClock([TestDiscogsClock.stamp(40)])
        let cache = DiscogsResponseCache<[Int]>(fileURL: url, clock: { clock.sample() })
        let stored = await cache.store([42], fetches: [TestDiscogsClock.stamp()], for: "key")
        XCTAssertTrue(stored)
        let reloaded = DiscogsResponseCache<[Int]>(fileURL: url, clock: { clock.sample() })
        let hit = await reloaded.value(for: "key")
        XCTAssertEqual(hit?.value, [42])
        XCTAssertEqual(hit?.fetches, [TestDiscogsClock.stamp()])
        guard let data = try? Data(contentsOf: url) else {
            XCTFail("Cache file missing")
            return
        }
        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(envelope?["version"] as? Int, 2)
    }
}
