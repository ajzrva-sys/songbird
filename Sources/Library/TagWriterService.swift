import AVFoundation
import FLACBridge
import Foundation

/// Writes metadata tags back to audio files on disk.
///
/// FLAC files use the libFLAC metadata chain API via `FLACBridge`.
/// All other formats use `AVAssetExportSession` with passthrough preset.
public enum TagWriterService {

    // MARK: - Public API

    /// Write changed metadata fields to the audio file at `path`.
    ///
    /// `rating` and `favorite` are Songbird-internal and are silently skipped.
    public static func writeTags(
        path: String,
        fields: [TrackMetadataField: TrackMetadataValue],
        artworkData: Data? = nil,
        artworkCleared: Bool = false
    ) async throws {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "flac":
            try writeFLACTags(path: path, fields: fields, artworkData: artworkData, artworkCleared: artworkCleared)
        case "mp3", "m4a", "aac", "aiff", "aif", "wav":
            try await writeAVFoundationTags(
                path: path, fields: fields, artworkData: artworkData, artworkCleared: artworkCleared
            )
        default:
            throw TagWriterError.unsupportedFormat(path: path)
        }
    }

    // MARK: - FLAC (libFLAC metadata chain)

    private static func writeFLACTags(
        path: String,
        fields: [TrackMetadataField: TrackMetadataValue],
        artworkData: Data?,
        artworkCleared: Bool
    ) throws {
        var keys: [String] = []
        var values: [String] = []
        for (field, value) in fields.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let (key, val) = flacTag(field: field, value: value) else { continue }
            keys.append(key)
            values.append(val)
        }
        if !keys.isEmpty {
            let result = path.withCString { pathPtr in
                keys.withCStrings { keysCStr in
                    values.withCStrings { valuesCStr in
                        SBFLACWriteTags(pathPtr, keysCStr, valuesCStr, keys.count)
                    }
                }
            }
            if result != 0 {
                throw TagWriterError.flacWriteFailed(path: path)
            }
        }
        if let data = artworkData {
            try writeFLACArtwork(path: path, data: data)
        }
    }

    private static func writeFLACArtwork(path: String, data: Data) throws {
        let mime = artworkMIMEType(data: data)
        let result: Int32 = path.withCString { pathPtr in
            data.withUnsafeBytes { buffer in
                guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
                return mime.withCString { mimePtr in
                    SBFLACWriteArtwork(pathPtr, ptr, data.count, mimePtr)
                }
            }
        }
        if result != 0 {
            throw TagWriterError.flacWriteFailed(path: path)
        }
    }

    private static func flacTag(
        field: TrackMetadataField, value: TrackMetadataValue
    ) -> (key: String, value: String)? {
        switch (field, value) {
        case (.title, .text(let v)):       return ("TITLE", v)
        case (.artist, .text(let v)):      return ("ARTIST", v)
        case (.album, .text(let v)):       return ("ALBUM", v)
        case (.albumArtist, .text(let v)): return ("ALBUMARTIST", v)
        case (.genre, .text(let v)):       return ("GENRE", v)
        case (.composer, .text(let v)):    return ("COMPOSER", v)
        case (.comment, .text(let v)):     return ("COMMENT", v)
        case (.year, .number(let v)):      return v > 0 ? ("DATE", "\(v)") : nil
        case (.trackNumber, .number(let v)):
            return v > 0 ? ("TRACKNUMBER", "\(v)") : nil
        case (.trackTotal, .number(let v)):
            return v > 0 ? ("TRACKTOTAL", "\(v)") : nil
        case (.discNumber, .number(let v)):
            return v > 0 ? ("DISCNUMBER", "\(v)") : nil
        case (.discTotal, .number(let v)):
            return v > 0 ? ("DISCTOTAL", "\(v)") : nil
        case (.beatsPerMinute, .number(let v)):
            return v > 0 ? ("BPM", "\(v)") : nil
        case (.rating, _), (.favorite, _), (.artwork, _):
            return nil
        default:
            return nil
        }
    }

    // MARK: - Non-FLAC (AVFoundation passthrough export)

    private static func writeAVFoundationTags(
        path: String,
        fields: [TrackMetadataField: TrackMetadataValue],
        artworkData: Data?,
        artworkCleared: Bool
    ) async throws {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw TagWriterError.exportSessionUnavailable(path: path)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension((path as NSString).pathExtension)

        let metadata = try await buildAVMetadata(
            asset: asset, fields: fields, artworkData: artworkData, artworkCleared: artworkCleared
        )

        exportSession.outputURL = tempURL
        exportSession.outputFileType = fileType(for: path)
        exportSession.metadata = metadata

        await exportSession.export()

        guard exportSession.status == .completed else {
            try? FileManager.default.removeItem(at: tempURL)
            throw exportSession.error ?? TagWriterError.exportFailed(path: path)
        }

        do {
            try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    // MARK: - AVFoundation metadata construction

    private static func buildAVMetadata(
        asset: AVURLAsset,
        fields: [TrackMetadataField: TrackMetadataValue],
        artworkData: Data?,
        artworkCleared: Bool
    ) async throws -> [AVMetadataItem] {
        let existing = (try? await asset.load(.metadata)) ?? []

        // Build the set of (key, keySpace) pairs we are replacing
        let replacedPairs: Set<MetadataKeyPair> = Set(fields.keys.compactMap { field in
            guard let keyString = avMetadataKeyString(for: field),
                  let ks = avMetadataKeySpace(for: field) else { return nil }
            return MetadataKeyPair(key: keyString, keySpace: ks)
        })

        var keep = existing.filter { item in
            if item.commonKey == .commonKeyArtwork, artworkData != nil || artworkCleared {
                return false
            }
            if let key = item.key as? String, let ks = item.keySpace {
                if replacedPairs.contains(MetadataKeyPair(key: key, keySpace: ks)) {
                    return false
                }
            }
            return true
        }

        // Collect number pair values before building items
        let trackNumber = intField(.trackNumber, from: fields)
        let trackTotal = intField(.trackTotal, from: fields)
        let discNumber = intField(.discNumber, from: fields)
        let discTotal = intField(.discTotal, from: fields)

        // Build a single packed trkn item if either number or total is present
        if let num = trackNumber, num > 0 {
            let item = AVMutableMetadataItem()
            item.key = "trkn" as NSString
            item.keySpace = AVMetadataKeySpace.iTunes
            item.value = packNumberPair(number: num, total: trackTotal ?? 0) as NSData
            keep.append(item)
        }

        // Build a single packed disk item
        if let num = discNumber, num > 0 {
            let item = AVMutableMetadataItem()
            item.key = "disk" as NSString
            item.keySpace = AVMetadataKeySpace.iTunes
            item.value = packNumberPair(number: num, total: discTotal ?? 0) as NSData
            keep.append(item)
        }

        // Build remaining fields (skip track/disc number/total — handled above)
        for (field, value) in fields {
            switch field {
            case .trackNumber, .trackTotal, .discNumber, .discTotal:
                continue // handled by packed pairs above
            default:
                break
            }
            guard let item = avMetadataItem(field: field, value: value) else { continue }
            keep.append(item)
        }

        if artworkCleared {
            // already filtered out above
        } else if let data = artworkData {
            let item = AVMutableMetadataItem()
            item.key = AVMetadataKey.commonKeyArtwork as NSString
            item.keySpace = .common
            item.value = data as NSData
            item.dataType = artworkDataType(data: data)
            keep.append(item)
        }

        return keep
    }

    private static func intField(
        _ field: TrackMetadataField, from fields: [TrackMetadataField: TrackMetadataValue]
    ) -> Int? {
        if case .number(let v) = fields[field] { return v }
        return nil
    }

    /// Pack track/disc number + total into the 16-byte iTunes atom format.
    static func packNumberPair(number: Int, total: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[2] = UInt8((number >> 8) & 0xFF)
        bytes[3] = UInt8(number & 0xFF)
        bytes[4] = UInt8((total >> 8) & 0xFF)
        bytes[5] = UInt8(total & 0xFF)
        return Data(bytes)
    }

    private static func avMetadataItem(
        field: TrackMetadataField, value: TrackMetadataValue
    ) -> AVMutableMetadataItem? {
        let item = AVMutableMetadataItem()
        switch (field, value) {
        case (.title, .text(let v)):
            item.key = AVMetadataKey.commonKeyTitle as NSString
            item.keySpace = .common
            item.value = v as NSString
        case (.artist, .text(let v)):
            item.key = AVMetadataKey.commonKeyArtist as NSString
            item.keySpace = .common
            item.value = v as NSString
        case (.album, .text(let v)):
            item.key = AVMetadataKey.commonKeyAlbumName as NSString
            item.keySpace = .common
            item.value = v as NSString
        case (.albumArtist, .text(let v)):
            item.key = "aart" as NSString
            item.keySpace = AVMetadataKeySpace.iTunes
            item.value = v as NSString
        case (.genre, .text(let v)):
            item.key = "©gen" as NSString
            item.keySpace = AVMetadataKeySpace.iTunes
            item.value = v as NSString
        case (.composer, .text(let v)):
            item.key = "©wrt" as NSString
            item.keySpace = AVMetadataKeySpace.iTunes
            item.value = v as NSString
        case (.comment, .text(let v)):
            item.key = AVMetadataKey.commonKeyDescription as NSString
            item.keySpace = .common
            item.value = v as NSString
        case (.year, .number(let v)):
            guard v > 0 else { return nil }
            item.key = AVMetadataKey.commonKeyCreationDate as NSString
            item.keySpace = .common
            item.value = "\(v)" as NSString
        case (.beatsPerMinute, .number(let v)):
            guard v > 0 else { return nil }
            item.key = "tmpo" as NSString
            item.keySpace = AVMetadataKeySpace.iTunes
            item.value = v as NSNumber
        case (.rating, _), (.favorite, _), (.artwork, _):
            return nil
        default:
            return nil
        }
        return item
    }

    // MARK: - Key/keySpace helpers

    private static func avMetadataKeyString(for field: TrackMetadataField) -> String? {
        switch field {
        case .title:       return AVMetadataKey.commonKeyTitle.rawValue
        case .artist:      return AVMetadataKey.commonKeyArtist.rawValue
        case .album:       return AVMetadataKey.commonKeyAlbumName.rawValue
        case .albumArtist: return "aart"
        case .genre:       return "©gen"
        case .composer:    return "©wrt"
        case .comment:     return AVMetadataKey.commonKeyDescription.rawValue
        case .year:        return AVMetadataKey.commonKeyCreationDate.rawValue
        case .trackNumber, .trackTotal: return "trkn"
        case .discNumber, .discTotal:   return "disk"
        case .beatsPerMinute:           return "tmpo"
        default:           return nil
        }
    }

    private static func avMetadataKeySpace(for field: TrackMetadataField) -> AVMetadataKeySpace? {
        switch field {
        case .title, .artist, .album, .comment, .year:
            return .common
        case .albumArtist, .genre, .composer,
             .trackNumber, .trackTotal, .discNumber, .discTotal, .beatsPerMinute:
            return AVMetadataKeySpace.iTunes
        default:
            return nil
        }
    }

    // MARK: - Format helpers

    private static func fileType(for path: String) -> AVFileType {
        switch (path as NSString).pathExtension.lowercased() {
        case "mp3":         return .mp3
        case "m4a", "aac":  return .m4a
        case "aiff", "aif": return .aiff
        case "wav":         return .wav
        default:            return .m4a // unreachable due to caller guard
        }
    }

    private static func artworkMIMEType(data: Data) -> String {
        guard data.count >= 4 else { return "image/jpeg" }
        let bytes = [UInt8](data.prefix(4))
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "image/png"
        }
        return "image/jpeg"
    }

    private static func artworkDataType(data: Data) -> String {
        guard data.count >= 4 else { return kCMMetadataBaseDataType_JPEG as String }
        let bytes = [UInt8](data.prefix(4))
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return kCMMetadataBaseDataType_PNG as String
        }
        return kCMMetadataBaseDataType_JPEG as String
    }
}

// MARK: - MetadataKeyPair (for filtering)

private struct MetadataKeyPair: Hashable {
    let key: String
    let keySpace: AVMetadataKeySpace
}

// MARK: - Errors

public enum TagWriterError: LocalizedError {
    case flacWriteFailed(path: String)
    case exportSessionUnavailable(path: String)
    case exportFailed(path: String)
    case unsupportedFormat(path: String)

    public var errorDescription: String? {
        switch self {
        case .flacWriteFailed(let path):
            return "Failed to write FLAC tags to \(path)."
        case .exportSessionUnavailable(let path):
            return "Export session unavailable for \(path)."
        case .exportFailed(let path):
            return "Tag export failed for \(path)."
        case .unsupportedFormat(let path):
            return "Tag writing is not supported for \((path as NSString).pathExtension.uppercased()) files."
        }
    }
}

// MARK: - C String Array Bridging

extension Array where Element == String {
    /// Execute `body` with an array of C string pointers. Each pointer is
    /// valid only for the duration of the call.
    func withCStrings<R>(_ body: (UnsafePointer<UnsafePointer<CChar>?>) -> R) -> R {
        func recurse(index: Int, pointers: [UnsafePointer<CChar>?], body: (UnsafePointer<UnsafePointer<CChar>?>) -> R) -> R {
            if index >= self.count {
                return pointers.withUnsafeBufferPointer { buf in
                    buf.baseAddress!.withMemoryRebound(
                        to: UnsafePointer<CChar>?.self,
                        capacity: pointers.count
                    ) { body($0) }
                }
            }
            return self[index].withCString { cStr in
                recurse(index: index + 1, pointers: pointers + [cStr], body: body)
            }
        }
        return recurse(index: 0, pointers: [], body: body)
    }
}
