public struct BrowseListItem: Identifiable, Equatable {
    public let name: String
    public let detail: String
    public let metric: Int?

    public var id: String { name }

    public init(name: String, detail: String, metric: Int? = nil) {
        self.name = name
        self.detail = detail
        self.metric = metric
    }
}
