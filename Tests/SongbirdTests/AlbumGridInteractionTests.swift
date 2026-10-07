import AppKit
import SwiftData
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

    @Test("Artist Albums uses exact track artists and retains complete album groups")
    func artistScopeMembershipAndFilters() {
        let compilation = LibraryAlbumGroupSnapshot(
            id: "compilation", title: "Compilation", artist: "Various Artists",
            year: 2000, dateAdded: .distantPast, albumIDs: [UUID(), UUID()],
            trackIDs: [UUID(), UUID()], artworkReference: nil, discCount: 2,
            isFavorite: true, contributingArtistNames: ["CAPSULE", "Guest"]
        )
        let albumArtistOnly = LibraryAlbumGroupSnapshot(
            id: "album-artist-only", title: "Credited Album", artist: "CAPSULE",
            year: 2001, dateAdded: .distantPast, albumIDs: [UUID()],
            trackIDs: [UUID()], artworkReference: nil, discCount: 1,
            isFavorite: true, contributingArtistNames: ["Different Performer"]
        )
        let unfavorited = LibraryAlbumGroupSnapshot(
            id: "unfavorited", title: "Another Album", artist: "CAPSULE",
            year: 2002, dateAdded: .distantPast, albumIDs: [UUID()],
            trackIDs: [UUID()], artworkReference: nil, discCount: 1,
            isFavorite: false, contributingArtistNames: ["CAPSULE"]
        )
        let groups = [compilation, albumArtistOnly, unfavorited]

        let result = AlbumGridFilter.apply(
            to: groups, searchText: "", favoritesOnly: false, sortOrder: .year,
            scope: .artist(name: "CAPSULE")
        )
        #expect(result.map(\.id) == ["unfavorited", "compilation"])
        #expect(result.last == compilation)
        #expect(AlbumGridFilter.apply(
            to: groups, searchText: "Compilation", favoritesOnly: true, sortOrder: .title,
            scope: .artist(name: "CAPSULE")
        ) == [compilation])
        #expect(AlbumGridFilter.apply(
            to: groups, searchText: "", favoritesOnly: false, sortOrder: .title,
            scope: .artist(name: "capsule")
        ).isEmpty)
        #expect(AlbumGridFilter.apply(
            to: groups, searchText: "", favoritesOnly: false, sortOrder: .title,
            scope: .artist(name: "Guest")
        ) == [compilation])
    }

    @Test("Changing artist scope invalidates the album grid cache")
    func artistScopeCache() async throws {
        let groups = [
            LibraryAlbumGroupSnapshot(
                id: "first", title: "First", artist: "Album Artist", year: 2000,
                dateAdded: .distantPast, albumIDs: [UUID()], trackIDs: [UUID()],
                artworkReference: nil, discCount: 1, isFavorite: false,
                contributingArtistNames: ["First Performer"]
            ),
            LibraryAlbumGroupSnapshot(
                id: "second", title: "Second", artist: "Album Artist", year: 2000,
                dateAdded: .distantPast, albumIDs: [UUID()], trackIDs: [UUID()],
                artworkReference: nil, discCount: 1, isFavorite: false,
                contributingArtistNames: ["Second Performer"]
            ),
        ]
        let worker = AlbumGridProjectionWorker()
        let firstRequest = AlbumGridProjectionRequest(
            sourceRevision: 1, searchText: "", favoritesOnly: false, sortOrder: .title,
            scope: .artist(name: "First Performer")
        )
        let secondRequest = AlbumGridProjectionRequest(
            sourceRevision: 1, searchText: "", favoritesOnly: false, sortOrder: .title,
            scope: .artist(name: "Second Performer")
        )

        #expect(try await worker.project(groups: groups, request: firstRequest).orderedIDs == ["first"])
        #expect(try await worker.project(groups: groups, request: firstRequest).orderedIDs == ["first"])
        #expect(await worker.projectionCount() == 1)
        #expect(try await worker.project(groups: groups, request: secondRequest).orderedIDs == ["second"])
        #expect(await worker.projectionCount() == 2)
    }

    @Test("Artist membership survives presentation refresh and changes with track metadata")
    @MainActor
    func artistMembershipRefreshAndFallback() async throws {
        let identifier = Track(path: "/Fixture/Album/01.flac", title: "Fixture").persistentModelID
        let albumID = UUID()
        let trackID = UUID()
        func track(artist: String) -> LibraryTrackSnapshot {
            LibraryTrackSnapshot(
                id: trackID, persistentIdentifier: identifier, title: "Fixture",
                artist: artist, album: "Album", albumArtist: "Album Artist",
                path: "/Fixture/Album/01.flac", albumID: albumID
            )
        }
        let album = LibraryAlbumSnapshot(
            id: albumID, persistentIdentifier: identifier, title: "Album",
            artist: "Album Artist", trackIDs: [trackID]
        )
        let firstSnapshot = LibrarySnapshot(
            revision: 1, albumStructureRevision: 1,
            tracks: [track(artist: "Performer")], albums: [album], playlists: []
        )
        let worker = LibraryAlbumProjectionWorker()
        let store = LibraryAlbumProjectionStore(worker: worker)
        let fallback = try #require(store.group(containing: albumID, fallback: firstSnapshot))
        #expect(fallback.artist == "Album Artist")
        #expect(fallback.contributingArtistNames == ["Performer"])
        await store.update(from: firstSnapshot)
        let first = try #require(store.group(containing: albumID))
        #expect(first.contributingArtistNames == ["Performer"])

        await store.update(from: LibrarySnapshot(
            revision: 2, albumStructureRevision: 1,
            tracks: [track(artist: "Performer")], albums: [album.withFavorite(true)], playlists: []
        ))
        let decorated = try #require(store.group(containing: albumID))
        #expect(decorated.isFavorite)
        #expect(decorated.contributingArtistNames == ["Performer"])
        #expect(await worker.projectionCount() == 1)

        await store.update(from: LibrarySnapshot(
            revision: 3, albumStructureRevision: 3,
            tracks: [track(artist: "Renamed Performer")], albums: [album.withFavorite(true)], playlists: []
        ))
        let renamed = try #require(store.group(containing: albumID))
        #expect(renamed.id == first.id)
        #expect(renamed.contributingArtistNames == ["Renamed Performer"])
        #expect(AlbumGridFilter.apply(
            to: store.groups, searchText: "", favoritesOnly: false, sortOrder: .title,
            scope: .artist(name: "Performer")
        ).isEmpty)
        #expect(AlbumGridFilter.apply(
            to: store.groups, searchText: "", favoritesOnly: false, sortOrder: .title,
            scope: .artist(name: "Renamed Performer")
        ) == [renamed])
        #expect(await worker.projectionCount() == 2)
    }

    @Test("Saving a track artist refreshes the artist album membership")
    @MainActor
    func savedArtistMetadataRefreshesMembership() async throws {
        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true),
        ])
        let context = container.mainContext
        context.autosaveEnabled = false
        let album = Album(title: "Fixture Album", artist: "Album Artist")
        let track = Track(
            path: "/Fixture/Artist Album/01.flac", title: "Fixture Track",
            artist: "Original Performer", album: album.title
        )
        track.albumArtist = album.artist
        track.albumRelation = album
        context.insert(album)
        context.insert(track)
        try context.save()
        let snapshots = LibrarySnapshotStore(modelContainer: container, startsImmediately: false)
        await snapshots.refresh()
        let albums = LibraryAlbumProjectionStore()
        await albums.update(from: snapshots.snapshot)
        let originalStructureRevision = snapshots.snapshot.albumStructureRevision
        #expect(albums.groups.first?.contributingArtistNames == ["Original Performer"])

        track.artist = "New Performer"
        try context.save()
        await snapshots.refreshAfterMutation()
        #expect(snapshots.snapshot.albumStructureRevision != originalStructureRevision)
        await albums.update(from: snapshots.snapshot)
        #expect(albums.groups.first?.contributingArtistNames == ["New Performer"])
        #expect(albums.groups.first?.artist == "Album Artist")
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

    @Test("Missing Album Art sorts uncovered albums first and preserves filters")
    func missingArtworkSort() async throws {
        func group(_ id: String, _ title: String, covered: Bool, favorite: Bool = true) -> LibraryAlbumGroupSnapshot {
            LibraryAlbumGroupSnapshot(
                id: id, title: title, artist: "Artist", year: 2000, dateAdded: .distantPast,
                albumIDs: [UUID()], trackIDs: [UUID()],
                artworkReference: covered ? .embedded(id: UUID(), data: Data([1])) : nil,
                discCount: 1, isFavorite: favorite
            )
        }
        let groups = [
            group("covered", "Alpha", covered: true),
            group("z", "Zed", covered: false, favorite: false),
            group("b", "Same", covered: false),
            group("a", "Same", covered: false),
        ]
        let result = AlbumGridFilter.apply(to: groups, searchText: "", favoritesOnly: false, sortOrder: .missingArtwork)
        #expect(result.map(\.id) == ["a", "b", "z", "covered"])
        let filtered = AlbumGridFilter.apply(to: groups, searchText: "Same", favoritesOnly: true, sortOrder: .missingArtwork)
        #expect(filtered.map(\.id) == ["a", "b"])
        let favorites = AlbumGridFilter.apply(to: groups, searchText: "", favoritesOnly: true, sortOrder: .missingArtwork)
        #expect(favorites.map(\.id) == ["a", "b", "covered"])

        let worker = AlbumGridProjectionWorker()
        let first = try await worker.project(groups: groups, request: AlbumGridProjectionRequest(
            sourceRevision: 1, searchText: "", favoritesOnly: false, sortOrder: .missingArtwork
        ))
        var updated = groups
        updated[3] = group("a", "Same", covered: true)
        let second = try await worker.project(groups: updated, request: AlbumGridProjectionRequest(
            sourceRevision: 2, searchText: "", favoritesOnly: false, sortOrder: .missingArtwork
        ))
        #expect(first.orderedIDs == ["a", "b", "z", "covered"])
        #expect(second.orderedIDs == ["b", "z", "covered", "a"])
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
