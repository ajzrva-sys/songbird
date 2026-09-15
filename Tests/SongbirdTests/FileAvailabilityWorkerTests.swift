import Foundation
import Testing
@testable import SongbirdLib

@Suite("File availability worker")
struct FileAvailabilityWorkerTests {
    @Test("A restored path stops being reported as missing")
    func restoredPathBecomesAvailable() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-file-availability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("restored.m4a")
        let id = UUID()
        let request = FileAvailabilityRequest(id: id, path: path.path)
        let worker = FileAvailabilityWorker()

        #expect(await worker.missingFileIDs([request]) == [id])

        try Data([0]).write(to: path)

        #expect(await worker.missingFileIDs([request]).isEmpty)
    }

    @Test("A canonically equivalent filename uses the filesystem spelling")
    func canonicallyEquivalentFilenameIsAvailable() async {
        let stored = "/Volumes/music/Yelle/02 A cause des gar\u{00E7}ons.m4a"
        let actual = "/Volumes/music/Yelle/02 A cause des garc\u{0327}ons.m4a"
        let worker = FileAvailabilityWorker(pathResolver: fakeResolver(existingPaths: [actual]))
        let id = UUID()

        #expect(await worker.missingFileIDs([.init(id: id, path: stored)]).isEmpty)
        let urls = await worker.existingFileURLs(paths: [stored])
        #expect(urls.count == 1)
        #expect(scalarKey(urls[0].path) == scalarKey(actual))
    }

    @Test("An exact NFC path preserves its filesystem spelling")
    func exactNFCFilenameIsPreserved() async {
        let exact = "/Volumes/music/Yelle/02 A cause des gar\u{00E7}ons.m4a"
        let worker = FileAvailabilityWorker(pathResolver: fakeResolver(existingPaths: [exact]))
        let id = UUID()

        #expect(await worker.missingFileIDs([.init(id: id, path: exact)]).isEmpty)
        let urls = await worker.existingFileURLs(paths: [exact])
        #expect(urls.count == 1)
        #expect(scalarKey(urls[0].path) == scalarKey(exact))
    }

    @Test("Canonical recovery resolves an equivalent parent directory")
    func canonicallyEquivalentParentIsAvailable() async {
        let stored = "/Volumes/music/Bj\u{00F6}rk/Vespertine/01 Hidden Place.m4a"
        let actual = "/Volumes/music/Bjo\u{0308}rk/Vespertine/01 Hidden Place.m4a"
        let worker = FileAvailabilityWorker(pathResolver: fakeResolver(existingPaths: [actual]))
        let id = UUID()

        #expect(await worker.missingFileIDs([.init(id: id, path: stored)]).isEmpty)
        let urls = await worker.existingFileURLs(paths: [stored])
        #expect(urls.count == 1)
        #expect(scalarKey(urls[0].path) == scalarKey(actual))
    }

    @Test("Canonical recovery rejects ambiguous filesystem entries without calling them missing")
    func ambiguousEquivalentNamesRemainUnavailable() async {
        let stored = "/Volumes/music/Yelle/gar\u{00E7}ons.m4a"
        let composed = "/Volumes/music/Yelle/gar\u{00E7}ons.m4a"
        let decomposed = "/Volumes/music/Yelle/garc\u{0327}ons.m4a"
        let resolver = fakeResolver(
            existingPaths: [composed, decomposed],
            exactLookupFailures: [stored]
        )
        let worker = FileAvailabilityWorker(pathResolver: resolver)
        let id = UUID()

        let availability = await worker.availability([.init(id: id, path: stored)])
        #expect(availability.missingIDs.isEmpty)
        #expect(availability.unavailableReasons[id] == .ambiguousUnicode(stored))
        #expect(await worker.existingFileURLs(paths: [stored]).isEmpty)
    }

    @Test("Canonical recovery does not fold filename case")
    func caseDifferenceRemainsMissing() async {
        let stored = "/Volumes/music/Yelle/SONG.m4a"
        let actual = "/Volumes/music/Yelle/song.m4a"
        let worker = FileAvailabilityWorker(pathResolver: fakeResolver(existingPaths: [actual]))
        let id = UUID()

        #expect(await worker.missingFileIDs([.init(id: id, path: stored)]) == [id])
    }

    @Test("An unmounted library volume is unavailable rather than missing")
    func unmountedVolumeIsUnavailable() async {
        let path = "/Volumes/music/Artist/Track.m4a"
        let resolver = FilesystemPathResolver(
            probe: { candidate in
                candidate == "/" || candidate == "/Volumes" ? .exists : .missing
            },
            directoryContents: { url in
                .success(url.path == "/" ? [filesystemURL(for: "/Volumes")] : [])
            }
        )
        let worker = FileAvailabilityWorker(pathResolver: resolver)
        let id = UUID()

        let result = await worker.availability([.init(id: id, path: path)])

        #expect(result.missingIDs.isEmpty)
        #expect(result.unavailableReasons[id] == .volumeNotMounted("/Volumes/music"))
    }

    @Test("A missing leaf on a mounted volume remains genuinely missing")
    func mountedMissingLeafIsMissing() async {
        let path = "/Volumes/music/Artist/Gone.m4a"
        let existing = ["/", "/Volumes", "/Volumes/music", "/Volumes/music/Artist"]
        let resolver = FilesystemPathResolver(
            probe: { existing.contains($0) ? .exists : .missing },
            directoryContents: { url in
                switch url.path {
                case "/": return .success([filesystemURL(for: "/Volumes")])
                case "/Volumes": return .success([filesystemURL(for: "/Volumes/music")])
                case "/Volumes/music": return .success([filesystemURL(for: "/Volumes/music/Artist")])
                default: return .success([])
                }
            }
        )
        let worker = FileAvailabilityWorker(pathResolver: resolver)
        let id = UUID()

        let result = await worker.availability([.init(id: id, path: path)])

        #expect(result.missingIDs == [id])
        #expect(result.unavailableReasons.isEmpty)
    }

    @Test("Permission and I/O failures fail closed as unavailable")
    func accessFailuresAreUnavailable() async {
        let deniedPath = "/Volumes/music/Denied.m4a"
        let ioPath = "/Volumes/music/Stalled.m4a"
        let resolver = FilesystemPathResolver(
            probe: { path in
                if path == deniedPath { return .unavailable(.permissionDenied(path)) }
                if path == ioPath { return .unavailable(.ioFailure(path: path, code: EIO)) }
                return .exists
            },
            directoryContents: { _ in .success([]) }
        )
        let worker = FileAvailabilityWorker(pathResolver: resolver)
        let deniedID = UUID()
        let ioID = UUID()

        let result = await worker.availability([
            .init(id: deniedID, path: deniedPath),
            .init(id: ioID, path: ioPath),
        ])

        #expect(result.missingIDs.isEmpty)
        #expect(result.unavailableReasons[deniedID] == .permissionDenied(deniedPath))
        #expect(result.unavailableReasons[ioID] == .ioFailure(path: ioPath, code: EIO))
    }

    @Test("Missing Files refreshes only when a running scan ends")
    func scanCompletionRequestsRefresh() {
        #expect(GhostTracksRefreshPolicy.shouldRefresh(from: .running, to: .succeeded))
        #expect(GhostTracksRefreshPolicy.shouldRefresh(from: .cancelling, to: .idle))
        #expect(!GhostTracksRefreshPolicy.shouldRefresh(from: .running, to: .cancelling))
        #expect(!GhostTracksRefreshPolicy.shouldRefresh(from: .idle, to: .succeeded))
    }

    @Test("Cancellation-aware availability never returns a partial snapshot")
    func cancellationAwareAvailabilityThrows() async {
        let worker = FileAvailabilityWorker(pathResolver: fakeResolver(existingPaths: []))
        let requests = (0..<512).map { index in
            FileAvailabilityRequest(id: UUID(), path: "/tmp/missing-\(index).flac")
        }
        let task = Task {
            try await worker.availabilityCheckingCancellation(requests)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("Relocation discovery indexes configured roots once and preserves ambiguity")
    func relocationDiscovery() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("songbird-relocation-scan-\(UUID().uuidString)")
        let firstRoot = base.appendingPathComponent("first")
        let secondRoot = base.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let unique = firstRoot.appendingPathComponent("unique.flac")
        let ambiguousA = firstRoot.appendingPathComponent("same.flac")
        let ambiguousB = secondRoot.appendingPathComponent("same.flac")
        try Data([1, 2, 3]).write(to: unique)
        try Data([4]).write(to: ambiguousA)
        try Data([5]).write(to: ambiguousB)
        let uniqueID = UUID()
        let ambiguousID = UUID()
        let worker = FileAvailabilityWorker()

        let scan = try await worker.relocationCandidates(
            for: [
                FileRelocationRequest(
                    trackID: uniqueID,
                    expectedPath: "/missing/unique.flac",
                    expectedChecksum: Track.contentChecksum(at: unique.path)
                ),
                FileRelocationRequest(
                    trackID: ambiguousID,
                    expectedPath: "/missing/same.flac",
                    expectedChecksum: ""
                ),
            ],
            searchRoots: [firstRoot.path, firstRoot.path, secondRoot.path,
                          base.appendingPathComponent("not-mounted").path]
        )

        #expect(scan.candidatesByTrackID[uniqueID]?.count == 1)
        #expect(scan.candidatesByTrackID[uniqueID]?.first?.checksumMatchesCatalog == true)
        #expect(scan.candidatesByTrackID[ambiguousID]?.count == 2)
        #expect(scan.rootFailures.count == 1)
        #expect(scan.rootFailures.first?.reason == .missing)
    }

    private func fakeResolver(
        existingPaths: [String],
        exactLookupFailures: [String] = []
    ) -> FilesystemPathResolver {
        let existingKeys = Set(existingPaths.map(scalarKey))
        let forcedFailureKeys = Set(exactLookupFailures.map(scalarKey))
        var listings: [String: [URL]] = [:]

        for path in existingPaths {
            let components = (path as NSString).pathComponents
            var parentPath = "/"
            for component in components.dropFirst() {
                let childPath = (parentPath as NSString).appendingPathComponent(component)
                let child = filesystemURL(for: childPath)
                let parentKey = scalarKey(parentPath)
                if listings[parentKey, default: []].contains(where: {
                    scalarKey($0.path) == scalarKey(child.path)
                }) == false {
                    listings[parentKey, default: []].append(child)
                }
                parentPath = childPath
            }
        }
        let immutableListings = listings

        return FilesystemPathResolver(
            fileExists: { path in
                let key = scalarKey(path)
                if forcedFailureKeys.contains(key) { return false }
                if existingKeys.contains(key) { return true }
                return existingKeys.contains { $0.hasPrefix(key + "|") }
            },
            directoryContents: { immutableListings[scalarKey($0.path)] }
        )
    }

    private func scalarKey(_ value: String) -> String {
        value.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "|")
    }

    private func filesystemURL(for path: String) -> URL {
        path.withCString {
            URL(
                fileURLWithFileSystemRepresentation: $0,
                isDirectory: false,
                relativeTo: nil
            )
        }
    }
}
