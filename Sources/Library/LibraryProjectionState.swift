public enum LibraryProjectionState<Value> {
    case loading(previous: Value?)
    case loaded(Value)
    case failed(message: String, previous: Value?)

    public var value: Value? {
        switch self {
        case .loading(let previous), .failed(_, let previous): previous
        case .loaded(let value): value
        }
    }
}
