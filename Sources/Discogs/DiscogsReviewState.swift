import Foundation
import Observation

/// One loaded surface owns its payload, selection, tasks and publication lease.
@MainActor @Observable
final class DiscogsReviewState<Item: Identifiable> {
    var items: [Item] = []
    var selectedID: Item.ID?
    var reviewIndex = 0
    var generation = UUID()
    var task: Task<Void, Never>?
    var targets: [DiscogsArtworkAlbumTarget] = []
    var requiresSearch = false
    private(set) var now: DiscogsFetchStamp?
    private let clock: () -> DiscogsFetchStamp?
    private let evidence: (Item) -> [DiscogsContentEvidence]

    init(clock: @escaping () -> DiscogsFetchStamp? = DiscogsClock.sample,
        evidence: @escaping (Item) -> [DiscogsContentEvidence]) {
        self.clock = clock
        self.evidence = evidence
    }
    var selectedItem: Item? { items.first { $0.id == selectedID } }
    @discardableResult func beginSearch(targets: [DiscogsArtworkAlbumTarget]? = nil) -> UUID {
        invalidate()
        items = []
        reviewIndex = 0
        requiresSearch = false
        if let targets { self.targets = targets }
        return generation
    }
    @discardableResult func publish(_ values: [Item], generation: UUID) -> Bool {
        guard generation == self.generation, !requiresSearch else { return false }
        now = clock()
        let fresh = freshItems(values, at: now)
        items = fresh
        if fresh.count != values.count {
            requiresSearch = true
            invalidate()
            return false
        }
        return true
    }
    func select(id: Item.ID) {
        _ = expire(at: clock())
        guard !requiresSearch, items.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }
    @discardableResult func expire(at now: DiscogsFetchStamp?) -> Bool {
        self.now = now
        let currentID = items.indices.contains(reviewIndex) ? items[reviewIndex].id : nil
        let fresh = freshItems(items, at: now)
        guard fresh.count != items.count else { return false }
        items = fresh
        reviewIndex = items.firstIndex { $0.id == currentID } ?? min(reviewIndex, max(0, items.count - 1))
        requiresSearch = true
        invalidate()
        return true
    }
    private func freshItems(_ values: [Item], at now: DiscogsFetchStamp?) -> [Item] {
        values.filter { item in
            let stamps = evidence(item)
            return !stamps.isEmpty && stamps.allSatisfy { $0.isFresh(at: now) }
        }
    }
    func advance() -> Bool {
        reviewIndex += 1
        guard reviewIndex >= items.count else { return false }
        items = []
        selectedID = nil
        reviewIndex = 0
        return true
    }

    func invalidate() {
        task?.cancel()
        task = nil
        selectedID = nil
        generation = UUID()
    }
}
