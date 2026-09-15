import Foundation
import SongbirdLib

private struct Output: Codable {
    let mode: String
    let before: LibraryRemediationPreview
    let after: LibraryRemediationPreview
    let local: LocalLibraryRemediationReport?
    let discogs: DiscogsLibraryRemediationReport?
    let apple: AppleCatalogLibraryRemediationReport?
    let audit: [DiscogsRemediationAuditItem]?
    let identifierAudit: [IdentifierMetadataRepairProposal]?
    let identifierRepair: IdentifierMetadataRepairReport?
    let backupPath: String?
}

@main
@MainActor
struct SongbirdLibraryRemediatorCommand {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let mode = arguments.first,
              ["preview", "local", "local-inference", "bpm", "apple", "apple-artwork", "apple-track-numbers", "discogs-audit", "discogs-cache", "discogs", "discogs-fuzzy", "discogs-refresh", "discogs-track-numbers", "identifier-audit", "identifier-repair"].contains(mode) else {
            throw CommandError.usage
        }
        let reportPath: String? = {
            guard let index = arguments.firstIndex(of: "--report"),
                  arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }()
        let country: String = {
            guard let index = arguments.firstIndex(of: "--country"),
                  arguments.indices.contains(index + 1) else { return "US" }
            return arguments[index + 1].uppercased()
        }()
        let expectedAlbums = try integerArgument("--expected-albums", in: arguments)
        let expectedFields = try integerArgument("--expected-fields", in: arguments)
        if mode == "identifier-repair",
           (expectedAlbums == nil || expectedFields == nil) {
            throw CommandError.missingIdentifierExpectations
        }

        let backupPath: String?
        if mode == "identifier-repair" {
            backupPath = try MediaLibraryStore.backupStore(
                at: MediaLibraryStore.libraryStoreURL
            ).path
        } else {
            backupPath = nil
        }

        let library = MediaLibrary.shared
        if let startupError = library.startupError {
            throw CommandError.libraryUnavailable(startupError)
        }
        let context = library.context
        let before = try RealLibraryRemediator.preview(in: context)
        let local: LocalLibraryRemediationReport?
        let discogs: DiscogsLibraryRemediationReport?
        let apple: AppleCatalogLibraryRemediationReport?
        let audit: [DiscogsRemediationAuditItem]?
        switch mode {
        case "local":
            local = try await RealLibraryRemediator.applyLocalEvidence(in: context)
            discogs = nil
            apple = nil
            audit = nil
        case "local-inference":
            local = try RealLibraryRemediator.applyLocalInference(in: context)
            discogs = nil
            apple = nil
            audit = nil
        case "bpm":
            local = try await RealLibraryRemediator.applyMissingBPM(in: context)
            discogs = nil
            apple = nil
            audit = nil
        case "apple":
            local = nil
            discogs = nil
            apple = try await RealLibraryRemediator.applyAppleCatalogEvidence(
                in: context,
                country: country
            )
            audit = nil
        case "apple-artwork":
            local = nil
            discogs = nil
            apple = try await RealLibraryRemediator.applyAppleCatalogEvidence(
                in: context,
                country: country,
                artworkOnly: true
            )
            audit = nil
        case "apple-track-numbers":
            local = nil
            discogs = nil
            apple = try await RealLibraryRemediator.applyAppleCatalogTrackNumbers(
                in: context,
                country: country
            )
            audit = nil
        case "discogs-audit":
            local = nil
            discogs = nil
            apple = nil
            audit = try await RealLibraryRemediator.auditDiscogsEvidence(in: context)
        case "discogs-cache":
            local = nil
            discogs = try await RealLibraryRemediator.applyDiscogsEvidence(
                in: context,
                allowNetwork: false
            )
            apple = nil
            audit = nil
        case "discogs":
            local = nil
            discogs = try await RealLibraryRemediator.applyDiscogsEvidence(in: context)
            apple = nil
            audit = nil
        case "discogs-fuzzy":
            local = nil
            discogs = try await RealLibraryRemediator.applyDiscogsEvidence(
                in: context,
                allowFuzzyMatches: true
            )
            apple = nil
            audit = nil
        case "discogs-track-numbers":
            local = nil
            discogs = try await RealLibraryRemediator.applyDiscogsTrackNumbers(in: context)
            apple = nil
            audit = nil
        case "discogs-refresh":
            local = nil
            discogs = try await RealLibraryRemediator.applyDiscogsEvidence(
                in: context,
                allowFuzzyMatches: true,
                refreshEmptyResults: true
            )
            apple = nil
            audit = nil
        default:
            local = nil
            discogs = nil
            apple = nil
            audit = nil
        }
        let identifierAudit: [IdentifierMetadataRepairProposal]?
        let identifierRepair: IdentifierMetadataRepairReport?
        if mode == "identifier-audit" || mode == "identifier-repair" {
            let proposals = try RealLibraryRemediator.previewIdentifierMetadataRepairs(
                in: context
            )
            let fieldCount = proposals.reduce(0) { $0 + $1.totalFields }
            if let expectedAlbums, proposals.count != expectedAlbums {
                throw CommandError.unexpectedIdentifierScope(
                    expectedAlbums: expectedAlbums,
                    actualAlbums: proposals.count,
                    expectedFields: expectedFields,
                    actualFields: fieldCount
                )
            }
            if let expectedFields, fieldCount != expectedFields {
                throw CommandError.unexpectedIdentifierScope(
                    expectedAlbums: expectedAlbums,
                    actualAlbums: proposals.count,
                    expectedFields: expectedFields,
                    actualFields: fieldCount
                )
            }
            identifierAudit = proposals
            if mode == "identifier-repair" {
                identifierRepair = try RealLibraryRemediator.applyIdentifierMetadataRepairs(
                    in: context,
                    expectedProposals: proposals
                )
            } else {
                identifierRepair = nil
            }
        } else {
            identifierAudit = nil
            identifierRepair = nil
        }
        let after = try RealLibraryRemediator.preview(in: context)
        // Validate new audit output at generation time. Saved reports remain historical
        // records; lookup expiry must not rewrite or remove them (G-IMPORT).
        let auditTime = DiscogsClock.sample()
        let currentAudit = audit?.compactMap { $0.revalidated(at: auditTime) }
        let output = Output(
            mode: mode,
            before: before,
            after: after,
            local: local,
            discogs: discogs,
            apple: apple,
            audit: currentAudit,
            identifierAudit: identifierAudit,
            identifierRepair: identifierRepair,
            backupPath: backupPath
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(output)
        if let reportPath {
            let url = URL(fileURLWithPath: reportPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        }
        print(String(decoding: data, as: UTF8.self))
    }

    private static func integerArgument(
        _ flag: String,
        in arguments: [String]
    ) throws -> Int? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        guard arguments.indices.contains(index + 1),
              let value = Int(arguments[index + 1]), value >= 0 else {
            throw CommandError.invalidInteger(flag)
        }
        return value
    }
}

private enum CommandError: Error, LocalizedError {
    case usage
    case libraryUnavailable(String)
    case missingIdentifierExpectations
    case invalidInteger(String)
    case unexpectedIdentifierScope(
        expectedAlbums: Int?,
        actualAlbums: Int,
        expectedFields: Int?,
        actualFields: Int
    )

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: SongbirdLibraryRemediator preview|local|local-inference|bpm|apple|apple-artwork|apple-track-numbers|discogs-audit|discogs-cache|discogs|discogs-fuzzy|discogs-refresh|discogs-track-numbers|identifier-audit|identifier-repair [--expected-albums N --expected-fields N] [--report PATH]"
        case .libraryUnavailable(let message):
            return message
        case .missingIdentifierExpectations:
            return "identifier-repair requires --expected-albums and --expected-fields."
        case .invalidInteger(let flag):
            return "\(flag) requires a nonnegative integer."
        case let .unexpectedIdentifierScope(
            expectedAlbums,
            actualAlbums,
            expectedFields,
            actualFields
        ):
            return "Identifier repair scope mismatch: expected "
                + "\(expectedAlbums.map(String.init) ?? "any") album(s) and "
                + "\(expectedFields.map(String.init) ?? "any") field(s), found "
                + "\(actualAlbums) album(s) and \(actualFields) field(s)."
        }
    }
}
