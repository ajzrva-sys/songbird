import AudioToolbox
import AVFoundation
import Foundation

public struct AudioCDRipProgress: Equatable, Sendable {
    public let trackNumber: Int
    public let trackIndex: Int
    public let totalTracks: Int
    public let completedSectors: Int64
    public let totalSectors: Int64
    public let completedDiscSectors: Int64
    public let totalDiscSectors: Int64

    public var fractionCompleted: Double {
        guard totalDiscSectors > 0 else { return 0 }
        return min(1, max(0, Double(completedDiscSectors) / Double(totalDiscSectors)))
    }
}

public struct AudioCDRipResult: Equatable, Sendable {
    public let track: AudioDiscTrack
    public let fileURL: URL
    public let reusedExistingFile: Bool
}

public enum AudioCDRipError: Error, LocalizedError, Equatable {
    case noAudioTracks
    case malformedSectorData(expected: Int, actual: Int)
    case cannotCreateAudioBuffer
    case cannotAccessOutput(String)
    case metadataExpired(completed: [AudioCDRipResult])

    public var errorDescription: String? {
        switch self {
        case .noAudioTracks:
            "This disc has no audio tracks to import."
        case .malformedSectorData(let expected, let actual):
            "The drive returned incomplete CD audio data (expected \(expected) bytes, received \(actual))."
        case .cannotCreateAudioBuffer:
            "Songbird could not prepare an audio buffer for lossless encoding."
        case .cannotAccessOutput(let path):
            "Songbird could not create the import folder at \(path)."
        case .metadataExpired:
            "Discogs results expired. Completed audio was kept. Refresh metadata or use CD-Text to resume."
        }
    }
}

public protocol AudioCDFileWriting: AnyObject {
    func append(cddaData: Data) throws
    func finish() throws
}

public protocol AudioCDFileWriterCreating: Sendable {
    func makeWriter(at url: URL) throws -> any AudioCDFileWriting
}

public struct ALACAudioCDFileWriterFactory: AudioCDFileWriterCreating {
    public init() {}

    public func makeWriter(at url: URL) throws -> any AudioCDFileWriting {
        try ALACAudioCDFileWriter(url: url)
    }
}

private final class ALACAudioCDFileWriter: AudioCDFileWriting {
    private var file: AVAudioFile?
    private let format: AVAudioFormat

    init(url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatAppleLossless),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitDepthHintKey: 16,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        self.file = file
        self.format = file.processingFormat
    }

    func append(cddaData: Data) throws {
        guard !cddaData.isEmpty, cddaData.count.isMultiple(of: 4) else {
            throw AudioCDRipError.malformedSectorData(expected: cddaData.count, actual: cddaData.count)
        }
        let frameCount = cddaData.count / 4
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ), let samples = buffer.int16ChannelData?.pointee else {
            throw AudioCDRipError.cannotCreateAudioBuffer
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let destination = UnsafeMutableRawBufferPointer(start: samples, count: cddaData.count)
        cddaData.copyBytes(to: destination)
        try file?.write(from: buffer)
    }

    func finish() throws {
        file = nil
    }
}

public enum AudioCDRipPaths {
    public static var defaultRoot: URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music")
        return music.appendingPathComponent("Songbird", isDirectory: true)
    }

    public static func albumDirectory(for disc: AudioDisc, root: URL = defaultRoot) -> URL {
        root
            .appendingPathComponent(sanitize(albumArtist(for: disc)), isDirectory: true)
            .appendingPathComponent(sanitize(disc.title), isDirectory: true)
    }

    public static func filename(for track: AudioDiscTrack) -> String {
        String(format: "%02d %@.m4a", track.number, sanitize(track.title))
    }

    public static func albumArtist(for disc: AudioDisc) -> String {
        if let value = disc.albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty,
           value.caseInsensitiveCompare("Unknown Artist") != .orderedSame {
            return value
        }
        let artists = Set(disc.tracks.map(\.artist).filter {
            !$0.isEmpty && $0.caseInsensitiveCompare("Unknown Artist") != .orderedSame
        })
        if artists.count == 1, let artist = artists.first { return artist }
        return artists.isEmpty ? "Unknown Artist" : "Various Artists"
    }

    public static func sanitize(_ value: String) -> String {
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:"))
        let scalars = value.unicodeScalars.map { invalid.contains($0) ? "-" : String($0) }.joined()
        let trimmed = scalars.trimmingCharacters(in: .whitespacesAndNewlines.union(
            CharacterSet(charactersIn: ".-")
        ))
        let usable = trimmed.isEmpty ? "Untitled" : trimmed
        return String(usable.prefix(180))
    }
}

/// Serial optical-drive worker. Raw drive access and ALAC encoding remain off
/// the main actor, and cancellation is checked between every bounded read.
public actor AudioCDRipper {
    public typealias ProgressHandler = @Sendable (AudioCDRipProgress) async -> Void

    private let sectorReader: any AudioCDSectorReading
    private let writerFactory: any AudioCDFileWriterCreating
    private let sectorsPerRead: Int
    private let clock: @Sendable () -> DiscogsFetchStamp?

    public init(
        sectorReader: any AudioCDSectorReading = SystemAudioCDSectorReader(),
        writerFactory: any AudioCDFileWriterCreating = ALACAudioCDFileWriterFactory(),
        sectorsPerRead: Int = 150,
        clock: @escaping @Sendable () -> DiscogsFetchStamp? = { DiscogsClock.sample() }
    ) {
        self.sectorReader = sectorReader
        self.writerFactory = writerFactory
        self.sectorsPerRead = max(1, sectorsPerRead)
        self.clock = clock
    }

    public func rip(
        disc: AudioDisc,
        destinationRoot: URL = AudioCDRipPaths.defaultRoot,
        completed: [AudioCDRipResult] = [],
        progress: @escaping ProgressHandler
    ) async throws -> [AudioCDRipResult] {
        guard !disc.tracks.isEmpty else { throw AudioCDRipError.noAudioTracks }
        try Task.checkCancellation()
        try requireFresh(disc, completed: completed)

        let directory = AudioCDRipPaths.albumDirectory(for: disc, root: destinationRoot)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw AudioCDRipError.cannotAccessOutput(directory.path)
        }

        let totalDiscSectors = disc.tracks.reduce(Int64(0)) {
            $0 + max(0, $1.endSector - $1.startSector)
        }
        var completedDiscSectors: Int64 = 0
        var results: [AudioCDRipResult] = []

        for (index, track) in disc.tracks.enumerated() {
            try Task.checkCancellation()
            let totalTrackSectors = max(0, track.endSector - track.startSector)
            if let previous = completed.first(where: { $0.track.source == track.source }),
               isUsableExistingFile(previous.fileURL, expectedFrames: totalTrackSectors * 588) {
                results.append(.init(track: track, fileURL: previous.fileURL, reusedExistingFile: true))
                completedDiscSectors += totalTrackSectors
                continue
            }
            try requireFresh(disc, completed: results)
            let preferredOutputURL = directory.appendingPathComponent(AudioCDRipPaths.filename(for: track))
            let (outputURL, canReuseOutput) = resolvedOutputURL(
                preferredOutputURL,
                expectedFrames: totalTrackSectors * 588
            )

            if canReuseOutput {
                completedDiscSectors += totalTrackSectors
                results.append(.init(track: track, fileURL: outputURL, reusedExistingFile: true))
                await progress(.init(
                    trackNumber: track.number,
                    trackIndex: index + 1,
                    totalTracks: disc.tracks.count,
                    completedSectors: totalTrackSectors,
                    totalSectors: totalTrackSectors,
                    completedDiscSectors: completedDiscSectors,
                    totalDiscSectors: totalDiscSectors
                ))
                continue
            }

            let temporaryURL = directory.appendingPathComponent(
                ".\(UUID().uuidString).partial.m4a"
            )
            var writer: (any AudioCDFileWriting)?
            do {
                writer = try writerFactory.makeWriter(at: temporaryURL)
                var nextSector = track.startSector
                while nextSector < track.endSector {
                    try Task.checkCancellation()
                    let count = Int(min(Int64(sectorsPerRead), track.endSector - nextSector))
                    let data = try await readWithRetry(
                        deviceID: track.source.deviceID,
                        firstSector: nextSector,
                        count: count
                    )
                    let expected = count * 2_352
                    guard data.count == expected else {
                        throw AudioCDRipError.malformedSectorData(
                            expected: expected,
                            actual: data.count
                        )
                    }
                    try writer?.append(cddaData: data)
                    nextSector += Int64(count)
                    let completedTrackSectors = nextSector - track.startSector
                    await progress(.init(
                        trackNumber: track.number,
                        trackIndex: index + 1,
                        totalTracks: disc.tracks.count,
                        completedSectors: completedTrackSectors,
                        totalSectors: totalTrackSectors,
                        completedDiscSectors: completedDiscSectors + completedTrackSectors,
                        totalDiscSectors: totalDiscSectors
                    ))
                }
                try writer?.finish()
                writer = nil
                try Task.checkCancellation()
                if let evidence = disc.discogsEvidence, !evidence.isFresh(at: clock()) {
                    // Finish and preserve this audio without committing an expired metadata-derived name.
                    let recovered = directory.appendingPathComponent("Recovered track \(track.number)-\(UUID().uuidString).m4a")
                    try FileManager.default.moveItem(at: temporaryURL, to: recovered)
                    results.append(.init(track: track, fileURL: recovered, reusedExistingFile: false))
                    throw AudioCDRipError.metadataExpired(completed: results)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
            } catch {
                writer = nil
                try? FileManager.default.removeItem(at: temporaryURL)
                throw error
            }

            completedDiscSectors += totalTrackSectors
            results.append(.init(track: track, fileURL: outputURL, reusedExistingFile: false))
        }
        return results
    }

    private func requireFresh(_ disc: AudioDisc, completed: [AudioCDRipResult]) throws {
        if let evidence = disc.discogsEvidence, !evidence.isFresh(at: clock()) {
            throw AudioCDRipError.metadataExpired(completed: completed)
        }
    }

    private func readWithRetry(deviceID: String, firstSector: Int64, count: Int) async throws -> Data {
        var lastError: Error = AudioCDReaderError.deviceRead(-1)
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                return try sectorReader.readSectors(
                    deviceID: deviceID,
                    firstSector: firstSector,
                    count: count
                )
            } catch {
                lastError = error
                if attempt < 2 {
                    try await Task.sleep(for: .milliseconds(20 * (attempt + 1)))
                }
            }
        }
        throw lastError
    }

    private func resolvedOutputURL(_ preferred: URL, expectedFrames: Int64) -> (URL, Bool) {
        if isUsableExistingFile(preferred, expectedFrames: expectedFrames) {
            return (preferred, true)
        }
        if !FileManager.default.fileExists(atPath: preferred.path) {
            return (preferred, false)
        }

        let directory = preferred.deletingLastPathComponent()
        let extensionName = preferred.pathExtension
        let stem = preferred.deletingPathExtension().lastPathComponent
        for suffix in 2...999 {
            let candidate = directory.appendingPathComponent("\(stem) (\(suffix)).\(extensionName)")
            if isUsableExistingFile(candidate, expectedFrames: expectedFrames) {
                return (candidate, true)
            }
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return (candidate, false)
            }
        }
        return (directory.appendingPathComponent("\(stem) (\(UUID().uuidString)).\(extensionName)"), false)
    }

    private func isUsableExistingFile(_ url: URL, expectedFrames: Int64) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              (values.fileSize ?? 0) > 0,
              let file = try? AVAudioFile(forReading: url) else {
            return false
        }
        let formatID = (file.fileFormat.settings[AVFormatIDKey] as? NSNumber)?.uint32Value
        return formatID == kAudioFormatAppleLossless
            && file.fileFormat.channelCount == 2
            && abs(file.fileFormat.sampleRate - 44_100) < 0.5
            && abs(file.length - expectedFrames) <= 1
    }
}
