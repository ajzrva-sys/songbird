import Foundation
@testable import SongbirdLib

actor ControlledDiscDiscovery: OpticalDiscAccessing {
    private var pending: [Int: CheckedContinuation<[OpticalDiscDescriptor], Never>] = [:]
    private(set) var count = 0
    func discover() async throws -> [OpticalDiscDescriptor] {
        let index = count
        count += 1
        return await withCheckedContinuation { pending[index] = $0 }
    }
    func complete(_ index: Int, with values: [OpticalDiscDescriptor]) {
        pending.removeValue(forKey: index)?.resume(returning: values)
    }
}
