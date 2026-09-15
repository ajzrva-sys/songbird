import Foundation
@testable import SongbirdLib

actor ControlledCDMetadata: AudioCDMetadataProviding {
    private var continuations: [Int: CheckedContinuation<[AudioCDMetadataCandidate], Error>] = [:]
    private(set) var count = 0
    func candidates(for query: AudioCDMetadataQuery) async throws -> [AudioCDMetadataCandidate] {
        let id = count
        count += 1
        return try await withCheckedThrowingContinuation { continuations[id] = $0 }
    }
    func complete(_ index: Int, with values: [AudioCDMetadataCandidate]) {
        continuations.removeValue(forKey: index)?.resume(returning: values)
    }
}
