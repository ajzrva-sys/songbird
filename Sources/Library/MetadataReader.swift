import AubioBridge
import AVFoundation
import AudioToolbox
import CoreMedia
import FLACBridge
import Foundation

public struct AudioMetadata: Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var genre: String
    public var composer: String
    public var comment: String
    public var year: Int
    public var trackNumber: Int
    public var trackTotal: Int
    public var discNumber: Int
    public var discTotal: Int
    public var beatsPerMinute: Int
    public var duration: TimeInterval
    public var bitrate: Int
    public var sampleRate: Int
    public var artworkData: Data?
}

public enum MetadataReader {
    /// Reads tags and stream properties independently from the playback engine.
    public static func read(
        from url: URL,
        backend: (any PlayerBackend)? = nil,
        detectMissingBPM: Bool = true
    ) async -> AudioMetadata? {
        let metadata: AudioMetadata?
        if url.pathExtension.lowercased() == "flac" {
            // libFLAC exposes STREAMINFO, Vorbis comments, and artwork in one
            // metadata pass. Avoid opening every FLAC again through both
            // AVFoundation and AudioToolbox during large library imports.
            metadata = readViaFLACBridge(url: url)
        } else {
            var m = blank(from: url)
            if let av = await readViaAVFoundation(url: url) {
                mergePreferringExisting(&m, with: av)
            }
            metadata = m
        }

        guard var result = metadata else { return nil }

        if detectMissingBPM, result.beatsPerMinute == 0 {
            result.beatsPerMinute = await detectBPM(from: url)
        }

        result.genre = GenreMetadata.normalized(result.genre)

        return result
    }

    // MARK: - AVFoundation fallback

    private static func readViaAVFoundation(url: URL) async -> AudioMetadata? {
        let asset = AVURLAsset(url: url)
        var metadata = blank(from: url)

        do {
            let duration = try await asset.load(.duration)
            metadata.duration = max(0, duration.seconds)
        } catch {
            metadata.duration = 0
        }

        // Prefer common keys (reliable for iTunes/ALAC), then full metadata bag.
        let common = (try? await asset.load(.commonMetadata)) ?? []
        let all = (try? await asset.load(.metadata)) ?? []
        await applyAVItems(common + all, to: &metadata)

        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            if let track = tracks.first {
                let descs = try await track.load(.formatDescriptions)
                for desc in descs {
                    let audio = CMAudioFormatDescriptionGetStreamBasicDescription(desc)
                    if let audio {
                        metadata.sampleRate = Int(audio.pointee.mSampleRate.rounded())
                    }
                }
                if let rate = try? await track.load(.estimatedDataRate), rate > 0 {
                    metadata.bitrate = Int((Double(rate) / 1000.0).rounded())
                }
            }
            if metadata.bitrate == 0 {
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                if let size = attrs?[.size] as? Int64, metadata.duration > 0 {
                    metadata.bitrate = Int((Double(size) * 8.0 / metadata.duration / 1000.0).rounded())
                }
            }
        } catch {
            // ignore format probe failures
        }

        return metadata
    }

    private static func applyAVItems(_ items: [AVMetadataItem], to metadata: inout AudioMetadata) async {
        for item in items {
            let raw = item.identifier?.rawValue ?? ""
            let common = item.commonKey?.rawValue ?? ""
            let keySpace = item.keySpace?.rawValue ?? ""
            let keyDesc = (item.key as? NSString as String?) ?? ""
            let key = [raw, common, keySpace, keyDesc].joined(separator: " ").lowercased()
            let lower = key.lowercased()

            if lower.contains("artwork") || common == "artwork" {
                if let data = try? await item.load(.dataValue) {
                    metadata.artworkData = data
                }
                continue
            }

            if let number = try? await item.load(.numberValue) {
                if lower.contains("totaltracks") || lower.contains("trackcount") {
                    if metadata.trackTotal == 0 { metadata.trackTotal = number.intValue }
                } else if lower.contains("discnumber") {
                    if metadata.discNumber == 0 { metadata.discNumber = number.intValue }
                } else if lower.contains("totaldiscs") || lower.contains("disccount") {
                    if metadata.discTotal == 0 { metadata.discTotal = number.intValue }
                } else if lower.contains("tempo") || lower.contains("bpm") {
                    if metadata.beatsPerMinute == 0 { metadata.beatsPerMinute = number.intValue }
                } else if lower.contains("tracknumber")
                    || (lower.contains("track") && !lower.contains("disc")) {
                    if metadata.trackNumber == 0 { metadata.trackNumber = number.intValue }
                } else if lower.contains("year") || lower.contains("date") {
                    if metadata.year == 0 { metadata.year = number.intValue }
                }
            }

            let stringValue: String?
            if let s = try? await item.load(.stringValue), !s.isEmpty {
                stringValue = s
            } else if let date = try? await item.load(.dateValue) {
                let y = Calendar.current.component(.year, from: date)
                stringValue = y > 0 ? "\(y)" : nil
            } else {
                stringValue = nil
            }
            guard let value = stringValue, !value.isEmpty else { continue }

            let isTitleKey = common == "title"
                || lower.contains("©nam")
                || (lower.contains("title") && !lower.contains("album"))
            let isArtistKey = common == "artist" || lower.contains("©art")
                || (lower.contains("artist") && !lower.contains("album"))
            let isAlbumArtistKey = lower.contains("albumartist") || lower.contains("aart")
                || (lower.contains("album") && lower.contains("artist"))
            let isAlbumKey = common == "albumName" || lower.contains("©alb")
                || (lower.contains("album") && !lower.contains("artist"))

            if isTitleKey, looksLikeFilenameTitle(metadata.title) {
                metadata.title = value
            } else if isAlbumArtistKey {
                if metadata.albumArtist == "Unknown Artist" { metadata.albumArtist = value }
            } else if isArtistKey {
                if metadata.artist == "Unknown Artist" { metadata.artist = value }
            } else if isAlbumKey {
                if metadata.album == "Unknown Album" { metadata.album = value }
            } else if common == "type" || lower.contains("genre") || lower.contains("©gen") {
                if metadata.genre.isEmpty { metadata.genre = value }
            } else if lower.contains("composer") || lower.contains("©wrt") {
                if metadata.composer.isEmpty { metadata.composer = value }
            } else if lower.contains("comment") || lower.contains("©cmt") {
                if metadata.comment.isEmpty { metadata.comment = value }
            } else if lower.contains("year") || lower.contains("creationdate")
                        || lower.contains("©day") || lower == "day" || lower.contains("date") {
                if metadata.year == 0 { metadata.year = parseYear(from: value) }
            } else if lower.contains("discnumber") || lower.contains("disk") {
                let pair = parseNumberPair(value)
                if metadata.discNumber == 0 { metadata.discNumber = pair.number }
                if metadata.discTotal == 0 { metadata.discTotal = pair.total }
            } else if lower.contains("tracknumber") || lower.contains("trkn") || lower == "track" {
                let pair = parseNumberPair(value)
                if metadata.trackNumber == 0 { metadata.trackNumber = pair.number }
                if metadata.trackTotal == 0 { metadata.trackTotal = pair.total }
            } else if lower.contains("tempo") || lower.contains("bpm") {
                if metadata.beatsPerMinute == 0 { metadata.beatsPerMinute = Int(value) ?? 0 }
            }
        }

        if metadata.albumArtist == "Unknown Artist", metadata.artist != "Unknown Artist" {
            metadata.albumArtist = metadata.artist
        }
    }

    /// Core Audio exposes FLAC Vorbis comments through its file info dictionary
    /// on systems where AVAsset does not surface all common metadata keys.
    private static func readViaAudioToolbox(url: URL) -> AudioMetadata? {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr,
              let file else { return nil }
        defer { AudioFileClose(file) }

        var dictionary: Unmanaged<CFDictionary>?
        var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        guard AudioFileGetProperty(
            file,
            kAudioFilePropertyInfoDictionary,
            &size,
            &dictionary
        ) == noErr,
        let values = dictionary?.takeUnretainedValue() as? [String: Any] else { return nil }

        var metadata = blank(from: url)
        for (rawKey, rawValue) in values {
            let key = rawKey.lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
            let value = rawValue as? String ?? (rawValue as? NSNumber)?.stringValue
            guard let value, !value.isEmpty else { continue }
            switch key {
            case "title": metadata.title = value
            case "artist": metadata.artist = value
            case "album": metadata.album = value
            case "albumartist": metadata.albumArtist = value
            case "genre": metadata.genre = value
            case "composer": metadata.composer = value
            case "comment", "comments": metadata.comment = value
            case "year", "date": metadata.year = parseYear(from: value)
            case "track", "tracknumber":
                let pair = parseNumberPair(value)
                metadata.trackNumber = pair.number
                metadata.trackTotal = pair.total
            case "tracktotal", "totaltracks": metadata.trackTotal = Int(value) ?? 0
            case "disc", "discnumber":
                let pair = parseNumberPair(value)
                metadata.discNumber = pair.number
                metadata.discTotal = pair.total
            case "disctotal", "totaldiscs": metadata.discTotal = Int(value) ?? 0
            case "bpm", "tempo": metadata.beatsPerMinute = Int(value) ?? 0
            default: break
            }
        }
        return metadata
    }

    /// libFLAC is the final fallback for Vorbis comments and embedded pictures
    /// that AVFoundation and AudioToolbox do not expose consistently.
    private static func readViaFLACBridge(url: URL) -> AudioMetadata? {
        guard let decoder = url.withUnsafeFileSystemRepresentation({
            $0.flatMap(SBFLACOpen)
        }) else { return nil }
        defer { SBFLACClose(decoder) }

        var metadata = blank(from: url)
        func tag(_ key: String) -> String? {
            key.withCString { keyPointer in
                SBFLACTag(decoder, keyPointer).map(String.init(cString:))
            }
        }
        if let value = tag("TITLE") { metadata.title = value }
        if let value = tag("ARTIST") { metadata.artist = value }
        if let value = tag("ALBUM") { metadata.album = value }
        if let value = tag("ALBUMARTIST") { metadata.albumArtist = value }
        if let value = tag("GENRE") { metadata.genre = value }
        if let value = tag("COMPOSER") { metadata.composer = value }
        if let value = tag("COMMENT") { metadata.comment = value }
        if let value = tag("DATE") ?? tag("YEAR") {
            metadata.year = parseYear(from: value)
        }
        if let value = tag("TRACKNUMBER") ?? tag("TRACK") {
            let pair = parseNumberPair(value)
            metadata.trackNumber = pair.number
            metadata.trackTotal = pair.total
        }
        if let value = tag("TRACKTOTAL") ?? tag("TOTALTRACKS") { metadata.trackTotal = Int(value) ?? 0 }
        if let value = tag("DISCNUMBER") ?? tag("DISC") {
            let pair = parseNumberPair(value)
            metadata.discNumber = pair.number
            metadata.discTotal = pair.total
        }
        if let value = tag("DISCTOTAL") ?? tag("TOTALDISCS") { metadata.discTotal = Int(value) ?? 0 }
        if let value = tag("BPM") ?? tag("TEMPO") { metadata.beatsPerMinute = Int(value) ?? 0 }
        metadata.sampleRate = Int(SBFLACSampleRate(decoder))
        let totalFrames = SBFLACTotalFrames(decoder)
        if metadata.sampleRate > 0, totalFrames > 0 {
            metadata.duration = Double(totalFrames) / Double(metadata.sampleRate)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? Int64 {
                metadata.bitrate = Int(
                    (Double(size) * 8 / metadata.duration / 1_000).rounded()
                )
            }
        }
        if metadata.albumArtist == "Unknown Artist",
           metadata.artist != "Unknown Artist" {
            metadata.albumArtist = metadata.artist
        }
        var artworkSize = 0
        if let artwork = SBFLACArtwork(decoder, &artworkSize), artworkSize > 0 {
            metadata.artworkData = Data(bytes: artwork, count: artworkSize)
        }
        return metadata
    }

    // MARK: - BPM detection fallback

    /// Detect BPM by analyzing audio samples when no tag is present.
    /// Reads the first 30 seconds of audio via AVFoundation and passes
    /// mono float samples to aubio for tempo detection.
    public static func detectBPM(from url: URL) async -> Int {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return 0 }
        let descs = try? await track.load(.formatDescriptions)
        guard let desc = descs?.first,
              let audioDesc = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else { return 0 }

        let sampleRate = UInt32(audioDesc.pointee.mSampleRate)
        guard sampleRate > 0 else { return 0 }

        let maxDuration = CMTime(seconds: 30, preferredTimescale: 600)
        let duration = (try? await asset.load(.duration)) ?? maxDuration
        let readDuration = CMTimeMinimum(duration, maxDuration)

        guard let reader = try? AVAssetReader(asset: asset) else { return 0 }
        reader.timeRange = CMTimeRange(start: .zero, duration: readDuration)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)

        guard reader.startReading() else { return 0 }

        var samples: [Float] = []
        while reader.status == .reading {
            guard let buffer = output.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            if let dataPointer, length > 0 {
                let floatCount = length / MemoryLayout<Float>.size
                let floatPointer = UnsafeRawPointer(dataPointer).bindMemory(to: Float.self, capacity: floatCount)
                samples.append(contentsOf: UnsafeBufferPointer(start: floatPointer, count: floatCount))
            }
        }

        var monoSamples: [Float]
        let channels = Int(audioDesc.pointee.mChannelsPerFrame)
        if channels == 2 {
            monoSamples = [Float](repeating: 0, count: samples.count / 2)
            for i in 0..<monoSamples.count {
                monoSamples[i] = (samples[i * 2] + samples[i * 2 + 1]) * 0.5
            }
        } else {
            monoSamples = samples
        }

        guard !monoSamples.isEmpty else { return 0 }
        return monoSamples.withUnsafeBufferPointer { ptr in
            Int(SBAubioDetectBPM(sampleRate, ptr.baseAddress, UInt32(monoSamples.count)))
        }
    }

    // MARK: - Merge helpers

    private static func blank(from url: URL) -> AudioMetadata {
        AudioMetadata(
            title: url.deletingPathExtension().lastPathComponent,
            artist: "Unknown Artist",
            album: "Unknown Album",
            albumArtist: "Unknown Artist",
            genre: "",
            composer: "",
            comment: "",
            year: 0,
            trackNumber: 0,
            trackTotal: 0,
            discNumber: 0,
            discTotal: 0,
            beatsPerMinute: 0,
            duration: 0,
            bitrate: 0,
            sampleRate: 0,
            artworkData: nil
        )
    }

    private static func merge(_ source: AudioMetadata, into target: inout AudioMetadata) {
        if !source.title.isEmpty,
           !looksLikeFilenameTitle(source.title) || looksLikeFilenameTitle(target.title) {
            target.title = source.title
        }
        if source.artist != "Unknown Artist" { target.artist = source.artist }
        if source.album != "Unknown Album" { target.album = source.album }
        if source.albumArtist != "Unknown Artist" { target.albumArtist = source.albumArtist }
        if !source.genre.isEmpty { target.genre = source.genre }
        if !source.composer.isEmpty { target.composer = source.composer }
        if !source.comment.isEmpty { target.comment = source.comment }
        if source.year != 0 { target.year = source.year }
        if source.trackNumber != 0 { target.trackNumber = source.trackNumber }
        if source.trackTotal != 0 { target.trackTotal = source.trackTotal }
        if source.discNumber != 0 { target.discNumber = source.discNumber }
        if source.discTotal != 0 { target.discTotal = source.discTotal }
        if source.beatsPerMinute != 0 { target.beatsPerMinute = source.beatsPerMinute }
        if source.duration > 0 { target.duration = source.duration }
        if source.bitrate != 0 { target.bitrate = source.bitrate }
        if source.sampleRate != 0 { target.sampleRate = source.sampleRate }
        if let art = source.artworkData { target.artworkData = art }
    }

    /// Fill only empty/unknown fields from fallback (AVFoundation).
    private static func mergePreferringExisting(_ target: inout AudioMetadata, with fallback: AudioMetadata) {
        if looksLikeFilenameTitle(target.title), !looksLikeFilenameTitle(fallback.title) {
            target.title = fallback.title
        }
        if target.artist == "Unknown Artist", fallback.artist != "Unknown Artist" {
            target.artist = fallback.artist
        }
        if target.album == "Unknown Album", fallback.album != "Unknown Album" {
            target.album = fallback.album
        }
        if target.albumArtist == "Unknown Artist", fallback.albumArtist != "Unknown Artist" {
            target.albumArtist = fallback.albumArtist
        }
        if target.genre.isEmpty, !fallback.genre.isEmpty { target.genre = fallback.genre }
        if target.composer.isEmpty, !fallback.composer.isEmpty { target.composer = fallback.composer }
        if target.comment.isEmpty, !fallback.comment.isEmpty { target.comment = fallback.comment }
        if target.year == 0, fallback.year != 0 { target.year = fallback.year }
        if target.trackNumber == 0, fallback.trackNumber != 0 { target.trackNumber = fallback.trackNumber }
        if target.trackTotal == 0, fallback.trackTotal != 0 { target.trackTotal = fallback.trackTotal }
        if target.discNumber == 0, fallback.discNumber != 0 { target.discNumber = fallback.discNumber }
        if target.discTotal == 0, fallback.discTotal != 0 { target.discTotal = fallback.discTotal }
        if target.beatsPerMinute == 0, fallback.beatsPerMinute != 0 { target.beatsPerMinute = fallback.beatsPerMinute }
        if target.duration <= 0, fallback.duration > 0 { target.duration = fallback.duration }
        if target.bitrate == 0, fallback.bitrate != 0 { target.bitrate = fallback.bitrate }
        if target.sampleRate == 0, fallback.sampleRate != 0 { target.sampleRate = fallback.sampleRate }
        if target.artworkData == nil { target.artworkData = fallback.artworkData }
    }

    /// True for empty titles or rip-style names like "1-01 Ambitionz…".
    private static func looksLikeFilenameTitle(_ title: String) -> Bool {
        if title.isEmpty { return true }
        return title.range(of: #"^\d{1,2}-\d{2}\s"#, options: .regularExpression) != nil
    }

    private static func parseYear(from value: String) -> Int {
        let digits = value.prefix(4).filter(\.isNumber)
        return Int(String(digits)) ?? 0
    }

    private static func parseNumberPair(_ value: String) -> (number: Int, total: Int) {
        let parts = value.split(separator: "/", maxSplits: 1).map {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        return (parts.first ?? 0, parts.count > 1 ? parts[1] : 0)
    }
}
