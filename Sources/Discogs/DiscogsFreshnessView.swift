import AppKit
import SwiftUI

/// One clock/timer per loaded surface, never one per candidate row.
@MainActor
struct DiscogsFreshnessView<Content: View>: View {
    private let clock: () -> DiscogsFetchStamp?
    private let onTick: (DiscogsFetchStamp?) -> Void
    private let content: () -> Content

    init(clock: @escaping () -> DiscogsFetchStamp? = DiscogsClock.sample,
         onTick: @escaping (DiscogsFetchStamp?) -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.clock = clock
        self.onTick = onTick
        self.content = content
    }

    var body: some View {
        content()
            .task {
                onTick(clock())
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) }
                    catch { return }
                    onTick(clock())
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                onTick(clock())
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                onTick(clock())
            }
    }
}
