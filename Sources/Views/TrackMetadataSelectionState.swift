import Foundation

/// An untouched mixed selection differs from explicitly choosing false or zero.
struct TrackMetadataSelectionState<Value: Equatable>: Equatable {
    let baseline: Value?
    private(set) var edit: Value?

    init(values: [Value]) {
        if let first = values.first, values.allSatisfy({ $0 == first }) {
            baseline = first
        } else {
            baseline = nil
        }
        edit = nil
    }

    var value: Value? { edit ?? baseline }
    var isMixed: Bool { baseline == nil && edit == nil }

    mutating func choose(_ value: Value) { edit = value }
    mutating func leaveUnchanged() { edit = nil }
}

public enum TrackMetadataWritePolicy: Equatable, Sendable {
    case catalogOnly
    case catalogAndFileTags

    public var title: String {
        switch self {
        case .catalogOnly: "Songbird catalog only"
        case .catalogAndFileTags: "Catalog + supported audio tags"
        }
    }
}

extension TrackMetadataField {
    var supportsAudioTagWriting: Bool {
        self != .rating && self != .favorite
    }
}
