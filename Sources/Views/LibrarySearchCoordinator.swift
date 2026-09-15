import Combine
import Foundation

/// Shared query and presentation state for the currently visible library root.
/// Navigation resets it so a hidden filter never follows the user elsewhere.
@MainActor
public final class LibrarySearchCoordinator: ObservableObject {
    @Published public var query = ""
    @Published public private(set) var isPresented = false
    @Published public private(set) var focusRequestID = 0

    public init() {}

    public func requestFocus() {
        isPresented = true
        focusRequestID &+= 1
    }

    public func clear() {
        query = ""
    }

    public func dismiss() {
        query = ""
        isPresented = false
    }

    public func collapseIfEmpty() {
        guard query.isEmpty else { return }
        isPresented = false
    }

    public func resetForNavigation() {
        guard query.isEmpty == false || isPresented else { return }
        query = ""
        isPresented = false
    }
}
