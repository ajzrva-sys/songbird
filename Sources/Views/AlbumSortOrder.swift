public enum AlbumSortOrder: String, CaseIterable, Hashable, Identifiable, Sendable {
    case title = "Title"
    case artist = "Artist"
    case year = "Year"
    case missingArtwork = "Missing Album Art"
    case recentlyAdded = "Recently Added"

    public var id: Self { self }
}
