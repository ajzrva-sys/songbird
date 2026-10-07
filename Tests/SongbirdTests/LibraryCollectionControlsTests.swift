import AppKit
import Testing
@testable import SongbirdLib

@Suite("Library collection controls")
struct LibraryCollectionControlsTests {
    @MainActor
    @Test("Select All belongs to the native search editor while text is focused")
    func textEditingKeepsNativeKeyboardCommands() {
        #expect(!TrackTableKeyboardRouting.ownsSelectAll(firstResponder: NSTextView()))
        #expect(!TrackTableKeyboardRouting.ownsSelectAll(firstResponder: NSTextField()))
        #expect(TrackTableKeyboardRouting.ownsSelectAll(firstResponder: NSTableView()))
        #expect(!TrackTableKeyboardRouting.acceptsTypeSelect(searchFocused: true, modifiers: []))
        #expect(!TrackTableKeyboardRouting.acceptsTypeSelect(searchFocused: false, modifiers: .command))
        #expect(TrackTableKeyboardRouting.acceptsTypeSelect(searchFocused: false, modifiers: .shift))
    }

    @MainActor
    @Test("Requesting search focus preserves the query and clearing filters preserves search")
    func searchAndFacetStateAreIndependent() {
        let search = LibrarySearchCoordinator()
        search.query = "Bowie"
        search.requestFocus()
        #expect(search.query == "Bowie")
        #expect(search.focusRequestID == 1)
        search.requestFocus()
        #expect(search.focusRequestID == 2)
        var filters = TrackTableFilterState(selectedArtist: "Bowie", selectedAlbumIDs: ["album"], selectedGenre: "Rock")
        filters.clear()
        #expect(!filters.isActive)
        #expect(search.query == "Bowie")
        filters.selectedGenre = "Jazz"
        search.clear()
        #expect(filters.selectedGenre == "Jazz")
        search.query = "Ambient"
        search.resetForNavigation()
        #expect(search.query.isEmpty)
    }

    @Test("Removing a chip keeps the other chosen filters")
    func targetedChipRemoval() {
        var filters = TrackTableFilterState(selectedArtist: "Artist", selectedAlbumIDs: ["a", "b"], selectedGenre: "Genre")
        filters.remove(.album("a"))
        #expect(filters.selectedAlbumIDs == ["b"])
        #expect(filters.selectedArtist == "Artist")
        #expect(filters.selectedGenre == "Genre")
        filters.remove(.genre)
        #expect(filters.selectedGenre == nil)
        #expect(filters.selectedArtist == "Artist")
        #expect(filters.selectedAlbumIDs == ["b"])
        filters.remove(.artist)
        #expect(filters.selectedAlbumIDs == ["b"])
    }

    @Test("Album chips preserve group identity and show existing edition detail")
    func duplicateAlbumTitlesHaveDistinctChips() {
        let filters = TrackTableFilterState(selectedAlbumIDs: ["a", "b"])
        let facets = TrackTableFacets(artists: [], albums: [
            .init(id: "a", title: "Same Album", detail: "2001 · Edition A", albumIDs: [], trackIDs: []),
            .init(id: "b", title: "Same Album", detail: "2002 · Edition B", albumIDs: [], trackIDs: [])
        ], genres: [])
        let chips = filters.chips(facets: facets)
        #expect(chips.map(\.id) == [.album("a"), .album("b")])
        #expect(chips.map(\.label) == ["Album: Same Album · 2001 · Edition A", "Album: Same Album · 2002 · Edition B"])
        #expect(filters.chips(facets: .empty).map(\.id) == [.album("a"), .album("b")])
    }

    @MainActor
    @Test("Removing an album chip recovers results while search and other hidden filters remain")
    func chipRemovalUpdatesTheRealProjection() async throws {
        let identifier = Track(path: "/tmp/collection-controls-fixture.flac", title: "Fixture").persistentModelID
        let first = LibraryTrackSnapshot(persistentIdentifier: identifier, title: "First", artist: "Artist", album: "Album A", genre: "Rock")
        let second = LibraryTrackSnapshot(persistentIdentifier: identifier, title: "Second", artist: "Artist", album: "Album B", genre: "Rock")
        let other = LibraryTrackSnapshot(persistentIdentifier: identifier, title: "Second Other", artist: "Other Artist", album: "Album C", genre: "Rock")
        let snapshot = LibrarySnapshot(revision: 1, tracks: [first, second, other], albums: [], playlists: [])
        let worker = TrackTableProjectionWorker()
        let initial = try await worker.project(snapshot: snapshot, request: TrackTableRequest(collection: .allTracks))
        let albumID = try #require(initial.facets.albums.first { $0.title == "Album A" }?.id)
        var filters = TrackTableFilterState(selectedArtist: "Artist", selectedAlbumIDs: [albumID], selectedGenre: "Rock")
        func request() -> TrackTableRequest {
            TrackTableRequest(
                collection: .allTracks,
                searchText: "Second",
                selectedArtist: filters.selectedArtist,
                selectedAlbumIDs: filters.selectedAlbumIDs,
                selectedGenre: filters.selectedGenre,
                includesFacets: false
            )
        }
        let noResults = try await worker.project(snapshot: snapshot, request: request())
        #expect(noResults.rows.isEmpty)
        filters.remove(.album(albumID))
        let recovered = try await worker.project(snapshot: snapshot, request: request())
        #expect(recovered.orderedIDs == [second.id])
        #expect(filters.selectedArtist == "Artist")
        #expect(filters.selectedGenre == "Rock")
        filters.clear()
        let cleared = try await worker.project(snapshot: snapshot, request: request())
        #expect(Set(cleared.orderedIDs) == [second.id, other.id])
        #expect(!cleared.orderedIDs.contains(first.id), "The query survives Clear All filters")
    }

    @Test("Empty sources offer an action that belongs to their collection")
    func emptyCollectionActions() {
        #expect(LibraryEmptyStatePolicy.sourceAction(for: .allTracks) == .importMusic)
        #expect(LibraryEmptyStatePolicy.sourceAction(for: .topPlayed) == .browseAllTracks)
        #expect(LibraryEmptyStatePolicy.sourceAction(for: .playlist(UUID()), playlistIsSmart: false) == .addTracks)
        #expect(LibraryEmptyStatePolicy.sourceAction(for: .playlist(UUID()), playlistIsSmart: true) == .editRules)
        #expect(LibraryEmptyStatePolicy.sourceAction(for: .playlist(UUID())) == nil)
        #expect(LibraryEmptyStatePolicy.sourceAction(for: .artist("Artist")) == .back)
        #expect(LibraryEmptyStatePolicy.sourceAction(for: .orderedTrackIDs([])) == nil)
    }

    @Test("No-result actions reset only the active constraints")
    func filteredEmptyActions() {
        #expect(LibraryEmptyStatePolicy.filteredActions(hasSearch: false) == [])
        #expect(LibraryEmptyStatePolicy.filteredActions(hasSearch: true) == [.clearSearch])
        #expect(LibraryEmptyStatePolicy.filteredActions(hasSearch: false, hasFilters: true) == [.clearFilters])
        #expect(LibraryEmptyStatePolicy.filteredActions(hasSearch: true, hasFilters: true) == [.clearSearch, .clearFilters])
        #expect(LibraryEmptyStatePolicy.filteredActions(hasSearch: true, favoritesOnly: true) == [.clearSearch, .showAllAlbums])
    }

    @MainActor
    @Test("A supplied empty-state action invokes only its owning workflow")
    func emptyStateDispatchesTheSuppliedWorkflow() {
        var addCount = 0
        var editCount = 0
        let add = LibraryEmptyStateAction(.addTracks) { addCount += 1 }
        let edit = LibraryEmptyStateAction(.editRules) { editCount += 1 }
        add.perform()
        #expect(addCount == 1)
        #expect(editCount == 0)
        edit.perform()
        #expect(editCount == 1)
        #expect(addCount == 1)
    }
}
