import Foundation

/// Keeps a retained count separate from whether that result is current.
struct LibraryHealthStatusPresentation: Equatable {
    let title: String
    let symbol: String
    let checkedAt: Date?
    let isCurrent: Bool
    let failureMessage: String?

    init(state: LibraryHealthCheckState) {
        checkedAt = state.lastGood?.checkedAt
        failureMessage = {
            if case .failed(let message, _) = state { return message }
            return nil
        }()
        switch state {
        case .notChecked:
            title = "Not checked"
            symbol = "clock"
            isCurrent = false
        case .checking:
            title = "Checking…"
            symbol = "arrow.triangle.2.circlepath"
            isCurrent = false
        case .ready:
            title = "Current"
            symbol = "checkmark.circle"
            isCurrent = true
        case .stale:
            title = "Results outdated"
            symbol = "clock.arrow.circlepath"
            isCurrent = false
        case .failed:
            title = "Check failed"
            symbol = "exclamationmark.triangle"
            isCurrent = false
        }
    }

    func findingText(count: Int) -> String {
        let countText = "\(count) finding\(count == 1 ? "" : "s")"
        return isCurrent ? countText : "Previous: \(countText)"
    }

    var emptyResultDescription: String {
        isCurrent
            ? "This check found no problems in the current library view."
            : "The last successful check found no problems. These results are not current."
    }
}
