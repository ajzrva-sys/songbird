import Foundation
import SwiftData
import Testing
@testable import SongbirdLib

@Suite("Library Health mutations", .serialized)
struct LibraryHealthMutationTests {
    @Test("Apply updates metadata and album relationship, then Undo restores both")
    @MainActor
    func applyAndUndo() async throws {
        let container = try makeContainer()
        let track = try insertTrack(path: "/Music/New Album/01.flac", in: container)
        let service = LibraryHealthMutationService(modelContainer: container)
        let plan = makePlan(changes: [change(track.id, from: "Unknown Album", to: "New Album")])

        let (outcome, receipt) = try await service.apply(plan)
        let applied = try fetchTrack(track.id, from: container)
        #expect(outcome.affectedTrackCount == 1)
        #expect(applied.album == "New Album")
        #expect(applied.albumRelation?.title == "New Album")
        #expect(applied.artistRelation?.name == "Artist")

        _ = try await service.undo(receipt)
        let restored = try fetchTrack(track.id, from: container)
        #expect(restored.album == "Unknown Album")
        #expect(restored.albumRelation?.title == "Unknown Album")
    }

    @Test("Drift refuses the complete batch before any mutation")
    @MainActor
    func driftRefusesBatch() async throws {
        let container = try makeContainer()
        let first = try insertTrack(path: "/Music/A/01.flac", in: container)
        let second = try insertTrack(path: "/Music/B/01.flac", in: container)
        let service = LibraryHealthMutationService(modelContainer: container)
        second.album = "Edited Elsewhere"
        try container.mainContext.save()
        let plan = makePlan(changes: [
            change(first.id, from: "Unknown Album", to: "A"),
            change(second.id, from: "Unknown Album", to: "B"),
        ])

        do {
            _ = try await service.apply(plan)
            Issue.record("Expected drift refusal")
        } catch let error as LibraryHealthMutationError {
            guard case .driftedTarget(let id, _, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(id == second.id)
        }
        #expect(try fetchTrack(first.id, from: container).album == "Unknown Album")
        #expect(try fetchTrack(second.id, from: container).album == "Edited Elsewhere")
    }

    @Test("Undo also refuses drift without a partial restore")
    @MainActor
    func undoRefusesDrift() async throws {
        let container = try makeContainer()
        let first = try insertTrack(path: "/Music/A/01.flac", in: container)
        let second = try insertTrack(path: "/Music/B/01.flac", in: container)
        let service = LibraryHealthMutationService(modelContainer: container)
        let (outcome, receipt) = try await service.apply(makePlan(changes: [
            change(first.id, from: "Unknown Album", to: "A"),
            change(second.id, from: "Unknown Album", to: "B"),
        ]))
        #expect(outcome.affectedTrackCount == 2)
        let editContext = ModelContext(container)
        let edited = try #require(
            editContext.fetch(FetchDescriptor<Track>()).first { $0.id == second.id }
        )
        edited.album = "Changed After Apply"
        try editContext.save()

        await #expect(throws: LibraryHealthMutationError.self) {
            _ = try await service.undo(receipt)
        }
        #expect(try fetchTrack(first.id, from: container).album == "A")
    }

    @Test("Applying an unrelated Health edit never deletes duplicate Artist records")
    @MainActor
    func unrelatedDuplicateArtistsSurvive() async throws {
        let container = try makeContainer()
        let track = try insertTrack(path: "/Music/A/01.flac", in: container)
        let unrelated = Track(
            path: "/Music/Elsewhere/01.flac",
            title: "Elsewhere",
            artist: "Artist",
            album: "Elsewhere"
        )
        let duplicateArtist = Artist(name: "Artist")
        unrelated.artistRelation = duplicateArtist
        container.mainContext.insert(duplicateArtist)
        container.mainContext.insert(unrelated)
        try container.mainContext.save()

        let service = LibraryHealthMutationService(modelContainer: container)
        _ = try await service.apply(makePlan(changes: [
            change(track.id, from: "Unknown Album", to: "A"),
        ]))

        let context = ModelContext(container)
        let artists = try context.fetch(FetchDescriptor<Artist>())
        let tracks = try context.fetch(FetchDescriptor<Track>())
        #expect(artists.count { $0.name == "Artist" } == 2)
        #expect(tracks.first { $0.id == unrelated.id }?.artistRelation?.id == duplicateArtist.id)
    }

    @Test("Supported string and numeric fields apply and undo through one boundary")
    @MainActor
    func supportedFieldsApplyAndUndo() async throws {
        let container = try makeContainer()
        let track = try insertTrack(path: "/Music/A/01.flac", in: container)
        let service = LibraryHealthMutationService(modelContainer: container)

        let (_, titleReceipt) = try await service.apply(makePlan(changes: [
            change(track.id, field: .title, from: "Track", to: "Corrected"),
        ]))
        #expect(try fetchTrack(track.id, from: container).title == "Corrected")
        _ = try await service.undo(titleReceipt)
        #expect(try fetchTrack(track.id, from: container).title == "Track")

        let (_, yearReceipt) = try await service.apply(makePlan(changes: [
            change(track.id, field: .year, from: "0", to: "2024"),
        ]))
        #expect(try fetchTrack(track.id, from: container).year == 2024)
        _ = try await service.undo(yearReceipt)
        #expect(try fetchTrack(track.id, from: container).year == 0)
    }

    @Test("Unsupported fields and invalid numeric values refuse before save")
    @MainActor
    func unsupportedAndInvalidValuesRefuse() async throws {
        let container = try makeContainer()
        let track = try insertTrack(path: "/Music/A/01.flac", in: container)
        let service = LibraryHealthMutationService(modelContainer: container)

        await #expect(throws: LibraryHealthMutationError.self) {
            _ = try await service.apply(makePlan(changes: [
                change(track.id, field: .albumArtwork, from: "", to: "x"),
            ]))
        }
        await #expect(throws: LibraryHealthMutationError.self) {
            _ = try await service.apply(makePlan(changes: [
                change(track.id, field: .trackNumber, from: "0", to: "not-a-number"),
            ]))
        }
        #expect(try fetchTrack(track.id, from: container).trackNumber == 0)
    }

    @Test("Missing-file relocation updates technical fields once and Undo restores them exactly")
    @MainActor
    func relocationApplyAndUndo() async throws {
        let container = try makeContainer()
        let track = try insertTrack(path: "/missing/original.flac", in: container)
        track.checksum = "catalog-checksum"
        track.fileSize = 91
        track.dateModified = Date(timeIntervalSince1970: 123)
        try container.mainContext.save()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-health-relocation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let candidate = folder.appendingPathComponent("original.flac")
        try Data([1, 2, 3, 4, 5]).write(to: candidate)
        let candidateChecksum = Track.contentChecksum(at: candidate.path)
        let service = LibraryHealthMutationService(modelContainer: container)

        let (outcome, receipt) = try await service.applyRelocations([
            LibraryPathChange(
                trackID: track.id,
                expectedOldPath: track.path,
                candidatePath: candidate.path,
                expectedCandidateChecksum: candidateChecksum,
                sourceRevision: 1
            ),
        ])
        let applied = try fetchTrack(track.id, from: container)
        #expect(outcome.affectedTrackCount == 1)
        #expect(applied.path == candidate.path)
        #expect(applied.checksum == candidateChecksum)
        #expect(applied.fileSize == 5)

        _ = try await service.undo(receipt)
        let restored = try fetchTrack(track.id, from: container)
        #expect(restored.path == "/missing/original.flac")
        #expect(restored.checksum == "catalog-checksum")
        #expect(restored.fileSize == 91)
        #expect(restored.dateModified == Date(timeIntervalSince1970: 123))
        #expect(FileManager.default.fileExists(atPath: candidate.path))
    }

    @Test("Relocation candidate drift refuses the whole batch")
    @MainActor
    func relocationDriftIsAtomic() async throws {
        let container = try makeContainer()
        let first = try insertTrack(path: "/missing/first.flac", in: container)
        let second = try insertTrack(path: "/missing/second.flac", in: container)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-health-relocation-drift-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let firstCandidate = folder.appendingPathComponent("first.flac")
        let secondCandidate = folder.appendingPathComponent("second.flac")
        try Data([1]).write(to: firstCandidate)
        try Data([2]).write(to: secondCandidate)
        let firstChecksum = Track.contentChecksum(at: firstCandidate.path)
        let staleSecondChecksum = Track.contentChecksum(at: secondCandidate.path)
        try Data([9, 9]).write(to: secondCandidate)
        let service = LibraryHealthMutationService(modelContainer: container)

        await #expect(throws: LibraryHealthMutationError.self) {
            _ = try await service.applyRelocations([
                LibraryPathChange(
                    trackID: first.id,
                    expectedOldPath: first.path,
                    candidatePath: firstCandidate.path,
                    expectedCandidateChecksum: firstChecksum,
                    sourceRevision: 1
                ),
                LibraryPathChange(
                    trackID: second.id,
                    expectedOldPath: second.path,
                    candidatePath: secondCandidate.path,
                    expectedCandidateChecksum: staleSecondChecksum,
                    sourceRevision: 1
                ),
            ])
        }
        #expect(try fetchTrack(first.id, from: container).path == "/missing/first.flac")
        #expect(try fetchTrack(second.id, from: container).path == "/missing/second.flac")
    }

    @Test("Artwork applies to the complete group once and Undo restores exact bytes")
    @MainActor
    func artworkApplyAndUndo() async throws {
        let container = try makeContainer()
        let first = try insertTrack(path: "/Music/Set/CD 1/01.flac", in: container)
        let second = try insertTrack(path: "/Music/Set/CD 2/01.flac", in: container)
        let firstAlbum = try #require(first.albumRelation)
        let secondAlbum = try #require(second.albumRelation)
        let image = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let service = LibraryHealthMutationService(modelContainer: container)

        let (outcome, receipt) = try await service.applyArtwork([
            LibraryArtworkChange(albumID: firstAlbum.id, expectedArtworkDigest: nil, imageData: image),
            LibraryArtworkChange(albumID: secondAlbum.id, expectedArtworkDigest: nil, imageData: image),
        ])
        #expect(outcome.affectedAlbumCount == 2)
        #expect(outcome.affectedTrackCount == 2)
        let applied = try ModelContext(container).fetch(FetchDescriptor<Album>())
        #expect(applied.filter { [$0.id].contains(firstAlbum.id) || [$0.id].contains(secondAlbum.id) }
            .allSatisfy { $0.artworkData == image })

        _ = try await service.undo(receipt)
        let restored = try ModelContext(container).fetch(FetchDescriptor<Album>())
        #expect(restored.filter { $0.id == firstAlbum.id || $0.id == secondAlbum.id }
            .allSatisfy { $0.artworkData == nil })
    }

    @Test("Artwork drift refuses a group before any mutation")
    @MainActor
    func artworkDriftIsAtomic() async throws {
        let container = try makeContainer()
        let first = try insertTrack(path: "/Music/A/01.flac", in: container)
        let second = try insertTrack(path: "/Music/B/01.flac", in: container)
        let firstAlbum = try #require(first.albumRelation)
        let secondAlbum = try #require(second.albumRelation)
        let image = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        secondAlbum.artworkData = image
        try container.mainContext.save()
        let service = LibraryHealthMutationService(modelContainer: container)

        await #expect(throws: LibraryHealthMutationError.self) {
            _ = try await service.applyArtwork([
                LibraryArtworkChange(albumID: firstAlbum.id, expectedArtworkDigest: nil, imageData: image),
                LibraryArtworkChange(albumID: secondAlbum.id, expectedArtworkDigest: nil, imageData: image),
            ])
        }
        let albums = try ModelContext(container).fetch(FetchDescriptor<Album>())
        #expect(albums.first { $0.id == firstAlbum.id }?.artworkData == nil)
    }

    @Test("Missing-record removal and Undo restore catalog, relationships, favorite, and playlist")
    @MainActor
    func missingRecordRemovalAndUndo() async throws {
        let container = try makeContainer()
        let track = try insertTrack(path: "/missing/catalog-only.flac", in: container)
        track.genre = "Rock"
        track.rating = 4
        track.playCount = 17
        let favoriteDate = Date(timeIntervalSince1970: 222)
        container.mainContext.insert(TrackFavorite(trackID: track.id, dateAdded: favoriteDate))
        let playlist = Playlist(name: "Manual")
        let playlistDate = Date(timeIntervalSince1970: 333)
        playlist.dateModified = playlistDate
        playlist.tracks = [track]
        container.mainContext.insert(playlist)
        try container.mainContext.save()
        let service = LibraryHealthMutationService(modelContainer: container)

        let (outcome, receipt) = try await service.removeMissingCatalogRecords([
            LibraryMissingRecordRemoval(trackID: track.id, expectedPath: track.path, sourceRevision: 1),
        ])
        #expect(outcome.affectedTrackCount == 1)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Track>()).contains { $0.id == track.id } == false)

        _ = try await service.undo(receipt)
        let context = ModelContext(container)
        let restored = try #require(context.fetch(FetchDescriptor<Track>()).first { $0.id == track.id })
        #expect(restored.path == "/missing/catalog-only.flac")
        #expect(restored.genre == "Rock")
        #expect(restored.rating == 4)
        #expect(restored.playCount == 17)
        #expect(restored.albumRelation != nil)
        #expect(restored.artistRelation != nil)
        #expect(try context.fetch(FetchDescriptor<TrackFavorite>()).first { $0.trackID == track.id }?.dateAdded == favoriteDate)
        let restoredPlaylist = try #require(context.fetch(FetchDescriptor<Playlist>()).first { $0.id == playlist.id })
        #expect(restoredPlaylist.tracks.contains { $0.id == track.id })
        #expect(restoredPlaylist.dateModified == playlistDate)
    }

    @Test("Missing-record removal refuses a path that returned")
    @MainActor
    func missingRecordRemovalRefusesAvailablePath() async throws {
        let container = try makeContainer()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-health-remove-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("returned.flac")
        let track = try insertTrack(path: url.path, in: container)
        try Data([1]).write(to: url)
        let service = LibraryHealthMutationService(modelContainer: container)

        await #expect(throws: LibraryHealthMutationError.self) {
            _ = try await service.removeMissingCatalogRecords([
                LibraryMissingRecordRemoval(trackID: track.id, expectedPath: track.path, sourceRevision: 1),
            ])
        }
        #expect(try fetchTrack(track.id, from: container).id == track.id)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Track.self, Album.self, Artist.self, Playlist.self, AlbumFavorite.self, TrackFavorite.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    private func insertTrack(path: String, in container: ModelContainer) throws -> Track {
        let track = Track(path: path, title: "Track", artist: "Artist", album: "Unknown Album")
        track.albumArtist = "Artist"
        let album = Album(title: "Unknown Album", artist: "Artist")
        let artist = Artist(name: "Artist")
        track.albumRelation = album
        track.artistRelation = artist
        container.mainContext.insert(album)
        container.mainContext.insert(artist)
        container.mainContext.insert(track)
        try container.mainContext.save()
        return track
    }

    @MainActor
    private func fetchTrack(_ id: UUID, from container: ModelContainer) throws -> Track {
        let context = ModelContext(container)
        return try #require(context.fetch(FetchDescriptor<Track>()).first { $0.id == id })
    }

    private func change(_ id: UUID, from: String, to: String) -> LibraryRemediationChange {
        change(id, field: .album, from: from, to: to)
    }

    private func change(
        _ id: UUID,
        field: LibraryHealthField,
        from: String,
        to: String
    ) -> LibraryRemediationChange {
        LibraryRemediationChange(
            target: LibraryHealthStableTarget(trackID: id, field: field),
            expectedValue: from,
            proposedValue: to
        )
    }

    private func makePlan(changes: [LibraryRemediationChange]) -> LibraryRemediationPlan {
        let grouping = LibraryHealthGrouping(
            stableKey: "test",
            displayName: "Test",
            trackIDs: changes.map(\.target.trackID)
        )
        let issue = LibraryHealthIssue(
            category: .missingAlbumNames,
            grouping: grouping,
            currentValue: "Unknown Album",
            evidence: []
        )
        return LibraryRemediationPlan(
            category: .missingAlbumNames,
            proposals: [LibraryRemediationProposal(
                issue: issue,
                proposedValue: changes.first?.proposedValue,
                confidence: .automaticSafe,
                evidence: [],
                changes: changes
            )]
        )
    }
}
