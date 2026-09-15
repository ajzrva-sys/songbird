import Foundation

/// Persists file paths that a person explicitly removed from Songbird so
/// automatic watched-folder scans do not silently add them back.
public struct LibraryImportExclusionStore: Sendable {
    static let defaultsKey = "songbird.libraryImport.explicitlyRemovedPaths"
    public static let shared = LibraryImportExclusionStore()

    private static let lock = NSLock()
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    func contains(_ path: String) -> Bool {
        Self.withLock {
            storedPaths().contains(Self.standardized(path))
        }
    }

    func exclude(paths: [String]) {
        let standardized = Set(paths.map(Self.standardized).filter { !$0.isEmpty })
        guard !standardized.isEmpty else { return }
        Self.withLock {
            var stored = storedPaths()
            let previous = stored
            stored.formUnion(standardized)
            if stored != previous { save(stored) }
        }
    }

    func allow(paths: [String]) {
        let standardized = Set(paths.map(Self.standardized).filter { !$0.isEmpty })
        guard !standardized.isEmpty else { return }
        Self.withLock {
            var stored = storedPaths()
            let previous = stored
            stored.subtract(standardized)
            if stored != previous { save(stored) }
        }
    }

    func clear() {
        Self.withLock {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }

    func snapshot() -> Set<String> {
        Self.withLock { storedPaths() }
    }

    func restore(_ paths: Set<String>) {
        Self.withLock { save(paths) }
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    private func storedPaths() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    private func save(_ paths: Set<String>) {
        defaults.set(paths.sorted(), forKey: Self.defaultsKey)
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
