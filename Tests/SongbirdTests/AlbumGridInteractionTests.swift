import AppKit
import Testing
@testable import SongbirdLib

@Suite("Album grid interactions")
struct AlbumGridInteractionTests {
    @Test("Album projection memoizes inputs and preserves selected context order")
    func memoizedProjection() async throws {
        let groups = [
            LibraryAlbumGroupSnapshot(
                id: "b",
                title: "Beta",
                artist: "Artist",
                year: 2002,
                dateAdded: .distantPast,
                albumIDs: [UUID()],
                trackIDs: [UUID()],
                artworkReference: nil,
                discCount: 1,
                isFavorite: true
            ),
            LibraryAlbumGroupSnapshot(
                id: "a",
                title: "Alpha",
                artist: "Artist",
                year: 2001,
                dateAdded: .distantPast,
                albumIDs: [UUID()],
                trackIDs: [UUID()],
                artworkReference: nil,
                discCount: 1,
                isFavorite: true
            ),
        ]
        let request = AlbumGridProjectionRequest(
            sourceRevision: 7,
            searchText: "  ",
            favoritesOnly: true,
            sortOrder: .title
        )
        let worker = AlbumGridProjectionWorker()

        let first = try await worker.project(groups: groups, request: request)
        let second = try await worker.project(groups: groups, request: request)

        #expect(first == second)
        #expect(await worker.projectionCount() == 1)
        #expect(first.orderedIDs == ["a", "b"])
        #expect(first.contextAlbums(clickedID: "b", selectedIDs: ["a", "b"]).map(\.id) == ["a", "b"])
    }

    @Test("Recently Added fixes the newest 100 before applying search and Favorites")
    func recentlyAddedScope() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        var groups: [LibraryAlbumGroupSnapshot] = []
        for index in 0..<101 {
            let title = index == 0 ? "Needle Favorite" : "Album \(index)"
            groups.append(LibraryAlbumGroupSnapshot(
                id: String(format: "album-%03d", index), title: title, artist: "Artist",
                year: 2000, dateAdded: base.addingTimeInterval(TimeInterval(index)),
                albumIDs: [UUID()], trackIDs: [UUID()], artworkReference: nil,
                discCount: 1, isFavorite: index == 0
            ))
        }

        let recent = AlbumGridFilter.apply(
            to: groups,
            searchText: "",
            favoritesOnly: false,
            sortOrder: .title,
            scope: .recentlyAdded(limit: 100)
        )
        let searched = AlbumGridFilter.apply(
            to: groups,
            searchText: "Needle",
            favoritesOnly: false,
            sortOrder: .title,
            scope: .recentlyAdded(limit: 100)
        )
        let favorites = AlbumGridFilter.apply(
            to: groups,
            searchText: "",
            favoritesOnly: true,
            sortOrder: .title,
            scope: .recentlyAdded(limit: 100)
        )

        #expect(recent.count == 100)
        #expect(recent.first?.id == "album-100")
        #expect(recent.last?.id == "album-001")
        #expect(searched.isEmpty)
        #expect(favorites.isEmpty)
    }

    @Test("Recently Added uses title and stable ID to break equal-date ties")
    func recentlyAddedDeterministicTies() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let groups = [
            album(id: "b", title: "Same", dateAdded: date),
            album(id: "c", title: "Zed", dateAdded: date),
            album(id: "a", title: "Same", dateAdded: date),
        ]

        let result = AlbumGridFilter.apply(
            to: groups,
            searchText: "",
            favoritesOnly: false,
            sortOrder: .year,
            scope: .recentlyAdded(limit: 100)
        )

        #expect(result.map(\.id) == ["a", "b", "c"])
    }

    private func album(id: String, title: String, dateAdded: Date) -> LibraryAlbumGroupSnapshot {
        LibraryAlbumGroupSnapshot(
            id: id,
            title: title,
            artist: "Artist",
            year: 2000,
            dateAdded: dateAdded,
            albumIDs: [UUID()],
            trackIDs: [UUID()],
            artworkReference: nil,
            discCount: 1,
            isFavorite: false
        )
    }

    @Test("Album columns retain their gutter by dropping a column at narrow widths")
    func responsiveColumnCount() {
        #expect(AlbumGridLayout.columnCount(
            forContentWidth: 805,
            artworkSize: 160,
            spacing: 16
        ) == 4)
        #expect(AlbumGridLayout.columnCount(
            forContentWidth: 864,
            artworkSize: 160,
            spacing: 16
        ) == 5)
        #expect(AlbumGridLayout.columnCount(
            forContentWidth: 805,
            artworkSize: 120,
            spacing: 16
        ) == 6)
        #expect(AlbumGridLayout.columnCount(
            forContentWidth: 805,
            artworkSize: 200,
            spacing: 16
        ) == 3)
        #expect(AlbumGridLayout.columnCount(
            forContentWidth: 847,
            artworkSize: 160,
            spacing: 8
        ) == 5)
        #expect(AlbumGridLayout.columnCount(
            forContentWidth: 847,
            artworkSize: 160,
            spacing: 24
        ) == 4)
    }

    @Test("Album artwork size uses stable defaults, steps, and bounds")
    func artworkSizeSettings() {
        #expect(AlbumGridSettings.defaultArtworkSize == 160)
        #expect(AlbumGridSettings.artworkSizeRange == 120...240)
        #expect(AlbumGridSettings.artworkSizeStep == 20)
        #expect(AlbumGridSettings.normalizedArtworkSize(80) == 120)
        #expect(AlbumGridSettings.normalizedArtworkSize(171) == 180)
        #expect(AlbumGridSettings.normalizedArtworkSize(300) == 240)
        #expect(AlbumGridSettings.normalizedArtworkSize(.nan) == 160)
    }

    @Test("Album grid spacing uses stable defaults, steps, and bounds")
    func gridSpacingSettings() {
        #expect(AlbumGridSettings.gridSpacingKey == "albumGrid.gridSpacing")
        #expect(AlbumGridSettings.defaultGridSpacing == 16)
        #expect(AlbumGridSettings.gridSpacingRange == 8...48)
        #expect(AlbumGridSettings.gridSpacingStep == 4)
        #expect(AlbumGridSettings.normalizedGridSpacing(0) == 8)
        #expect(AlbumGridSettings.normalizedGridSpacing(19) == 20)
        #expect(AlbumGridSettings.normalizedGridSpacing(99) == 48)
        #expect(AlbumGridSettings.normalizedGridSpacing(.infinity) == 16)
    }

    @Test("Album size examples select two unique gallery albums")
    func artworkExampleSelection() {
        let ids = ["album-a", "album-b", "album-c", "album-a"]

        let selected = AlbumGridExampleSelection.choose(from: ids)

        #expect(selected.count == 2)
        #expect(Set(selected).count == 2)
        #expect(Set(selected).isSubset(of: Set(ids)))
    }

    @Test("Single, Command, and Shift clicks build the expected album selection")
    func modifierSelection() {
        // Given
        let albums = ["a", "b", "c", "d"]
        var selection = AlbumGridSelectionState()

        // When
        selection.select("b", in: albums, modifiers: [])
        selection.select("d", in: albums, modifiers: .shift)
        selection.select("a", in: albums, modifiers: .command)

        // Then
        #expect(selection.selectedIDs == ["a", "b", "c", "d"])
        #expect(selection.anchorID == "a")
    }

    @Test("Command-click toggles an album without clearing the rest")
    func commandClickToggles() {
        // Given
        let albums = ["a", "b", "c"]
        var selection = AlbumGridSelectionState()
        selection.select("a", in: albums, modifiers: [])
        selection.select("b", in: albums, modifiers: .command)

        // When
        selection.select("a", in: albums, modifiers: .command)

        // Then
        #expect(selection.selectedIDs == ["b"])
    }

    @Test("Album empty states distinguish Favorites from search")
    func albumEmptyReasons() {
        #expect(
            AlbumGridEmptyReason.resolve(searchText: "", favoritesOnly: true)
                == .noFavorites
        )
        #expect(
            AlbumGridEmptyReason.resolve(searchText: "Ambient", favoritesOnly: false)
                == .search(query: "Ambient", favoritesOnly: false)
        )
        #expect(
            AlbumGridEmptyReason.resolve(searchText: "  Ambient  ", favoritesOnly: true)
                == .search(query: "Ambient", favoritesOnly: true)
        )
    }

    @MainActor
    @Test("A normal click selects immediately and a double-click invokes Play")
    func immediateClickDispatch() {
        // Given
        var singleClickModifiers: [NSEvent.ModifierFlags] = []
        let albumTrackIDs = [UUID(), UUID(), UUID()]
        var playedTrackIDs: [UUID] = []
        var playInvocationCount = 0
        let coordinator = MacClickActivationView.Coordinator(
            singleClick: { singleClickModifiers.append($0) },
            doubleClick: {
                playedTrackIDs = albumTrackIDs
                playInvocationCount += 1
            }
        )

        // When
        coordinator.handleClick(count: 1, modifiers: .command)

        // Then
        #expect(singleClickModifiers.count == 1)
        #expect(singleClickModifiers[0].contains(.command))
        #expect(playedTrackIDs.isEmpty)

        // When
        coordinator.handleClick(count: 2, modifiers: [])

        // Then
        #expect(singleClickModifiers.count == 1)
        #expect(playedTrackIDs == albumTrackIDs)
        #expect(playInvocationCount == 1)

        // When
        coordinator.handleClick(count: 3, modifiers: [])

        // Then
        #expect(singleClickModifiers.count == 1)
        #expect(playedTrackIDs == albumTrackIDs)
        #expect(playInvocationCount == 1)
    }
}
