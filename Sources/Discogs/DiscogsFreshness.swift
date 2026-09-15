import Darwin
import Foundation

public struct DiscogsContentEvidence: Codable, Hashable, Sendable {
    public let releaseID: Int
    public let fetches: [DiscogsFetchStamp]
    public init(releaseID: Int, fetches: [DiscogsFetchStamp]) {
        self.releaseID = releaseID
        self.fetches = fetches
    }
    public var sourcePageURL: URL? {
        guard releaseID > 0 else { return nil }
        return URL(string: "https://www.discogs.com/release/\(releaseID)")
    }
    public func isFresh(at now: DiscogsFetchStamp?) -> Bool {
        releaseID > 0 && !fetches.isEmpty
            && fetches.allSatisfy { DiscogsFreshness.isFresh($0, at: now) }
    }
}

public enum DiscogsClock {
    public static func sample() -> DiscogsFetchStamp? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0,
            size > 1
        else { return nil }

        var bytes = [CChar](repeating: 0, count: size)
        let status = bytes.withUnsafeMutableBytes {
            sysctlbyname("kern.bootsessionuuid", $0.baseAddress, &size, nil, 0)
        }
        guard status == 0 else { return nil }

        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS,
            timebase.denom != 0
        else { return nil }

        let seconds =
            Double(mach_continuous_time())
            * Double(timebase.numer) / Double(timebase.denom)
            / 1_000_000_000
        let bootID = bytes.withUnsafeBufferPointer {
            String(cString: $0.baseAddress!)
        }
        guard !bootID.isEmpty, seconds.isFinite else { return nil }

        return DiscogsFetchStamp(
            wall: Date(),
            continuousSeconds: seconds,
            bootID: bootID
        )
    }
}

public struct DiscogsFetchStamp: Codable, Hashable, Sendable {
    public let wall: Date
    public let continuousSeconds: TimeInterval
    public let bootID: String
    public init(wall: Date, continuousSeconds: TimeInterval, bootID: String) {
        self.wall = wall
        self.continuousSeconds = continuousSeconds
        self.bootID = bootID
    }
}

public enum DiscogsFreshness {
    public static let maximumAge: TimeInterval = 5 * 60 * 60
    public static func isFresh(
        _ stamp: DiscogsFetchStamp?, at now: DiscogsFetchStamp?,
        maximumAge: TimeInterval = DiscogsFreshness.maximumAge
    ) -> Bool {
        guard let stamp, let now, !stamp.bootID.isEmpty, stamp.bootID == now.bootID else {
            return false
        }
        guard maximumAge.isFinite, maximumAge > 0 else { return false }
        let maximumAge = min(maximumAge, Self.maximumAge)
        let wallAge = now.wall.timeIntervalSince(stamp.wall)
        let continuousAge = now.continuousSeconds - stamp.continuousSeconds
        return wallAge.isFinite && continuousAge.isFinite
            && wallAge >= 0 && wallAge < maximumAge
            && continuousAge >= 0 && continuousAge < maximumAge
    }
}
