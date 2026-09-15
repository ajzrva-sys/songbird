import Foundation

public struct FileAvailabilityRequest: Equatable, Sendable {
    public let id: UUID
    public let path: String

    public init(id: UUID, path: String) {
        self.id = id
        self.path = path
    }
}

public struct FileAvailabilitySnapshot: Equatable, Sendable {
    public let availableURLs: [UUID: URL]
    public let missingIDs: Set<UUID>
    public let unavailableReasons: [UUID: FileUnavailableReason]

    public init(
        availableURLs: [UUID: URL] = [:],
        missingIDs: Set<UUID> = [],
        unavailableReasons: [UUID: FileUnavailableReason] = [:]
    ) {
        self.availableURLs = availableURLs
        self.missingIDs = missingIDs
        self.unavailableReasons = unavailableReasons
    }
}

public struct FileRelocationRequest: Equatable, Sendable {
    public let trackID: UUID
    public let expectedPath: String
    public let expectedChecksum: String

    public init(trackID: UUID, expectedPath: String, expectedChecksum: String) {
        self.trackID = trackID
        self.expectedPath = expectedPath
        self.expectedChecksum = expectedChecksum
    }
}

public struct FileRelocationScan: Equatable, Sendable {
    public let candidatesByTrackID: [UUID: [LibraryFileRelocationCandidate]]
    public let rootFailures: [LibraryFileRootFailure]

    public init(
        candidatesByTrackID: [UUID: [LibraryFileRelocationCandidate]] = [:],
        rootFailures: [LibraryFileRootFailure] = []
    ) {
        self.candidatesByTrackID = candidatesByTrackID
        self.rootFailures = rootFailures
    }
}

public actor FileAvailabilityWorker {
    private let pathResolver: FilesystemPathResolver

    public init() {
        pathResolver = FilesystemPathResolver()
    }

    init(pathResolver: FilesystemPathResolver) {
        self.pathResolver = pathResolver
    }

    public func existingFileURLs(paths: [String]) -> [URL] {
        var seenPaths: Set<String> = []
        var cache = FilesystemPathResolver.Cache()
        return paths.compactMap { path in
            guard let url = pathResolver.existingFileURL(for: path, cache: &cache),
                  seenPaths.insert(url.path).inserted else { return nil }
            return url
        }
    }

    public func resolve(path: String) -> FileResolution {
        pathResolver.resolve(path)
    }

    public func availability(
        _ requests: [FileAvailabilityRequest]
    ) -> FileAvailabilitySnapshot {
        var available: [UUID: URL] = [:]
        var missing = Set<UUID>()
        var unavailable: [UUID: FileUnavailableReason] = [:]
        var cache = FilesystemPathResolver.Cache()
        for (index, request) in requests.enumerated() {
            if index.isMultiple(of: 256), Task.isCancelled { break }
            switch pathResolver.resolve(request.path, cache: &cache) {
            case .available(let url):
                available[request.id] = url
            case .missing:
                missing.insert(request.id)
            case .unavailable(let reason):
                unavailable[request.id] = reason
            }
        }
        return FileAvailabilitySnapshot(
            availableURLs: available,
            missingIDs: missing,
            unavailableReasons: unavailable
        )
    }

    /// Cancellation-aware variant used by explicit Library Health checks. It never returns a
    /// partial result, so cancellation cannot be misreported as a healthy library.
    public func availabilityCheckingCancellation(
        _ requests: [FileAvailabilityRequest]
    ) throws -> FileAvailabilitySnapshot {
        var available: [UUID: URL] = [:]
        var missing = Set<UUID>()
        var unavailable: [UUID: FileUnavailableReason] = [:]
        var cache = FilesystemPathResolver.Cache()
        for (index, request) in requests.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            switch pathResolver.resolve(request.path, cache: &cache) {
            case .available(let url):
                available[request.id] = url
            case .missing:
                missing.insert(request.id)
            case .unavailable(let reason):
                unavailable[request.id] = reason
            }
        }
        try Task.checkCancellation()
        return FileAvailabilitySnapshot(
            availableURLs: available,
            missingIDs: missing,
            unavailableReasons: unavailable
        )
    }

    public func missingFileIDs(_ requests: [FileAvailabilityRequest]) -> Set<UUID> {
        availability(requests).missingIDs
    }

    /// Builds one filename index across all explicitly configured roots. The caller invokes this
    /// only from Check Now/Retry; no snapshot or mount notification may trigger it implicitly.
    public func relocationCandidates(
        for requests: [FileRelocationRequest],
        searchRoots: [String]
    ) throws -> FileRelocationScan {
        let requestedNames = Set(requests.map {
            URL(fileURLWithPath: $0.expectedPath).lastPathComponent.lowercased()
        })
        var pathsByName: [String: Set<String>] = [:]
        var failures: [LibraryFileRootFailure] = []
        var resolverCache = FilesystemPathResolver.Cache()
        var seenRoots = Set<String>()

        for rawRoot in searchRoots {
            try Task.checkCancellation()
            let root = (rawRoot as NSString).standardizingPath
            guard root.isEmpty == false, seenRoots.insert(root).inserted else { continue }
            switch pathResolver.resolve(root, cache: &resolverCache) {
            case .missing:
                failures.append(.init(path: root, reason: .missing))
                continue
            case .unavailable(let reason):
                failures.append(.init(
                    path: root,
                    reason: .unavailable(LibraryFileUnavailableReason(reason))
                ))
                continue
            case .available(let rootURL):
                guard requestedNames.isEmpty == false else { continue }
                var enumerationError = false
                guard let enumerator = FileManager.default.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in
                        enumerationError = true
                        return true
                    }
                ) else {
                    failures.append(.init(path: root, reason: .enumerationFailed))
                    continue
                }
                var visited = 0
                while let url = enumerator.nextObject() as? URL {
                    visited += 1
                    if visited.isMultiple(of: 128) { try Task.checkCancellation() }
                    let name = url.lastPathComponent.lowercased()
                    guard requestedNames.contains(name),
                          (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                        continue
                    }
                    pathsByName[name, default: []].insert(url.standardizedFileURL.path)
                }
                if enumerationError {
                    failures.append(.init(path: root, reason: .enumerationFailed))
                }
            }
        }

        var result: [UUID: [LibraryFileRelocationCandidate]] = [:]
        for request in requests {
            try Task.checkCancellation()
            let name = URL(fileURLWithPath: request.expectedPath).lastPathComponent.lowercased()
            result[request.trackID] = try pathsByName[name, default: []].sorted().map { path in
                try Task.checkCancellation()
                let checksum = Track.contentChecksum(at: path)
                return LibraryFileRelocationCandidate(
                    path: path,
                    checksum: checksum,
                    checksumMatchesCatalog: request.expectedChecksum.isEmpty == false
                        && checksum == request.expectedChecksum
                )
            }
        }
        return FileRelocationScan(candidatesByTrackID: result, rootFailures: failures)
    }
}
