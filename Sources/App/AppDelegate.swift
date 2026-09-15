import Cocoa
import AVFoundation
import UniformTypeIdentifiers
import SongbirdLib

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by SongbirdApp so Dock menu / open-URLs can reach playback.
    var session: PlaybackSession?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        Task { @MainActor in
            LibraryFolderWatcher.shared.applySettingsFromDefaults()
        }
    }

    /// Keep mini as the sole visible player when the Dock icon is clicked.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if PlayerWindowMode.isMiniMode {
            if let mini = PlayerWindowMode.miniWindows().first {
                mini.makeKeyAndOrderFront(nil)
            } else {
                NotificationCenter.default.post(name: .openMiniPlayer, object: nil)
            }
            return false
        }
        if !flag {
            for window in PlayerWindowMode.mainWindows() {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    @objc func systemWillSleep(_ notification: Notification) {
        NotificationCenter.default.post(name: .systemWillSleep, object: nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        session?.engine.prepareForTermination()
        return .terminateNow
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .filesWereOpened,
                object: nil,
                userInfo: ["urls": urls]
            )
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let repeatItem = NSMenuItem(title: repeatMenuTitle, action: #selector(dockCycleRepeat), keyEquivalent: "")
        repeatItem.target = self
        menu.addItem(repeatItem)

        let shuffleItem = NSMenuItem(title: shuffleMenuTitle, action: #selector(dockToggleShuffle), keyEquivalent: "")
        shuffleItem.target = self
        menu.addItem(shuffleItem)

        menu.addItem(.separator())

        let playPause = NSMenuItem(
            title: "Play/Pause",
            action: #selector(dockPlayPause),
            keyEquivalent: ""
        )
        playPause.target = self
        menu.addItem(playPause)

        let next = NSMenuItem(title: "Next Track", action: #selector(dockNext), keyEquivalent: "")
        next.target = self
        menu.addItem(next)

        let previous = NSMenuItem(title: "Previous Track", action: #selector(dockPrevious), keyEquivalent: "")
        previous.target = self
        menu.addItem(previous)

        menu.addItem(.separator())

        let miniTitle = PlayerWindowMode.isMiniMode ? "Show Full Player" : "Switch to Mini Player"
        let mini = NSMenuItem(title: miniTitle, action: #selector(dockMiniPlayer), keyEquivalent: "")
        mini.target = self
        menu.addItem(mini)

        return menu
    }

    @objc private func dockPlayPause() {
        session?.engine.togglePlayPause()
    }

    @objc private func dockNext() {
        session?.engine.playNext()
    }

    @objc private func dockPrevious() {
        session?.engine.playPrevious()
    }

    @objc private func dockMiniPlayer() {
        Task { @MainActor in
            if PlayerWindowMode.isMiniMode {
                NotificationCenter.default.post(name: .showMainPlayer, object: nil)
            } else {
                NotificationCenter.default.post(name: .openMiniPlayer, object: nil)
            }
        }
    }

    @objc private func dockCycleRepeat() {
        session?.engine.cycleRepeatMode()
    }

    @objc private func dockToggleShuffle() {
        session?.engine.queue.shuffleEnabled.toggle()
    }

    private var repeatMenuTitle: String {
        guard let mode = session?.engine.queue.repeatMode else { return "Repeat" }
        switch mode {
        case .off: return "Repeat: Off"
        case .all: return "Repeat: All"
        case .one: return "Repeat: One"
        }
    }

    private var shuffleMenuTitle: String {
        guard let on = session?.engine.queue.shuffleEnabled else { return "Shuffle" }
        return on ? "Shuffle: On" : "Shuffle: Off"
    }

    @IBAction func openFiles(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = supportedExtensions.compactMap { ext in
            UTType(filenameExtension: ext)
        }

        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .filesWereOpened,
                    object: nil,
                    userInfo: ["urls": urls]
                )
            }
        }
    }
}
