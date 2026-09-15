import Foundation

public enum LibraryActionError: Error, LocalizedError, Equatable {
    case unavailable(String)
    case persistence(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message), .persistence(let message):
            message
        }
    }
}

public typealias LibraryActionResult = Result<Void, LibraryActionError>
