import Foundation

enum PlayerToolbarItem: String, CaseIterable, Codable, Identifiable {
    case previous
    case playPause
    case next
    case volume
    case shuffle
    case repeatMode
    case flexibleSpace
    case faceplate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .previous: return "Previous"
        case .playPause: return "Play"
        case .next: return "Next"
        case .volume: return "Volume"
        case .shuffle: return "Shuffle"
        case .repeatMode: return "Repeat"
        case .flexibleSpace: return "Flexible Space"
        case .faceplate: return "Now Playing"
        }
    }

    var systemImage: String {
        switch self {
        case .previous: return "backward.fill"
        case .playPause: return "play.fill"
        case .next: return "forward.fill"
        case .volume: return "speaker.wave.2.fill"
        case .shuffle: return "shuffle"
        case .repeatMode: return "repeat"
        case .flexibleSpace: return "arrow.left.and.right"
        case .faceplate: return "music.note"
        }
    }
}

enum PlayerToolbarLayout {
    static let storageKey = "nowPlaying.toolbarItems"

    static let defaults: [PlayerToolbarItem] = [
        .previous,
        .playPause,
        .next,
        .volume,
        .shuffle,
        .repeatMode,
        .flexibleSpace,
        .faceplate,
    ]

    static func encode(_ items: [PlayerToolbarItem]) -> String {
        guard let data = try? JSONEncoder().encode(items),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    static func decode(_ raw: String) -> [PlayerToolbarItem] {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([PlayerToolbarItem].self, from: data)
        else {
            return defaults
        }
        let unique = decoded.reduce(into: [PlayerToolbarItem]()) { result, item in
            if !result.contains(item) {
                result.append(item)
            }
        }
        return unique.contains(.faceplate) ? unique : defaults
    }
}
