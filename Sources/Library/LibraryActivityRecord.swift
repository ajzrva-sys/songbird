import Foundation

/// Only controlled vocabulary and counts cross the durable activity boundary.
public enum LibraryActivityKind: String, Codable, CaseIterable, Sendable {
    case importFiles, metadataEdit, healthCheck, healthRepair, fileTagWrite
    case artworkWrite, readFileTags, libraryMaintenance, cdRip, bpmAnalysis, notice

    public var title: String {
        switch self {
        case .importFiles: "Import Music"
        case .metadataEdit: "Save Metadata"
        case .healthCheck: "Check Library Health"
        case .healthRepair: "Repair Library Health"
        case .fileTagWrite: "Save File Tags"
        case .artworkWrite: "Save Artwork to Files"
        case .readFileTags: "Read File Tags"
        case .libraryMaintenance: "Library Maintenance"
        case .cdRip: "Import Audio CD"
        case .bpmAnalysis: "Analyze BPM"
        case .notice: "Library Notice"
        }
    }
}

public enum LibraryActivityStatus: String, Codable, CaseIterable, Sendable {
    case running, cancelling, succeeded, completedWithWarnings, failed, cancelled, interrupted

    public var isTerminal: Bool { self != .running && self != .cancelling }
    public var title: String {
        switch self {
        case .running: "Running"
        case .cancelling: "Cancelling"
        case .succeeded: "Completed"
        case .completedWithWarnings: "Completed with warnings"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .interrupted: "Interrupted"
        }
    }
}

public enum LibraryActivityFailureCategory: String, Codable, Sendable {
    case missingFile, unavailableFile, unsupportedFormat, permissionDenied
    case verificationFailed, ioFailure, unknown

    public var title: String {
        switch self {
        case .missingFile: "File missing"
        case .unavailableFile: "File unavailable"
        case .unsupportedFormat: "Unsupported format"
        case .permissionDenied: "Permission denied"
        case .verificationFailed: "Verification failed"
        case .ioFailure: "File operation failed"
        case .unknown: "Operation failed"
        }
    }
}

public struct LibraryActivityFailure: Codable, Equatable, Sendable {
    public let fileName: String
    public let category: LibraryActivityFailureCategory

    public init(fileName: String, category: LibraryActivityFailureCategory) {
        self.fileName = Self.safeFileName(fileName)
        self.category = category
    }

    static func safeFileName(_ value: String) -> String {
        // HTTP/provider strings are never accepted as file names. Strip paths,
        // query fragments, controls and excess length at the single write boundary.
        guard !value.contains("://") else { return "File" }
        let basename = value.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/").last.map(String.init) ?? "File"
        let name = basename.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? "File"
        let clean = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return clean.isEmpty || clean == "." || clean == ".." ? "File" : String(clean.prefix(255))
    }
}

public struct LibraryActivityCounts: Codable, Equatable, Sendable {
    public var catalogSaved: Int
    public var filesAttempted: Int
    public var filesSaved: Int
    public var filesFailed: Int

    public init(catalogSaved: Int = 0, filesAttempted: Int = 0, filesSaved: Int = 0, filesFailed: Int = 0) {
        self.catalogSaved = max(0, catalogSaved)
        self.filesAttempted = max(0, filesAttempted)
        self.filesSaved = max(0, filesSaved)
        self.filesFailed = max(0, filesFailed)
    }
}

public struct LibraryActivityRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: LibraryActivityKind
    public let source: LibraryNoticeSource
    public var status: LibraryActivityStatus
    public var severity: LibraryNoticeSeverity
    public let startedAt: Date
    public var updatedAt: Date
    public var finishedAt: Date?
    public var completed: Int
    public var total: Int
    public var failures: [LibraryActivityFailure]
    public var failureCount: Int
    public var counts: LibraryActivityCounts?

    public var title: String {
        kind == .notice ? "\(source.activityTitle) · \(severity.activityTitle)" : kind.title
    }
    public var summary: String {
        total > 0 ? "\(status.title) · \(completed) of \(total)" : status.title
    }

    public init(id: UUID = UUID(), kind: LibraryActivityKind, source: LibraryNoticeSource = .library,
                total: Int = 0, startedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.source = source
        status = .running
        severity = .information
        self.startedAt = startedAt
        updatedAt = startedAt
        finishedAt = nil
        completed = 0
        self.total = max(0, total)
        failures = []
        failureCount = 0
        counts = nil
    }
}

extension LibraryNoticeSource {
    public var activityTitle: String {
        switch self {
        case .library: "Library"
        case .playback: "Playback"
        case .importing: "Import"
        case .metadata: "Metadata"
        case .discogs: "External Service"
        case .fileIO: "Files"
        }
    }
}

extension LibraryNoticeSeverity {
    public var activityTitle: String {
        switch self {
        case .information: "Information"
        case .success: "Success"
        case .warning: "Warning"
        case .error: "Error"
        }
    }
}
