import Combine
import Foundation

@MainActor
public final class LibraryAlbumProjectionStore: ObservableObject {
    @Published public private(set) var state: LibraryProjectionState<[LibraryAlbumGroupSnapshot]> =
        .loading(previous: nil)

    private let project: @Sendable (LibrarySnapshot) async throws -> [LibraryAlbumGroupSnapshot]
    private let detailBuilder: @Sendable ([LibraryAlbumGroupSnapshot]) -> [String: String]
    private var projectionTask: Task<Void, Never>?
    private var inFlightKey: ProjectionKey?

    private struct ProjectionKey: Equatable {
        let revision: Int
        let structure: Int
        let presentation: Int
    }
    private var requestGeneration = 0
    private var projectedStructureRevision: Int?
    private var projectedPresentationRevision: Int?
    private var structuralGroups: [LibraryAlbumGroupSnapshot] = []
    private var groupsByAlbumID: [UUID: LibraryAlbumGroupSnapshot] = [:]
    private var detailsByGroupID: [String: String] = [:]
    @Published public private(set) var projectionRevision = 0

    public init(worker: LibraryAlbumProjectionWorker = LibraryAlbumProjectionWorker()) {
        self.project = { try await worker.project($0) }
        self.detailBuilder = { LibraryAlbumDisplayDetail.details(for: $0) }
    }

    init(
        worker: LibraryAlbumProjectionWorker,
        detailBuilder: @escaping @Sendable ([LibraryAlbumGroupSnapshot]) -> [String: String]
    ) {
        self.project = { try await worker.project($0) }
        self.detailBuilder = detailBuilder
    }

    init(project: @escaping @Sendable (LibrarySnapshot) async throws -> [LibraryAlbumGroupSnapshot]) {
        self.project = project
        self.detailBuilder = { LibraryAlbumDisplayDetail.details(for: $0) }
    }

    /// Constant-time header lookup. Labels depend on the whole structure, not
    /// artwork/favorites, and are derived only when that structure is replaced.
    public func displayDetail(forGroupID groupID: String) -> String? {
        detailsByGroupID[groupID]
    }

    deinit {
        projectionTask?.cancel()
    }

    public var groups: [LibraryAlbumGroupSnapshot] {
        state.value ?? []
    }

    public func group(containing albumID: UUID) -> LibraryAlbumGroupSnapshot? {
        groupsByAlbumID[albumID]
    }

    /// Album routes should not wait for the full-library grouping pass. This
    /// lightweight snapshot fallback is replaced automatically once projection finishes.
    public func group(
        containing albumID: UUID,
        fallback snapshot: LibrarySnapshot
    ) -> LibraryAlbumGroupSnapshot? {
        if let projected = group(containing: albumID) { return projected }
        guard let album = snapshot.albumsByID[albumID] else { return nil }

        return LibraryAlbumGroupSnapshot(
            id: "album:\(album.id.uuidString)",
            title: album.title,
            artist: album.artist,
            year: album.year,
            dateAdded: album.dateAdded,
            albumIDs: [album.id],
            trackIDs: album.trackIDs,
            artworkReference: album.artworkReference,
            discCount: 1,
            isFavorite: album.isFavorite
        )
    }

    public func update(from snapshot: LibrarySnapshot, force: Bool = false) async {
        let key = ProjectionKey(revision: snapshot.revision,
                                structure: snapshot.albumStructureRevision,
                                presentation: snapshot.albumPresentationRevision)
        if inFlightKey == key, let projectionTask {
            // The app and an opening detail can request the same snapshot.
            // Cancelling one waiter must not cancel the store-owned shared work.
            await projectionTask.value
            return
        }
        guard force
            || projectedStructureRevision != snapshot.albumStructureRevision
            || projectedPresentationRevision != snapshot.albumPresentationRevision
        else { return }
        projectionTask?.cancel()
        projectionTask = nil
        inFlightKey = nil
        requestGeneration += 1
        let generation = requestGeneration

        if force == false,
           projectedStructureRevision == snapshot.albumStructureRevision {
            projectionRevision = snapshot.revision
            let decorated = Self.decorate(structuralGroups, from: snapshot)
            groupsByAlbumID = Self.index(decorated)
            state = .loaded(decorated)
            projectedPresentationRevision = snapshot.albumPresentationRevision
            return
        }

        inFlightKey = key
        state = .loading(previous: state.value)
        projectionTask = Task { [weak self, project] in
            defer {
                if self?.requestGeneration == generation {
                    self?.inFlightKey = nil
                    self?.projectionTask = nil
                }
            }
            do {
                let groups = try await project(snapshot)
                try Task.checkCancellation()
                guard let self, self.requestGeneration == generation else { return }
                self.detailsByGroupID = self.detailBuilder(groups)
                self.structuralGroups = groups
                self.projectedStructureRevision = snapshot.albumStructureRevision
                self.projectedPresentationRevision = snapshot.albumPresentationRevision
                self.projectionRevision = snapshot.revision
                let decorated = Self.decorate(groups, from: snapshot)
                self.groupsByAlbumID = Self.index(decorated)
                self.state = .loaded(decorated)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self,
                      self.requestGeneration == generation else { return }
                self.state = .failed(
                    message: error.localizedDescription,
                    previous: self.state.value
                )
            }
        }
        await projectionTask?.value
    }

    private static func decorate(
        _ groups: [LibraryAlbumGroupSnapshot],
        from snapshot: LibrarySnapshot
    ) -> [LibraryAlbumGroupSnapshot] {
        return groups.map { group in
            let albums = group.albumIDs.compactMap { snapshot.albumsByID[$0] }
            return LibraryAlbumGroupSnapshot(
                id: group.id,
                title: group.title,
                artist: group.artist,
                year: group.year,
                dateAdded: albums.map(\.dateAdded).max() ?? group.dateAdded,
                albumIDs: group.albumIDs,
                trackIDs: group.trackIDs,
                artworkReference: albums.lazy.compactMap(\.artworkReference).first,
                discCount: group.discCount,
                partCount: group.partCount,
                collectionKind: group.collectionKind,
                editionLabel: group.editionLabel,
                isFavorite: albums.isEmpty == false && albums.allSatisfy(\.isFavorite)
            )
        }
    }

    private static func index(
        _ groups: [LibraryAlbumGroupSnapshot]
    ) -> [UUID: LibraryAlbumGroupSnapshot] {
        Dictionary(
            groups.flatMap { group in group.albumIDs.map { ($0, group) } },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
