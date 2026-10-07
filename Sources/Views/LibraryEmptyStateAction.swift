import Foundation

/// Presentation intent; the owning view supplies its existing import, sheet,
/// navigation, or filter action instead of the table creating another workflow.
public struct LibraryEmptyStateAction {
    public enum Kind: Equatable {
        case importMusic, browseAllTracks, addTracks, editRules, back
        case clearSearch, clearFilters, showAllAlbums

        public var title: String {
            switch self {
            case .importMusic: "Import Music…"
            case .browseAllTracks: "Browse All Tracks"
            case .addTracks: "Add Tracks…"
            case .editRules: "Edit Rules…"
            case .back: "Back"
            case .clearSearch: "Clear Search"
            case .clearFilters: "Clear Filters"
            case .showAllAlbums: "Show All Albums"
            }
        }
    }

    public let kind: Kind
    private let operation: @MainActor () -> Void

    public init(_ kind: Kind, operation: @escaping @MainActor () -> Void) {
        self.kind = kind
        self.operation = operation
    }

    @MainActor
    public func perform() { operation() }
}

enum LibraryEmptyStatePolicy {
    static func sourceAction(
        for collection: TrackCollectionDescriptor,
        playlistIsSmart: Bool? = nil
    ) -> LibraryEmptyStateAction.Kind? {
        switch collection {
        case .allTracks: .importMusic
        case .topPlayed, .recentlyAdded: .browseAllTracks
        case .artist, .genre: .back
        case .playlist:
            playlistIsSmart.map { $0 ? .editRules : .addTracks }
        case .orderedTrackIDs: nil
        }
    }

    static func filteredActions(
        hasSearch: Bool,
        hasFilters: Bool = false,
        favoritesOnly: Bool = false
    ) -> [LibraryEmptyStateAction.Kind] {
        var result: [LibraryEmptyStateAction.Kind] = []
        if hasSearch { result.append(.clearSearch) }
        if hasFilters { result.append(.clearFilters) }
        if favoritesOnly { result.append(.showAllAlbums) }
        return result
    }
}
