import Darwin
import Foundation

public enum FileUnavailableReason: Error, Equatable, Sendable {
    case volumeNotMounted(String)
    case permissionDenied(String)
    case ioFailure(path: String, code: Int32)
    case ambiguousUnicode(String)

    public var message: String {
        switch self {
        case .volumeNotMounted(let path):
            return "Library volume is unavailable: \(path)"
        case .permissionDenied(let path):
            return "Songbird does not have permission to access: \(path)"
        case .ioFailure(let path, _):
            return "The file is temporarily unavailable: \(path)"
        case .ambiguousUnicode(let path):
            return "More than one filesystem entry matches: \(path)"
        }
    }
}

public enum FileResolution: Equatable, Sendable {
    case available(URL)
    case missing
    case unavailable(FileUnavailableReason)

    public var availableURL: URL? {
        guard case .available(let url) = self else { return nil }
        return url
    }
}

/// Resolves stored paths without assuming that canonically equivalent Unicode
/// spellings address the same bytes on every filesystem.
public struct FilesystemPathResolver: Sendable {
    enum ProbeResult: Equatable, Sendable {
        case exists
        case missing
        case unavailable(FileUnavailableReason)
    }

    struct Cache {
        var directoryEntries: [String: Result<[URL], FileUnavailableReason>] = [:]
    }

    typealias Probe = @Sendable (String) -> ProbeResult
    typealias DirectoryContents = @Sendable (URL) -> Result<[URL], FileUnavailableReason>

    private let probe: Probe
    private let directoryContents: DirectoryContents

    public init() {
        probe = { path in
            var status = stat()
            if path.withCString({ Darwin.lstat($0, &status) }) == 0 {
                if (status.st_mode & S_IFMT) != S_IFDIR,
                   path.withCString({ Darwin.access($0, R_OK) }) != 0 {
                    return Self.probeFailure(path: path, code: errno)
                }
                return .exists
            }
            return Self.probeFailure(path: path, code: errno)
        }
        directoryContents = { url in
            do {
                return .success(try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: []
                ))
            } catch {
                let nsError = error as NSError
                let code = Int32(nsError.userInfo[NSUnderlyingErrorKey]
                    .flatMap { ($0 as? NSError)?.code } ?? nsError.code)
                return .failure(Self.unavailableReason(path: url.path, code: code))
            }
        }
    }

    init(
        probe: @escaping Probe,
        directoryContents: @escaping DirectoryContents
    ) {
        self.probe = probe
        self.directoryContents = directoryContents
    }

    /// Compatibility initializer for deterministic byte-sensitive fixtures.
    init(
        fileExists: @escaping @Sendable (String) -> Bool,
        directoryContents: @escaping @Sendable (URL) -> [URL]?
    ) {
        probe = { fileExists($0) ? .exists : .missing }
        self.directoryContents = { url in
            .success(directoryContents(url) ?? [])
        }
    }

    public func resolve(_ path: String) -> FileResolution {
        var cache = Cache()
        return resolve(path, cache: &cache)
    }

    func resolve(_ path: String, cache: inout Cache) -> FileResolution {
        let requestedPath = (path as NSString).standardizingPath
        switch probe(requestedPath) {
        case .exists:
            return .available(filesystemURL(for: requestedPath))
        case .unavailable(let reason):
            return .unavailable(reason)
        case .missing:
            break
        }

        let components = (requestedPath as NSString).pathComponents
        guard components.first == "/" else { return .missing }

        var resolved = filesystemURL(for: "/", isDirectory: true)
        for component in components.dropFirst() {
            let exactPath = (resolved.path as NSString).appendingPathComponent(component)
            switch probe(exactPath) {
            case .exists:
                resolved = filesystemURL(for: exactPath)
                continue
            case .unavailable(let reason):
                return .unavailable(reason)
            case .missing:
                break
            }

            let entriesResult = cachedDirectoryContents(for: resolved, cache: &cache)
            let entries: [URL]
            switch entriesResult {
            case .success(let value):
                entries = value
            case .failure(let reason):
                return .unavailable(reason)
            }

            switch canonicalMatch(for: component, in: entries) {
            case .one(let match):
                resolved = match
            case .none:
                if resolved.path == "/Volumes" {
                    return .unavailable(.volumeNotMounted(exactPath))
                }
                return .missing
            case .ambiguous:
                return .unavailable(.ambiguousUnicode(exactPath))
            }
        }

        switch probe(resolved.path) {
        case .exists:
            return .available(resolved)
        case .missing:
            return .missing
        case .unavailable(let reason):
            return .unavailable(reason)
        }
    }

    /// Returns an existing URL using the filesystem's actual component spelling.
    public func existingFileURL(for path: String) -> URL? {
        resolve(path).availableURL
    }

    func existingFileURL(for path: String, cache: inout Cache) -> URL? {
        resolve(path, cache: &cache).availableURL
    }

    private enum CanonicalMatch {
        case none
        case one(URL)
        case ambiguous
    }

    private func canonicalMatch(for component: String, in entries: [URL]) -> CanonicalMatch {
        let canonicalComponent = component.precomposedStringWithCanonicalMapping
        let matches = entries.filter {
            $0.lastPathComponent.precomposedStringWithCanonicalMapping == canonicalComponent
        }
        if matches.count == 1 { return .one(matches[0]) }
        return matches.isEmpty ? .none : .ambiguous
    }

    private func cachedDirectoryContents(
        for url: URL,
        cache: inout Cache
    ) -> Result<[URL], FileUnavailableReason> {
        let key = scalarKey(url.path)
        if let cached = cache.directoryEntries[key] { return cached }
        let result = directoryContents(url)
        cache.directoryEntries[key] = result
        return result
    }

    private func filesystemURL(for path: String, isDirectory: Bool = false) -> URL {
        path.withCString {
            URL(
                fileURLWithFileSystemRepresentation: $0,
                isDirectory: isDirectory,
                relativeTo: nil
            )
        }
    }

    private func scalarKey(_ value: String) -> String {
        value.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "|")
    }

    private static func probeFailure(path: String, code: Int32) -> ProbeResult {
        switch code {
        case ENOENT, ENOTDIR:
            return .missing
        default:
            return .unavailable(unavailableReason(path: path, code: code))
        }
    }

    private static func unavailableReason(path: String, code: Int32) -> FileUnavailableReason {
        if code == EACCES || code == EPERM {
            return .permissionDenied(path)
        }
        return .ioFailure(path: path, code: code)
    }
}
