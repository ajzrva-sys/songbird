import SwiftUI

public struct FocusedLibrarySearchCommands {
    public let focusSearch: () -> Void

    public init(focusSearch: @escaping () -> Void) {
        self.focusSearch = focusSearch
    }
}

private struct FocusedLibrarySearchCommandsKey: FocusedValueKey {
    typealias Value = FocusedLibrarySearchCommands
}

public extension FocusedValues {
    var librarySearchCommands: FocusedLibrarySearchCommands? {
        get { self[FocusedLibrarySearchCommandsKey.self] }
        set { self[FocusedLibrarySearchCommandsKey.self] = newValue }
    }
}
