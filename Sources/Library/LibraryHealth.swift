import CryptoKit
import Foundation

public enum LibraryHealthCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case missingFiles
    case unavailableVolumes
    case duplicateTracks
    case missingArtwork
    case missingGenre
    case missingArtistNames
    case missingAlbumNames
    case missingTrackNumber
    case emptyTitles
    case missingYear
    case inconsistentArtists
    case inconsistentAlbums
    case inconsistentGenres
    case inconsistentAlbumArtists
    case filledComments
    case lowBitrate

    public var displayName: String {
        switch self {
        case .missingFiles: "Missing Files"
        case .unavailableVolumes: "Unavailable Volumes"
        case .duplicateTracks: "Duplicate Tracks"
        case .missingArtwork: "Missing Artwork"
        case .missingGenre: "Missing Genre"
        case .missingArtistNames: "Missing Artist Names"
        case .missingAlbumNames: "Missing Album Names"
        case .missingTrackNumber: "Missing Track Number"
        case .emptyTitles: "Empty Titles"
        case .missingYear: "Missing Year"
        case .inconsistentArtists: "Inconsistent Artists"
        case .inconsistentAlbums: "Inconsistent Albums"
        case .inconsistentGenres: "Inconsistent Genres"
        case .inconsistentAlbumArtists: "Inconsistent Album Artists"
        case .filledComments: "Filled Comments"
        case .lowBitrate: "Low Bitrate"
        }
    }

    public var isFileAvailabilityCheck: Bool {
        self == .missingFiles || self == .unavailableVolumes
    }
}

public enum LibraryHealthField: String, Codable, Hashable, Sendable {
    case artist
    case album
    case albumArtist
    case title
    case genre
    case year
    case trackNumber
    case comment
    case path
    case albumArtwork
    case catalogRecord
}

public enum LibraryRemediationConfidence: String, Codable, Comparable, Sendable {
    case unresolved
    case reviewRequired
    case automaticSafe

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let order: [Self] = [.unresolved, .reviewRequired, .automaticSafe]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

public enum LibraryHealthEvidenceKind: String, Codable, Hashable, Sendable {
    case embeddedMetadata
    case unanimousDirectorySiblings
    case provenMultiDiscCollection
    case folderName
    case filenameInference
    case nameVariants
    case commentClassifier
    case missingArtwork
    case bitrateThreshold
    case conflictingLocalEvidence
    case noLocalEvidence
}

public struct LibraryHealthEvidence: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: LibraryHealthEvidenceKind
    public let summary: String

    public init(kind: LibraryHealthEvidenceKind, summary: String) {
        self.kind = kind
        self.summary = summary
        id = LibraryHealthStableID.make("evidence|\(kind.rawValue)|\(summary)")
    }
}

public struct LibraryHealthStableTarget: Codable, Hashable, Sendable {
    public let trackID: UUID
    public let field: LibraryHealthField

    public init(trackID: UUID, field: LibraryHealthField) {
        self.trackID = trackID
        self.field = field
    }
}

public struct LibraryHealthExpectedValue: Codable, Hashable, Sendable {
    public let target: LibraryHealthStableTarget
    public let value: String

    public init(target: LibraryHealthStableTarget, value: String) {
        self.target = target
        self.value = value
    }
}

public struct LibraryHealthGrouping: Codable, Hashable, Sendable {
    public let stableKey: String
    public let displayName: String
    public let trackIDs: [UUID]

    public init(stableKey: String, displayName: String, trackIDs: [UUID]) {
        self.stableKey = stableKey
        self.displayName = displayName
        self.trackIDs = trackIDs
    }
}

public struct LibraryHealthIssue: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let category: LibraryHealthCategory
    public let grouping: LibraryHealthGrouping
    public let currentValue: String
    public let evidence: [LibraryHealthEvidence]

    public init(
        category: LibraryHealthCategory,
        grouping: LibraryHealthGrouping,
        currentValue: String,
        evidence: [LibraryHealthEvidence]
    ) {
        self.category = category
        self.grouping = grouping
        self.currentValue = currentValue
        self.evidence = evidence
        id = LibraryHealthStableID.make("issue|\(category.rawValue)|\(grouping.stableKey)")
    }
}

public struct LibraryRemediationChange: Codable, Hashable, Sendable {
    public let target: LibraryHealthStableTarget
    public let expectedValue: String
    public let proposedValue: String

    public init(target: LibraryHealthStableTarget, expectedValue: String, proposedValue: String) {
        self.target = target
        self.expectedValue = expectedValue
        self.proposedValue = proposedValue
    }
}

public struct LibraryRemediationProposal: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let issue: LibraryHealthIssue
    public let proposedValue: String?
    public let candidateValues: [String]
    public let confidence: LibraryRemediationConfidence
    public let evidence: [LibraryHealthEvidence]
    public let changes: [LibraryRemediationChange]

    public var affectedTrackCount: Int { issue.grouping.trackIDs.count }
    public var isApplicable: Bool { proposedValue != nil && confidence != .unresolved }
    public var beginsChecked: Bool { confidence == .automaticSafe }

    public init(
        issue: LibraryHealthIssue,
        proposedValue: String?,
        candidateValues: [String] = [],
        confidence: LibraryRemediationConfidence,
        evidence: [LibraryHealthEvidence],
        changes: [LibraryRemediationChange]
    ) {
        self.issue = issue
        self.proposedValue = proposedValue
        self.candidateValues = candidateValues
        self.confidence = confidence
        self.evidence = evidence
        self.changes = changes
        id = LibraryHealthStableID.make("proposal|\(issue.id.uuidString)|\(proposedValue ?? "unresolved")")
    }

    public func choosing(_ value: String) -> LibraryRemediationProposal {
        guard candidateValues.contains(value) else { return self }
        return LibraryRemediationProposal(
            issue: issue,
            proposedValue: value,
            candidateValues: candidateValues,
            confidence: confidence,
            evidence: evidence,
            changes: changes.map {
                LibraryRemediationChange(
                    target: $0.target,
                    expectedValue: $0.expectedValue,
                    proposedValue: value
                )
            }
        )
    }
}

public struct LibraryRemediationPlan: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let category: LibraryHealthCategory
    public let createdAt: Date
    public let proposals: [LibraryRemediationProposal]

    public init(
        category: LibraryHealthCategory,
        createdAt: Date = Date(),
        proposals: [LibraryRemediationProposal]
    ) {
        self.category = category
        self.createdAt = createdAt
        self.proposals = proposals
        id = LibraryHealthStableID.make(
            "plan|\(category.rawValue)|" + proposals.map(\.id.uuidString).joined(separator: "|")
        )
    }

    public func selecting(_ proposalIDs: Set<UUID>) -> LibraryRemediationPlan {
        LibraryRemediationPlan(
            category: category,
            createdAt: createdAt,
            proposals: proposals.filter { proposalIDs.contains($0.id) && $0.isApplicable }
        )
    }

    public var changes: [LibraryRemediationChange] { proposals.flatMap(\.changes) }
}

/// Value-only input for proposal derivation. Embedded values are populated only by an explicit
/// local-evidence scan; constructing or sorting this value never touches the filesystem.
public struct LibraryHealthTrackInput: Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let path: String
    public let album: String
    public let artist: String
    public let albumArtist: String
    public let genre: String
    public let comment: String
    public let year: Int
    public let trackNumber: Int
    public let bitrate: Int
    public let fileKind: String
    public let albumID: UUID?
    public let hasArtwork: Bool
    public let embeddedAlbum: String?

    public init(
        id: UUID,
        title: String,
        path: String,
        album: String,
        artist: String = "Unknown Artist",
        albumArtist: String = "Unknown Artist",
        genre: String = "",
        comment: String = "",
        year: Int = 0,
        trackNumber: Int = 0,
        bitrate: Int = 0,
        fileKind: String = "",
        albumID: UUID? = nil,
        hasArtwork: Bool = false,
        embeddedAlbum: String? = nil
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.album = album
        self.artist = artist
        self.albumArtist = albumArtist
        self.genre = genre
        self.comment = comment
        self.year = year
        self.trackNumber = trackNumber
        self.bitrate = bitrate
        self.fileKind = fileKind
        self.albumID = albumID
        self.hasArtwork = hasArtwork
        self.embeddedAlbum = embeddedAlbum
    }
}

public actor LibraryHealthProposalService {
    public init() {}

    public func plan(
        category: LibraryHealthCategory,
        tracks: [LibraryHealthTrackInput]
    ) async throws -> LibraryRemediationPlan {
        try Task.checkCancellation()
        switch category {
        case .missingAlbumNames:
            return LibraryRemediationPlan(
                category: category,
                proposals: try missingAlbumProposals(tracks)
            )
        case .missingArtistNames:
            return LibraryRemediationPlan(
                category: category,
                proposals: try missingStringProposals(
                    category: category,
                    field: .artist,
                    tracks: tracks,
                    value: \.artist,
                    isMeaningful: Self.isMeaningfulArtist
                )
            )
        case .missingGenre:
            return LibraryRemediationPlan(
                category: category,
                proposals: try missingStringProposals(
                    category: category,
                    field: .genre,
                    tracks: tracks,
                    value: \.genre,
                    isMeaningful: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                )
            )
        case .emptyTitles:
            return LibraryRemediationPlan(
                category: category,
                proposals: try missingTitleProposals(tracks)
            )
        case .missingTrackNumber:
            return LibraryRemediationPlan(
                category: category,
                proposals: try missingTrackNumberProposals(tracks)
            )
        case .missingYear:
            return LibraryRemediationPlan(
                category: category,
                proposals: try missingYearProposals(tracks)
            )
        case .missingArtwork:
            return LibraryRemediationPlan(
                category: category,
                proposals: try missingArtworkProposals(tracks)
            )
        case .inconsistentArtists:
            return LibraryRemediationPlan(
                category: category,
                proposals: try inconsistentNameProposals(
                    category: category,
                    field: .artist,
                    tracks: tracks,
                    value: \.artist
                )
            )
        case .inconsistentAlbums:
            return LibraryRemediationPlan(
                category: category,
                proposals: try inconsistentNameProposals(
                    category: category,
                    field: .album,
                    tracks: tracks,
                    value: \.album
                )
            )
        case .inconsistentGenres:
            return LibraryRemediationPlan(
                category: category,
                proposals: try inconsistentNameProposals(
                    category: category,
                    field: .genre,
                    tracks: tracks,
                    value: \.genre
                )
            )
        case .inconsistentAlbumArtists:
            return LibraryRemediationPlan(
                category: category,
                proposals: try inconsistentNameProposals(
                    category: category,
                    field: .albumArtist,
                    tracks: tracks,
                    value: \.albumArtist
                )
            )
        case .filledComments:
            return LibraryRemediationPlan(
                category: category,
                proposals: try filledCommentProposals(tracks)
            )
        case .lowBitrate:
            return LibraryRemediationPlan(
                category: category,
                proposals: try lowBitrateProposals(tracks)
            )
        case .missingFiles, .unavailableVolumes, .duplicateTracks:
            return LibraryRemediationPlan(category: category, proposals: [])
        }
    }

    private func missingStringProposals(
        category: LibraryHealthCategory,
        field: LibraryHealthField,
        tracks: [LibraryHealthTrackInput],
        value: KeyPath<LibraryHealthTrackInput, String>,
        isMeaningful: (String) -> Bool
    ) throws -> [LibraryRemediationProposal] {
        let sorted = sortedTracks(tracks)
        return try sorted.filter { !isMeaningful($0[keyPath: value]) }.map { track in
            try Task.checkCancellation()
            let directory = (track.path as NSString).deletingLastPathComponent
            let siblingValues = sorted.filter {
                $0.id != track.id
                    && ($0.path as NSString).deletingLastPathComponent == directory
                    && isMeaningful($0[keyPath: value])
            }.map { $0[keyPath: value] }
            let resolution = canonicalUnanimous(siblingValues)
            let proposed = resolution.value
            let evidence: [LibraryHealthEvidence]
            if let proposed {
                evidence = [LibraryHealthEvidence(
                    kind: .unanimousDirectorySiblings,
                    summary: "All populated sibling tracks in this directory use “\(proposed)”."
                )]
            } else if resolution.conflicts {
                evidence = [LibraryHealthEvidence(
                    kind: .conflictingLocalEvidence,
                    summary: "Populated sibling tracks disagree, so no automatic change is available."
                )]
            } else {
                evidence = [LibraryHealthEvidence(
                    kind: .noLocalEvidence,
                    summary: "No deterministic local evidence was found."
                )]
            }
            return singleTrackProposal(
                category: category,
                field: field,
                track: track,
                currentValue: track[keyPath: value],
                proposedValue: proposed,
                confidence: proposed == nil ? .unresolved : .automaticSafe,
                evidence: evidence
            )
        }
    }

    private func missingTitleProposals(
        _ tracks: [LibraryHealthTrackInput]
    ) throws -> [LibraryRemediationProposal] {
        try sortedTracks(tracks).filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.map { track in
            try Task.checkCancellation()
            let filename = ((track.path as NSString).lastPathComponent as NSString)
                .deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            let proposed = filename.isEmpty ? nil : filename
            return singleTrackProposal(
                category: .emptyTitles,
                field: .title,
                track: track,
                currentValue: track.title,
                proposedValue: proposed,
                confidence: proposed == nil ? .unresolved : .reviewRequired,
                evidence: [LibraryHealthEvidence(
                    kind: proposed == nil ? .noLocalEvidence : .filenameInference,
                    summary: proposed == nil
                        ? "The filename does not provide a usable title."
                        : "The filename suggests “\(proposed!)”; review is required."
                )]
            )
        }
    }

    private func missingTrackNumberProposals(
        _ tracks: [LibraryHealthTrackInput]
    ) throws -> [LibraryRemediationProposal] {
        try sortedTracks(tracks).filter { $0.trackNumber <= 0 }.map { track in
            try Task.checkCancellation()
            let stem = ((track.path as NSString).lastPathComponent as NSString)
                .deletingPathExtension
            let proposed = Self.leadingTrackNumber(in: stem).map(String.init)
            return singleTrackProposal(
                category: .missingTrackNumber,
                field: .trackNumber,
                track: track,
                currentValue: String(track.trackNumber),
                proposedValue: proposed,
                confidence: proposed == nil ? .unresolved : .reviewRequired,
                evidence: [LibraryHealthEvidence(
                    kind: proposed == nil ? .noLocalEvidence : .filenameInference,
                    summary: proposed == nil
                        ? "The filename does not begin with a track number."
                        : "The filename suggests track \(proposed!); review is required."
                )]
            )
        }
    }

    private func missingYearProposals(
        _ tracks: [LibraryHealthTrackInput]
    ) throws -> [LibraryRemediationProposal] {
        let sorted = sortedTracks(tracks)
        return try sorted.filter { $0.year <= 0 }.map { track in
            try Task.checkCancellation()
            let directory = (track.path as NSString).deletingLastPathComponent
            let years = sorted.filter {
                $0.id != track.id
                    && ($0.path as NSString).deletingLastPathComponent == directory
                    && $0.year > 0
            }.map { String($0.year) }
            let resolution = canonicalUnanimous(years)
            let proposed = resolution.value
            return singleTrackProposal(
                category: .missingYear,
                field: .year,
                track: track,
                currentValue: String(track.year),
                proposedValue: proposed,
                confidence: proposed == nil ? .unresolved : .automaticSafe,
                evidence: [LibraryHealthEvidence(
                    kind: proposed == nil
                        ? (resolution.conflicts ? .conflictingLocalEvidence : .noLocalEvidence)
                        : .unanimousDirectorySiblings,
                    summary: proposed.map {
                        "All populated sibling tracks in this directory use \($0)."
                    } ?? (resolution.conflicts
                        ? "Sibling tracks disagree about the year."
                        : "No deterministic local year evidence was found.")
                )]
            )
        }
    }

    private func missingArtworkProposals(
        _ tracks: [LibraryHealthTrackInput]
    ) throws -> [LibraryRemediationProposal] {
        let missing = sortedTracks(tracks).filter { !$0.hasArtwork }
        let groups = Dictionary(grouping: missing) { track in
            track.albumID.map { "album|\($0.uuidString)" }
                ?? "directory|\((track.path as NSString).deletingLastPathComponent)"
        }
        return try groups.keys.sorted().map { key in
            try Task.checkCancellation()
            let members = groups[key, default: []]
            let name = members.first.map {
                Self.isMeaningfulAlbum($0.album)
                    ? $0.album
                    : ($0.path as NSString).deletingLastPathComponent.components(separatedBy: "/").last ?? "Unknown Album"
            } ?? "Unknown Album"
            let grouping = LibraryHealthGrouping(
                stableKey: key,
                displayName: name,
                trackIDs: members.map(\.id).sorted { $0.uuidString < $1.uuidString }
            )
            let evidence = [LibraryHealthEvidence(
                kind: .missingArtwork,
                summary: "No catalog artwork is available. Choose local artwork or explicitly open Discogs review."
            )]
            return LibraryRemediationProposal(
                issue: LibraryHealthIssue(
                    category: .missingArtwork,
                    grouping: grouping,
                    currentValue: "No artwork",
                    evidence: evidence
                ),
                proposedValue: nil,
                confidence: .unresolved,
                evidence: evidence,
                changes: []
            )
        }
    }

    private func inconsistentNameProposals(
        category: LibraryHealthCategory,
        field: LibraryHealthField,
        tracks: [LibraryHealthTrackInput],
        value: KeyPath<LibraryHealthTrackInput, String>
    ) throws -> [LibraryRemediationProposal] {
        let populated = sortedTracks(tracks).filter {
            !$0[keyPath: value].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let groups = Dictionary(grouping: populated) {
            Self.normalizedName($0[keyPath: value])
        }
        return try groups.keys.sorted().compactMap { key in
            try Task.checkCancellation()
            let members = groups[key, default: []]
            let variants = Dictionary(grouping: members, by: { $0[keyPath: value] })
            guard variants.count > 1 else { return nil }
            let candidates = variants.keys.sorted { lhs, rhs in
                let leftCount = variants[lhs]?.count ?? 0
                let rightCount = variants[rhs]?.count ?? 0
                if leftCount != rightCount { return leftCount > rightCount }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            guard let proposed = candidates.first else { return nil }
            let grouping = LibraryHealthGrouping(
                stableKey: "\(field.rawValue)|\(key)",
                displayName: proposed,
                trackIDs: members.map(\.id).sorted { $0.uuidString < $1.uuidString }
            )
            let evidence = [LibraryHealthEvidence(
                kind: .nameVariants,
                summary: "Variants differ only by case, diacritics, or collapsed whitespace. Choose a canonical value."
            )]
            return LibraryRemediationProposal(
                issue: LibraryHealthIssue(
                    category: category,
                    grouping: grouping,
                    currentValue: candidates.joined(separator: " · "),
                    evidence: evidence
                ),
                proposedValue: proposed,
                candidateValues: candidates,
                confidence: .reviewRequired,
                evidence: evidence,
                changes: members.map {
                    LibraryRemediationChange(
                        target: LibraryHealthStableTarget(trackID: $0.id, field: field),
                        expectedValue: $0[keyPath: value],
                        proposedValue: proposed
                    )
                }
            )
        }
    }

    private func filledCommentProposals(
        _ tracks: [LibraryHealthTrackInput]
    ) throws -> [LibraryRemediationProposal] {
        try sortedTracks(tracks).compactMap { track in
            try Task.checkCancellation()
            guard let reason = LibraryHealthCommentPolicy.junkReason(for: track.comment) else {
                return nil
            }
            return singleTrackProposal(
                category: .filledComments,
                field: .comment,
                track: track,
                currentValue: track.comment,
                proposedValue: "",
                confidence: .reviewRequired,
                evidence: [LibraryHealthEvidence(kind: .commentClassifier, summary: reason)]
            )
        }
    }

    private func lowBitrateProposals(
        _ tracks: [LibraryHealthTrackInput]
    ) throws -> [LibraryRemediationProposal] {
        let losslessExtensions: Set<String> = ["FLAC", "WAV", "WAVE", "AIFF", "AIF", "APE"]
        return try sortedTracks(tracks).filter {
            $0.bitrate > 0 && $0.bitrate < 128
                && !losslessExtensions.contains($0.fileKind.uppercased())
        }.map { track in
            try Task.checkCancellation()
            let evidence = [LibraryHealthEvidence(
                kind: .bitrateThreshold,
                summary: "Catalog bitrate is \(track.bitrate) kbps; this check is informational only."
            )]
            return singleTrackProposal(
                category: .lowBitrate,
                field: .catalogRecord,
                track: track,
                currentValue: "\(track.bitrate) kbps",
                proposedValue: nil,
                confidence: .unresolved,
                evidence: evidence
            )
        }
    }

    private func singleTrackProposal(
        category: LibraryHealthCategory,
        field: LibraryHealthField,
        track: LibraryHealthTrackInput,
        currentValue: String,
        proposedValue: String?,
        confidence: LibraryRemediationConfidence,
        evidence: [LibraryHealthEvidence]
    ) -> LibraryRemediationProposal {
        let grouping = LibraryHealthGrouping(
            stableKey: "track|\(track.id.uuidString)|\(field.rawValue)",
            displayName: track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (track.path as NSString).lastPathComponent
                : track.title,
            trackIDs: [track.id]
        )
        let issue = LibraryHealthIssue(
            category: category,
            grouping: grouping,
            currentValue: currentValue,
            evidence: evidence
        )
        return LibraryRemediationProposal(
            issue: issue,
            proposedValue: proposedValue,
            confidence: confidence,
            evidence: evidence,
            changes: proposedValue.map {
                [LibraryRemediationChange(
                    target: LibraryHealthStableTarget(trackID: track.id, field: field),
                    expectedValue: currentValue,
                    proposedValue: $0
                )]
            } ?? []
        )
    }

    private func sortedTracks(_ tracks: [LibraryHealthTrackInput]) -> [LibraryHealthTrackInput] {
        tracks.sorted { lhs, rhs in
            lhs.path != rhs.path ? lhs.path < rhs.path : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func canonicalUnanimous(_ values: [String]) -> (value: String?, conflicts: Bool) {
        let meaningful = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !meaningful.isEmpty else { return (nil, false) }
        let groups = Dictionary(grouping: meaningful, by: Self.normalizedName)
        guard groups.count == 1 else { return (nil, true) }
        return (groups.values.first?.sorted().first, false)
    }

    private static func leadingTrackNumber(in filename: String) -> Int? {
        let digits = filename.prefix { $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits), value > 0 else { return nil }
        let remainder = filename.dropFirst(digits.count)
        guard remainder.isEmpty || remainder.first.map({ $0 == " " || $0 == "." || $0 == "-" || $0 == "_" }) == true else {
            return nil
        }
        return value
    }

    private func missingAlbumProposals(
        _ tracks: [LibraryHealthTrackInput]
    ) throws -> [LibraryRemediationProposal] {
        let sorted = tracks.sorted { lhs, rhs in
            lhs.path != rhs.path ? lhs.path < rhs.path : lhs.id.uuidString < rhs.id.uuidString
        }
        let multiDiscProofs = provenMultiDiscCollections(sorted)
        let missing = sorted.filter { !Self.isMeaningfulAlbum($0.album) }
        let grouped = Dictionary(grouping: missing) { track -> String in
            if let collection = MultiDiscAlbumTitle.collectionFolder(inPath: track.path),
               multiDiscProofs[collection.path] != nil {
                return "collection|\(collection.path)"
            }
            return "directory|\((track.path as NSString).deletingLastPathComponent)"
        }

        return try grouped.keys.sorted().map { key in
            try Task.checkCancellation()
            let members = grouped[key, default: []]
            let ids = members.map(\.id).sorted { $0.uuidString < $1.uuidString }
            let resolution = resolveAlbum(
                key: key,
                members: members,
                allTracks: sorted,
                multiDiscProofs: multiDiscProofs
            )
            let grouping = LibraryHealthGrouping(
                stableKey: key,
                displayName: resolution.groupName,
                trackIDs: ids
            )
            let issue = LibraryHealthIssue(
                category: .missingAlbumNames,
                grouping: grouping,
                currentValue: "Unknown Album",
                evidence: resolution.evidence
            )
            let changes = resolution.value.map { proposed in
                members.map {
                    LibraryRemediationChange(
                        target: LibraryHealthStableTarget(trackID: $0.id, field: .album),
                        expectedValue: $0.album,
                        proposedValue: proposed
                    )
                }
            } ?? []
            return LibraryRemediationProposal(
                issue: issue,
                proposedValue: resolution.value,
                confidence: resolution.confidence,
                evidence: resolution.evidence,
                changes: changes
            )
        }
    }

    private struct Resolution {
        let groupName: String
        let value: String?
        let confidence: LibraryRemediationConfidence
        let evidence: [LibraryHealthEvidence]
    }

    private func resolveAlbum(
        key: String,
        members: [LibraryHealthTrackInput],
        allTracks: [LibraryHealthTrackInput],
        multiDiscProofs: [String: (name: String, discNumbers: Set<Int>)]
    ) -> Resolution {
        let directory = (members[0].path as NSString).deletingLastPathComponent
        let folderName = (directory as NSString).lastPathComponent
        let embedded = unanimousMeaningful(members.compactMap(\.embeddedAlbum))
        if case .value(let value) = embedded {
            return Resolution(
                groupName: folderName,
                value: value,
                confidence: .automaticSafe,
                evidence: [LibraryHealthEvidence(
                    kind: .embeddedMetadata,
                    summary: "Embedded album metadata unanimously names “\(value)”."
                )]
            )
        }
        if case .conflict = embedded {
            return Resolution(
                groupName: folderName,
                value: nil,
                confidence: .unresolved,
                evidence: [LibraryHealthEvidence(
                    kind: .conflictingLocalEvidence,
                    summary: "Embedded album metadata conflicts within this group."
                )]
            )
        }

        if key.hasPrefix("collection|"),
           let collection = MultiDiscAlbumTitle.collectionFolder(inPath: members[0].path),
           let proof = multiDiscProofs[collection.path] {
            return Resolution(
                groupName: proof.name,
                value: proof.name,
                confidence: .automaticSafe,
                evidence: [LibraryHealthEvidence(
                    kind: .provenMultiDiscCollection,
                    summary: "Collection parent proven by \(proof.discNumbers.count) numbered disc folders."
                )]
            )
        }

        let siblings = allTracks.filter {
            ($0.path as NSString).deletingLastPathComponent == directory
                && Self.isMeaningfulAlbum($0.album)
        }.map(\.album)
        switch unanimousMeaningful(siblings) {
        case .value(let value):
            return Resolution(
                groupName: folderName,
                value: value,
                confidence: .automaticSafe,
                evidence: [LibraryHealthEvidence(
                    kind: .unanimousDirectorySiblings,
                    summary: "All tagged sibling tracks in this directory name “\(value)”."
                )]
            )
        case .conflict:
            return Resolution(
                groupName: folderName,
                value: nil,
                confidence: .unresolved,
                evidence: [LibraryHealthEvidence(
                    kind: .conflictingLocalEvidence,
                    summary: "Sibling tracks disagree about the album name."
                )]
            )
        case .none:
            break
        }

        let trimmedFolder = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isMeaningfulFolder(trimmedFolder) {
            return Resolution(
                groupName: trimmedFolder,
                value: trimmedFolder,
                confidence: .reviewRequired,
                evidence: [LibraryHealthEvidence(
                    kind: .folderName,
                    summary: "The containing folder is named “\(trimmedFolder)”; review is required."
                )]
            )
        }
        return Resolution(
            groupName: members.first?.title ?? "Unknown Album",
            value: nil,
            confidence: .unresolved,
            evidence: [LibraryHealthEvidence(
                kind: .noLocalEvidence,
                summary: "No deterministic local album evidence was found."
            )]
        )
    }

    private enum UnanimousValue {
        case none
        case value(String)
        case conflict
    }

    private func unanimousMeaningful(_ values: [String]) -> UnanimousValue {
        let meaningful = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(Self.isMeaningfulAlbum)
        guard !meaningful.isEmpty else { return .none }
        let groups = Dictionary(grouping: meaningful, by: Self.normalized)
        guard groups.count == 1, let value = groups.values.first?.sorted().first else {
            return .conflict
        }
        return .value(value)
    }

    private func provenMultiDiscCollections(
        _ tracks: [LibraryHealthTrackInput]
    ) -> [String: (name: String, discNumbers: Set<Int>)] {
        var candidates: [String: (name: String, discNumbers: Set<Int>)] = [:]
        for track in tracks {
            guard let collection = MultiDiscAlbumTitle.collectionFolder(inPath: track.path) else {
                continue
            }
            var current = candidates[collection.path]
                ?? (name: collection.name, discNumbers: Set<Int>())
            current.discNumbers.insert(collection.discNumber)
            candidates[collection.path] = current
        }
        return candidates.filter { $0.value.discNumbers.count >= 2 }
    }

    private static func isMeaningfulAlbum(_ value: String) -> Bool {
        let key = normalized(value)
        return !key.isEmpty && key != normalized("Unknown Album")
    }

    private static func isMeaningfulArtist(_ value: String) -> Bool {
        let key = normalized(value)
        return !key.isEmpty && key != normalized("Unknown Artist")
    }

    private static func isMeaningfulFolder(_ value: String) -> Bool {
        guard isMeaningfulAlbum(value) else { return false }
        return !["music", "downloads", "audio", "media", "library", "itunes", "amarra",
                  "home", "desktop", "documents"].contains(normalized(value))
            && MultiDiscAlbumTitle.collectionFolder(inPath: "/placeholder/\(value)/track.flac") == nil
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func normalizedName(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

enum LibraryHealthCommentPolicy {
    static func junkReason(for value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased()
        let prefixes = [
            "encoded by ", "ripped by ", "tagged by ", "generated by ",
            "created by exact audio copy", "created with exact audio copy",
        ]
        if let prefix = prefixes.first(where: { normalized.hasPrefix($0) }) {
            return "The comment begins with the tool-generated marker “\(prefix.trimmingCharacters(in: .whitespaces))”."
        }
        if normalized.contains("downloaded from ") || normalized.contains("visit http") {
            return "The comment contains an explicit download or promotional marker."
        }
        return nil
    }
}

enum LibraryHealthStableID {
    static func make(_ value: String) -> UUID {
        let digest = SHA256.hash(data: Data(value.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
