import CryptoKit
import Foundation

public struct AudioCDText: Sendable, Equatable {
    public let albumTitle: String?
    public let albumArtist: String?
    public let trackTitles: [Int: String]
    public let trackArtists: [Int: String]

    public static let empty = AudioCDText(
        albumTitle: nil,
        albumArtist: nil,
        trackTitles: [:],
        trackArtists: [:]
    )
}

public enum AudioCDTextParser {
    public static func parse(_ data: Data) -> AudioCDText {
        guard data.count >= 4 else { return .empty }
        var fields: [UInt8: [Int: Data]] = [:]
        var offset = 4
        while offset + 18 <= data.count {
            let pack = data[offset..<(offset + 18)]
            let type = pack[pack.startIndex]
            let track = Int(pack[pack.startIndex + 1])
            guard type == 0x80 || type == 0x81 else {
                offset += 18
                continue
            }
            fields[type, default: [:]][track, default: Data()]
                .append(contentsOf: pack[(pack.startIndex + 4)..<(pack.startIndex + 16)])
            offset += 18
        }

        func strings(for type: UInt8) -> [Int: String] {
            (fields[type] ?? [:]).compactMapValues { bytes in
                let prefix = bytes.prefix { $0 != 0 }
                let value = String(data: prefix, encoding: .isoLatin1)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value?.isEmpty == false ? value : nil
            }
        }
        let titles = strings(for: 0x80)
        let artists = strings(for: 0x81)
        return AudioCDText(
            albumTitle: titles[0],
            albumArtist: artists[0],
            trackTitles: titles.filter { $0.key > 0 },
            trackArtists: artists.filter { $0.key > 0 }
        )
    }
}

public enum MusicBrainzDiscID {
    public static func calculate(
        entries: [AudioCDTOCParser.Entry],
        leadOutSector: Int64
    ) -> String {
        let tracks = entries
            .filter { (1...99).contains($0.number) }
            .sorted { $0.number < $1.number }
        guard let first = tracks.first?.number, let last = tracks.last?.number else { return "" }
        let offsets = Dictionary(uniqueKeysWithValues: tracks.map { ($0.number, $0.startSector + 150) })
        var input = String(format: "%02X%02X%08X", first, last, leadOutSector + 150)
        for number in 1...99 {
            input += String(format: "%08X", offsets[number] ?? 0)
        }
        let digest = Insecure.SHA1.hash(data: Data(input.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: ".")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "-")
    }
}
