import Foundation
import SwiftData

public enum DefaultSmartPlaylists {
    public static let recentlyPlayedKey = "system.recentlyPlayed"
    public static let topRatedKey = "system.topRated"
    public static let neverPlayedKey = "system.neverPlayed"

    public static func ensureInstalled(in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<Playlist>())
        let keys = Set(existing.compactMap(\.systemKey).filter { !$0.isEmpty })
        var changed = false
        if let favorites = existing.first(where: { $0.systemKey == topRatedKey }) {
            let rules = try SmartPlaylistRuleSet(
                matchMode: .all,
                conditions: [SmartCondition(field: .favorite, op: .isSet, value: "")]
            ).encode()
            if favorites.name != "Favorites" {
                favorites.name = "Favorites"
                changed = true
            }
            if favorites.smartPlaylistRules != rules {
                favorites.smartPlaylistRules = rules
                changed = true
            }
        }

        if !keys.contains(recentlyPlayedKey) {
            try insert(
                name: "Recently Played",
                key: recentlyPlayedKey,
                rules: SmartPlaylistRuleSet(
                    matchMode: .all,
                    conditions: [
                        SmartCondition(field: .lastPlayed, op: .isSet, value: ""),
                        SmartCondition(field: .lastPlayed, op: .lessThan, value: "30"),
                    ]
                ),
                into: context
            )
            changed = true
        }
        if !keys.contains(topRatedKey) {
            try insert(
                name: "Favorites",
                key: topRatedKey,
                rules: SmartPlaylistRuleSet(
                    matchMode: .all,
                    conditions: [SmartCondition(field: .favorite, op: .isSet, value: "")]
                ),
                into: context
            )
            changed = true
        }
        if !keys.contains(neverPlayedKey) {
            try insert(
                name: "Never Played",
                key: neverPlayedKey,
                rules: SmartPlaylistRuleSet(
                    matchMode: .all,
                    conditions: [SmartCondition(field: .playCount, op: .equals, value: "0")]
                ),
                into: context
            )
            changed = true
        }
        if changed { try context.save() }
    }

    private static func insert(name: String, key: String, rules: SmartPlaylistRuleSet, into context: ModelContext) throws {
        let playlist = Playlist(name: name, smart: true, systemKey: key)
        playlist.smartPlaylistRules = try rules.encode()
        context.insert(playlist)
    }
}
