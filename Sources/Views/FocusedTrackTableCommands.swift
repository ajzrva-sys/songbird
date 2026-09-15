import SwiftUI

public struct FocusedTrackTableCommands {
    public let selectAll: () -> Void
    public let focusSearch: () -> Void

    public init(
        selectAll: @escaping () -> Void,
        focusSearch: @escaping () -> Void
    ) {
        self.selectAll = selectAll
        self.focusSearch = focusSearch
    }
}

private struct FocusedTrackTableCommandsKey: FocusedValueKey {
    typealias Value = FocusedTrackTableCommands
}

public extension FocusedValues {
    var trackTableCommands: FocusedTrackTableCommands? {
        get { self[FocusedTrackTableCommandsKey.self] }
        set { self[FocusedTrackTableCommandsKey.self] = newValue }
    }
}
