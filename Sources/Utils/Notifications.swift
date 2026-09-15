import Foundation

public extension Notification.Name {
    static let systemWillSleep = Notification.Name("songbird.systemWillSleep")
    static let filesWereOpened = Notification.Name("songbird.filesWereOpened")
    static let openMiniPlayer = Notification.Name("songbird.openMiniPlayer")
    static let showMainPlayer = Notification.Name("songbird.showMainPlayer")
    static let playbackDidFinish = Notification.Name("songbird.playbackDidFinish")
    static let selectAllTracks = Notification.Name("songbird.selectAllTracks")
    static let toggleColumnVisibility = Notification.Name("songbird.toggleColumnVisibility")
    static let resetTrackColumns = Notification.Name("songbird.resetTrackColumns")
    static let showAbout = Notification.Name("songbird.showAbout")
    static let focusTrackSearch = Notification.Name("songbird.focusTrackSearch")
    static let showLyrics = Notification.Name("songbird.showLyrics")
}
