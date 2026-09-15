import Foundation

/// UserDefaults keys for playback preferences.
public enum PlaybackSettings {
    public static let volumeLimitKey = "playback.volumeLimit"
    public static let resumeOnLaunchKey = "playback.resumeOnLaunch"
    public static let rememberPositionKey = "playback.rememberPosition"
    public static let crossfadeSecondsKey = "playback.crossfadeSeconds"
    public static let lastTrackPathKey = "playback.lastTrackPath"
    public static let lastTrackIDKey = "playback.lastTrackID"
    public static let lastTrackPositionKey = "playback.lastTrackPosition"
    public static let stopAfterCurrentKey = "playback.stopAfterCurrent"
    public static let sleepTimerMinutesKey = "playback.sleepTimerMinutes"

    public static var volumeLimit: Double {
        get {
            let v = UserDefaults.standard.object(forKey: volumeLimitKey) as? Double
            return min(1.0, max(0.5, v ?? 1.0))
        }
        set { UserDefaults.standard.set(min(1.0, max(0.5, newValue)), forKey: volumeLimitKey) }
    }

    public static var resumeOnLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: resumeOnLaunchKey) }
        set { UserDefaults.standard.set(newValue, forKey: resumeOnLaunchKey) }
    }

    public static var rememberPosition: Bool {
        get { UserDefaults.standard.bool(forKey: rememberPositionKey) }
        set { UserDefaults.standard.set(newValue, forKey: rememberPositionKey) }
    }

    public static var crossfadeSeconds: Double {
        get { UserDefaults.standard.double(forKey: crossfadeSecondsKey) }
        set { UserDefaults.standard.set(max(0, min(12, newValue)), forKey: crossfadeSecondsKey) }
    }

    public static var stopAfterCurrent: Bool {
        get { UserDefaults.standard.bool(forKey: stopAfterCurrentKey) }
        set { UserDefaults.standard.set(newValue, forKey: stopAfterCurrentKey) }
    }
}
