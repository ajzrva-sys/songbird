import Foundation

public enum TrackMetadataField: String, CaseIterable, Hashable, Sendable {
    case title, artist, album, albumArtist, genre, composer, comment
    case year, trackNumber, trackTotal, discNumber, discTotal, beatsPerMinute
    case rating, favorite, artwork
}

public enum TrackMetadataValue: Equatable, Sendable {
    case text(String)
    case number(Int)
    case flag(Bool)
    case artwork(Data?)

    public var displayText: String {
        switch self {
        case .text(let value): value.isEmpty ? "Empty" : value
        case .number(let value): String(value)
        case .flag(let value): value ? "Yes" : "No"
        case .artwork(let data): data == nil ? "No artwork" : "Artwork (\(data?.count ?? 0) bytes)"
        }
    }
}

public struct TrackMetadataBaseline: Equatable, Sendable {
    public let trackID: UUID
    public let values: [TrackMetadataField: TrackMetadataValue]

    public init(trackID: UUID, values: [TrackMetadataField: TrackMetadataValue]) {
        self.trackID = trackID
        self.values = values
    }
}

/// Artwork has album scope; ordinary metadata retains selected-track scope.
public struct TrackArtworkTarget: Equatable, Sendable {
    public let trackID: UUID
    public let albumID: UUID?
    public let groupID: String
    public let title: String
    public let identity: AlbumPhysicalIdentity
    public let artworkData: Data?
}

public struct TrackArtworkScope: Equatable, Sendable {
    public let targets: [TrackArtworkTarget]
    public let sourceStructureRevision: Int
}

struct TrackMetadataFileWrite: Sendable {
    let trackID: UUID
    let path: String
    let fields: [TrackMetadataField: TrackMetadataValue]
}

struct TrackMetadataMutationResult: Sendable {
    let outcome: TrackMetadataApplyOutcome
    let fileWrites: [TrackMetadataFileWrite]
}

public struct TrackMetadataConflict: Identifiable, Equatable, Sendable {
    public let trackID: UUID
    public let field: TrackMetadataField
    public let opening: TrackMetadataValue
    public let current: TrackMetadataValue
    public let proposed: TrackMetadataValue

    public var id: String { "\(trackID.uuidString)|\(field.rawValue)" }
}

public enum TrackMetadataConflictResolution: String, Equatable, Sendable {
    case useCurrent
    case useProposed
}

public struct TrackMetadataConflictDecision: Equatable, Sendable {
    public let trackID: UUID
    public let field: TrackMetadataField
    public let expectedCurrent: TrackMetadataValue
    public let resolution: TrackMetadataConflictResolution

    public init(
        trackID: UUID,
        field: TrackMetadataField,
        expectedCurrent: TrackMetadataValue,
        resolution: TrackMetadataConflictResolution
    ) {
        self.trackID = trackID
        self.field = field
        self.expectedCurrent = expectedCurrent
        self.resolution = resolution
    }

    public var id: String { "\(trackID.uuidString)|\(field.rawValue)" }
}

public enum TrackMetadataMutationError: Error, LocalizedError, Equatable, Sendable {
    case emptySelection
    case duplicateTarget(UUID)
    case missingTarget(UUID)
    case invalidDecision(String)
    case invalidValue(TrackMetadataField)
    case inconsistentAlbumArtwork(UUID)
    case artworkScopeChanged
    case persistence(String)

    public var errorDescription: String? {
        switch self {
        case .emptySelection: "No tracks were selected."
        case .duplicateTarget(let id): "Track \(id.uuidString) appears more than once in this edit."
        case .missingTarget(let id): "Track \(id.uuidString) is no longer in the library."
        case .invalidDecision: "A metadata conflict changed again. Review the refreshed values before saving."
        case .invalidValue(let field): "The value for \(field.rawValue) is not valid."
        case .inconsistentAlbumArtwork:
            "Tracks sharing one album cannot use different artwork conflict decisions."
        case .artworkScopeChanged:
            "The album's membership changed while editing. Reopen Edit Metadata to review the current album."
        case .persistence(let message): message
        }
    }
}

public struct TrackMetadataChangeSet: Equatable, Sendable {
    public let baselines: [TrackMetadataBaseline]
    public let edits: [TrackMetadataField: TrackMetadataValue]
    public let artworkScope: TrackArtworkScope?

    public init(
        baselines: [TrackMetadataBaseline],
        edits: [TrackMetadataField: TrackMetadataValue],
        artworkScope: TrackArtworkScope? = nil
    ) {
        self.baselines = baselines
        self.edits = edits
        self.artworkScope = artworkScope
    }

    func openingValue(trackID: UUID, field: TrackMetadataField) -> TrackMetadataValue? {
        if let value = baselines.first(where: { $0.trackID == trackID })?.values[field] {
            return value
        }
        guard field == .artwork,
              let target = artworkScope?.targets.first(where: { $0.trackID == trackID }) else {
            return nil
        }
        return .artwork(target.artworkData)
    }

    public func conflicts(
        currentValues: [UUID: [TrackMetadataField: TrackMetadataValue]]
    ) -> [TrackMetadataConflict] {
        let selected = Set(baselines.map(\.trackID))
        let artworkBaselines = (artworkScope?.targets ?? []).filter {
            !selected.contains($0.trackID)
        }.map {
            TrackMetadataBaseline(trackID: $0.trackID, values: [.artwork: .artwork($0.artworkData)])
        }
        return (baselines + artworkBaselines).flatMap { baseline in
            edits.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { field in
                guard let opening = baseline.values[field],
                      let current = currentValues[baseline.trackID]?[field],
                      let proposed = edits[field],
                      current != opening,
                      current != proposed else { return nil }
                return TrackMetadataConflict(
                    trackID: baseline.trackID,
                    field: field,
                    opening: opening,
                    current: current,
                    proposed: proposed
                )
            }
        }
    }
}

public enum TrackMetadataApplyOutcome: Equatable, Sendable {
    case saved(trackCount: Int)
    case conflicts([TrackMetadataConflict])
}
