import Foundation
import SongbirdDockIconSupport

public enum SongbirdDockIconPreference {
    private static let storageKeyPrefix = "songbird.dockIcon"

    public static func migrateLegacyBlueMondaySourceChoiceIfNeeded(
        defaults: UserDefaults = .standard
    ) {
        guard defaults.string(forKey: SongbirdThemeID.storageKey)
                == SongbirdThemeID.legacyBlueMondaySourceRawValue
        else {
            return
        }
        let legacyKey = "\(storageKeyPrefix).\(SongbirdThemeID.legacyBlueMondaySourceRawValue)"
        guard let rawChoice = defaults.string(forKey: legacyKey),
              let choice = SongbirdDockIconChoice(rawValue: rawChoice),
              SongbirdThemeID.blueMonday.dockIconChoices.contains(choice)
        else {
            return
        }
        defaults.set(rawChoice, forKey: storageKey(for: .blueMonday))
        defaults.removeObject(forKey: legacyKey)
    }

    public static func storageKey(for theme: SongbirdThemeID) -> String {
        "\(storageKeyPrefix).\(theme.rawValue)"
    }

    public static func choice(
        for theme: SongbirdThemeID,
        defaults: UserDefaults = .standard
    ) -> SongbirdDockIconChoice? {
        guard let fallback = theme.defaultDockIconChoice else { return nil }
        let storedValue = defaults.string(forKey: storageKey(for: theme))
        guard let storedValue,
              let storedChoice = SongbirdDockIconChoice(rawValue: storedValue),
              theme.dockIconChoices.contains(storedChoice)
        else {
            return fallback
        }
        return storedChoice
    }

    public static func setChoice(
        _ choice: SongbirdDockIconChoice,
        for theme: SongbirdThemeID,
        defaults: UserDefaults = .standard
    ) {
        guard theme.dockIconChoices.contains(choice) else { return }
        defaults.set(choice.rawValue, forKey: storageKey(for: theme))
    }

    public static func activeResourceName(
        defaults: UserDefaults = .standard
    ) -> String? {
        SongbirdDockIconArtwork.validatedResourceName(
            defaults.string(forKey: SongbirdDockIconArtwork.activeResourceStorageKey)
        )
    }

    public static func setActiveChoice(
        _ choice: SongbirdDockIconChoice,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(
            choice.resourceName,
            forKey: SongbirdDockIconArtwork.activeResourceStorageKey
        )
    }

    public static func clearActiveChoice(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: SongbirdDockIconArtwork.activeResourceStorageKey)
    }
}
