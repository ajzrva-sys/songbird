import Foundation
import Testing
@testable import SongbirdLib

@Suite("Library Health proposals")
struct LibraryHealthProposalTests {
    private let service = LibraryHealthProposalService()

    @Test("Unanimous sibling evidence is safe and grouped by directory")
    func siblingEvidence() async throws {
        let missingA = UUID()
        let missingB = UUID()
        let plan = try await service.plan(category: .missingAlbumNames, tracks: [
            input(missingA, path: "/Music/Northern Lights/01.flac"),
            input(missingB, path: "/Music/Northern Lights/02.flac"),
            input(UUID(), path: "/Music/Northern Lights/03.flac", album: "Northern Lights"),
        ])

        let proposal = try #require(plan.proposals.first)
        #expect(plan.proposals.count == 1)
        #expect(proposal.proposedValue == "Northern Lights")
        #expect(proposal.confidence == .automaticSafe)
        #expect(proposal.beginsChecked)
        #expect(Set(proposal.changes.map(\.target.trackID)) == [missingA, missingB])
        #expect(proposal.evidence.map(\.kind) == [.unanimousDirectorySiblings])
    }

    @Test("A proven multi-disc collection never proposes the disc folder")
    func multiDiscCollection() async throws {
        let plan = try await service.plan(category: .missingAlbumNames, tracks: [
            input(UUID(), path: "/Music/Box Set/CD 1/01.flac"),
            input(UUID(), path: "/Music/Box Set/CD 2/01.flac"),
        ])

        let proposal = try #require(plan.proposals.first)
        #expect(plan.proposals.count == 1)
        #expect(proposal.proposedValue == "Box Set")
        #expect(proposal.confidence == .automaticSafe)
        #expect(proposal.affectedTrackCount == 2)
        #expect(proposal.evidence.map(\.kind) == [.provenMultiDiscCollection])
    }

    @Test("An ordinary folder is review-required, not automatic")
    func ordinaryFolderNeedsReview() async throws {
        let plan = try await service.plan(category: .missingAlbumNames, tracks: [
            input(UUID(), path: "/Music/Possible Album/01.flac"),
        ])

        let proposal = try #require(plan.proposals.first)
        #expect(proposal.proposedValue == "Possible Album")
        #expect(proposal.confidence == .reviewRequired)
        #expect(!proposal.beginsChecked)
    }

    @Test("Conflicting sibling values remain visible and cannot be applied")
    func conflictIsUnresolved() async throws {
        let plan = try await service.plan(category: .missingAlbumNames, tracks: [
            input(UUID(), path: "/Music/Conflict/01.flac"),
            input(UUID(), path: "/Music/Conflict/02.flac", album: "First") ,
            input(UUID(), path: "/Music/Conflict/03.flac", album: "Second"),
        ])

        let proposal = try #require(plan.proposals.first)
        #expect(proposal.confidence == .unresolved)
        #expect(proposal.proposedValue == nil)
        #expect(!proposal.isApplicable)
        #expect(proposal.changes.isEmpty)
    }

    @Test("Proposal identity and ordering are deterministic")
    func deterministicIdentity() async throws {
        let idA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let idB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let tracks = [
            input(idB, path: "/Music/B/01.flac"),
            input(idA, path: "/Music/A/01.flac"),
        ]
        let first = try await service.plan(category: .missingAlbumNames, tracks: tracks)
        let second = try await service.plan(category: .missingAlbumNames, tracks: tracks.reversed())

        #expect(first.id == second.id)
        #expect(first.proposals.map(\.id) == second.proposals.map(\.id))
        #expect(first.proposals.map(\.issue.grouping.stableKey)
            == first.proposals.map(\.issue.grouping.stableKey).sorted())
    }

    @Test("Consistency groups spelling variants but keeps punctuation distinct")
    func conservativeConsistencyGrouping() async throws {
        let plan = try await service.plan(category: .inconsistentArtists, tracks: [
            detailedInput(path: "/Music/A.flac", artist: "Beyoncé"),
            detailedInput(path: "/Music/B.flac", artist: "  BEYONCE  "),
            detailedInput(path: "/Music/C.flac", artist: "Beyonce!"),
        ])

        let proposal = try #require(plan.proposals.first)
        #expect(plan.proposals.count == 1)
        #expect(Set(proposal.candidateValues) == ["Beyoncé", "  BEYONCE  "])
        #expect(proposal.confidence == .reviewRequired)
        #expect(proposal.changes.count == 2)
    }

    @Test("Comment cleanup does not classify generic text or domains as junk")
    func conservativeCommentPolicy() async throws {
        let plan = try await service.plan(category: .filledComments, tracks: [
            detailedInput(path: "/Music/A.flac", comment: "42"),
            detailedInput(path: "/Music/B.flac", comment: "example.com"),
            detailedInput(path: "/Music/C.flac", comment: "Great live take"),
            detailedInput(path: "/Music/D.flac", comment: "Encoded by Tool 1.0"),
        ])

        #expect(plan.proposals.count == 1)
        #expect(plan.proposals.first?.issue.grouping.displayName == "D.flac")
        #expect(plan.proposals.first?.confidence == .reviewRequired)
    }

    @Test("Low bitrate is informational and excludes known lossless files")
    func lowBitratePolicy() async throws {
        let plan = try await service.plan(category: .lowBitrate, tracks: [
            detailedInput(path: "/Music/A.mp3", bitrate: 96, fileKind: "MP3"),
            detailedInput(path: "/Music/B.flac", bitrate: 96, fileKind: "FLAC"),
        ])

        #expect(plan.proposals.count == 1)
        #expect(plan.proposals.first?.confidence == .unresolved)
        #expect(plan.proposals.first?.changes.isEmpty == true)
    }

    private func detailedInput(
        path: String,
        artist: String = "Artist",
        comment: String = "",
        bitrate: Int = 0,
        fileKind: String = "FLAC"
    ) -> LibraryHealthTrackInput {
        LibraryHealthTrackInput(
            id: UUID(),
            title: (path as NSString).lastPathComponent,
            path: path,
            album: "Album",
            artist: artist,
            albumArtist: artist,
            comment: comment,
            bitrate: bitrate,
            fileKind: fileKind
        )
    }

    private func input(
        _ id: UUID,
        path: String,
        album: String = "Unknown Album",
        embeddedAlbum: String? = nil
    ) -> LibraryHealthTrackInput {
        LibraryHealthTrackInput(
            id: id,
            title: (path as NSString).lastPathComponent,
            path: path,
            album: album,
            embeddedAlbum: embeddedAlbum
        )
    }
}
