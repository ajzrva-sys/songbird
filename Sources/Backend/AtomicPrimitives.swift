import AudioAtomics
import Foundation

final class AtomicUInt64: @unchecked Sendable {
    private let storage: OpaquePointer
    init(_ value: UInt64 = 0) { storage = SBAtomicU64Create(value)! }
    deinit { SBAtomicU64Destroy(storage) }
    @inline(__always) func loadAcquire() -> UInt64 { SBAtomicU64LoadAcquire(storage) }
    @inline(__always) func loadRelaxed() -> UInt64 { SBAtomicU64LoadRelaxed(storage) }
    @inline(__always) func storeRelease(_ value: UInt64) { SBAtomicU64StoreRelease(storage, value) }
    @inline(__always) func storeRelaxed(_ value: UInt64) { SBAtomicU64StoreRelaxed(storage, value) }
    @discardableResult
    @inline(__always) func fetchAddRelaxed(_ value: UInt64) -> UInt64 {
        SBAtomicU64FetchAddRelaxed(storage, value)
    }
    @inline(__always) func maxRelaxed(_ value: UInt64) {
        SBAtomicU64MaxRelaxed(storage, value)
    }
}

final class AtomicUInt32: @unchecked Sendable {
    private let storage: OpaquePointer
    init(_ value: UInt32 = 0) { storage = SBAtomicU32Create(value)! }
    deinit { SBAtomicU32Destroy(storage) }
    @inline(__always) func loadAcquire() -> UInt32 { SBAtomicU32LoadAcquire(storage) }
    @inline(__always) func storeRelease(_ value: UInt32) { SBAtomicU32StoreRelease(storage, value) }
}

final class AtomicFloat: @unchecked Sendable {
    private let storage: OpaquePointer
    init(_ value: Float = 0) { storage = SBAtomicFloatCreate(value)! }
    deinit { SBAtomicFloatDestroy(storage) }
    @inline(__always) func loadRelaxed() -> Float { SBAtomicFloatLoadRelaxed(storage) }
    @inline(__always) func storeRelaxed(_ value: Float) { SBAtomicFloatStoreRelaxed(storage, value) }
}

final class AtomicDouble: @unchecked Sendable {
    private let storage: OpaquePointer
    init(_ value: Double = 0) { storage = SBAtomicDoubleCreate(value)! }
    deinit { SBAtomicDoubleDestroy(storage) }
    @inline(__always) func loadAcquire() -> Double { SBAtomicDoubleLoadAcquire(storage) }
    @inline(__always) func loadRelaxed() -> Double { SBAtomicDoubleLoadRelaxed(storage) }
    @inline(__always) func storeRelease(_ value: Double) {
        SBAtomicDoubleStoreRelease(storage, value)
    }
    @inline(__always) func storeRelaxed(_ value: Double) {
        SBAtomicDoubleStoreRelaxed(storage, value)
    }
}

final class AtomicBool: @unchecked Sendable {
    private let storage: OpaquePointer
    init(_ value: Bool = false) { storage = SBAtomicBoolCreate(value ? 1 : 0)! }
    deinit { SBAtomicBoolDestroy(storage) }
    @inline(__always) func loadAcquire() -> Bool { SBAtomicBoolLoadAcquire(storage) != 0 }
    @inline(__always) func storeRelease(_ value: Bool) {
        SBAtomicBoolStoreRelease(storage, value ? 1 : 0)
    }
}

final class AtomicPointer: @unchecked Sendable {
    private let storage: OpaquePointer
    init(_ value: UInt = 0) { storage = SBAtomicPointerCreate(value)! }
    deinit { SBAtomicPointerDestroy(storage) }
    @inline(__always) func loadAcquire() -> UInt { SBAtomicPointerLoadAcquire(storage) }
    @inline(__always) func storeRelease(_ value: UInt) {
        SBAtomicPointerStoreRelease(storage, value)
    }
}

struct AtomicMessage: Equatable {
    var type: UInt32
    var pointer: UInt
    var value: UInt64
}

final class AtomicMessageQueue: @unchecked Sendable {
    private let storage: OpaquePointer
    init(capacity: Int) { storage = SBMessageQueueCreate(capacity)! }
    deinit { SBMessageQueueDestroy(storage) }

    @inline(__always)
    func push(_ message: AtomicMessage) -> Bool {
        SBMessageQueuePush(
            storage,
            SBAtomicMessage(type: message.type, pointer: message.pointer, value: message.value)
        ) != 0
    }

    @inline(__always)
    func pop() -> AtomicMessage? {
        var message = SBAtomicMessage()
        guard SBMessageQueuePop(storage, &message) != 0 else { return nil }
        return AtomicMessage(type: message.type, pointer: message.pointer, value: message.value)
    }

    var count: Int { SBMessageQueueCount(storage) }
}
