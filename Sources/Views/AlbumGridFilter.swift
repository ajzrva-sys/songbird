public enum AlbumGridScope: Hashable, Sendable {
    case all
    case recentlyAdded(limit: Int = 100)
}

public enum AlbumGridFilter {
    public static func apply(
        to groups: [LibraryAlbumGroupSnapshot],
        searchText: String,
        favoritesOnly: Bool,
        sortOrder: AlbumSortOrder,
        scope: AlbumGridScope = .all
    ) -> [LibraryAlbumGroupSnapshot] {
        let scoped: [LibraryAlbumGroupSnapshot]
        switch scope {
        case .all:
            scoped = groups
        case .recentlyAdded(let limit):
            scoped = Array(groups.sorted { lhs, rhs in
                if lhs.dateAdded != rhs.dateAdded { return lhs.dateAdded > rhs.dateAdded }
                let title = lhs.title.localizedStandardCompare(rhs.title)
                if title != .orderedSame { return title == .orderedAscending }
                return lhs.id < rhs.id
            }.prefix(max(0, limit)))
        }
        let filtered = scoped.filter { group in
            let matchesFavorite = favoritesOnly == false || group.isFavorite
            let matchesSearch = searchText.isEmpty
                || group.title.localizedStandardContains(searchText)
                || group.artist.localizedStandardContains(searchText)
            return matchesFavorite && matchesSearch
        }
        if case .recentlyAdded = scope { return filtered }
        return filtered.sorted { lhs, rhs in
            switch sortOrder {
            case .title:
                compare(lhs.title, rhs.title, fallback: (lhs.artist, rhs.artist))
            case .artist:
                compare(lhs.artist, rhs.artist, fallback: (lhs.title, rhs.title))
            case .year:
                lhs.year == rhs.year
                    ? compare(lhs.title, rhs.title, fallback: (lhs.artist, rhs.artist))
                    : lhs.year > rhs.year
            case .recentlyAdded:
                lhs.dateAdded == rhs.dateAdded
                    ? compare(lhs.title, rhs.title, fallback: (lhs.artist, rhs.artist))
                    : lhs.dateAdded > rhs.dateAdded
            }
        }
    }

    private static func compare(
        _ lhs: String,
        _ rhs: String,
        fallback: (String, String)
    ) -> Bool {
        let result = lhs.localizedStandardCompare(rhs)
        return result == .orderedSame
            ? fallback.0.localizedStandardCompare(fallback.1) == .orderedAscending
            : result == .orderedAscending
    }
}

struct AlbumGridProjectionRequest: Hashable, Sendable {
    let sourceRevision: Int
    let searchText: String
    let favoritesOnly: Bool
    let sortOrder: AlbumSortOrder
    let scope: AlbumGridScope

    init(
        sourceRevision: Int,
        searchText: String,
        favoritesOnly: Bool,
        sortOrder: AlbumSortOrder,
        scope: AlbumGridScope = .all
    ) {
        self.sourceRevision = sourceRevision
        self.searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.favoritesOnly = favoritesOnly
        self.sortOrder = sortOrder
        self.scope = scope
    }
}

struct AlbumGridProjection: Equatable, Sendable {
    let request: AlbumGridProjectionRequest
    let groups: [LibraryAlbumGroupSnapshot]
    let orderedIDs: [String]
    let groupsByID: [String: LibraryAlbumGroupSnapshot]
    let displayDetails: [String: String]

    static let empty = AlbumGridProjection(
        request: AlbumGridProjectionRequest(
            sourceRevision: 0,
            searchText: "",
            favoritesOnly: false,
            sortOrder: .title,
            scope: .all
        ),
        groups: [],
        orderedIDs: [],
        groupsByID: [:],
        displayDetails: [:]
    )

    func contextAlbums(clickedID: String, selectedIDs: Set<String>) -> [LibraryAlbumGroupSnapshot] {
        guard selectedIDs.contains(clickedID) else {
            return groupsByID[clickedID].map { [$0] } ?? []
        }
        let selected = orderedIDs.compactMap { id in
            selectedIDs.contains(id) ? groupsByID[id] : nil
        }
        return selected.isEmpty
            ? (groupsByID[clickedID].map { [$0] } ?? [])
            : selected
    }
}

actor AlbumGridProjectionWorker {
    private var cachedProjection: AlbumGridProjection?
    private var completedProjectionCount = 0

    func project(
        groups: [LibraryAlbumGroupSnapshot],
        request: AlbumGridProjectionRequest
    ) throws -> AlbumGridProjection {
        if let cachedProjection, cachedProjection.request == request {
            return cachedProjection
        }
        try Task.checkCancellation()
        let displayed = AlbumGridFilter.apply(
            to: groups,
            searchText: request.searchText,
            favoritesOnly: request.favoritesOnly,
            sortOrder: request.sortOrder,
            scope: request.scope
        )
        try Task.checkCancellation()
        let projection = AlbumGridProjection(
            request: request,
            groups: displayed,
            orderedIDs: displayed.map(\.id),
            groupsByID: Dictionary(uniqueKeysWithValues: displayed.map { ($0.id, $0) }),
            displayDetails: LibraryAlbumDisplayDetail.details(for: groups)
        )
        cachedProjection = projection
        completedProjectionCount += 1
        return projection
    }

    func projectionCount() -> Int {
        completedProjectionCount
    }
}

enum AlbumGridEmptyReason: Equatable {
    case noFavorites
    case search(query: String, favoritesOnly: Bool)

    static func resolve(searchText: String, favoritesOnly: Bool) -> Self {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty, favoritesOnly {
            return .noFavorites
        }
        return .search(query: query, favoritesOnly: favoritesOnly)
    }
}
