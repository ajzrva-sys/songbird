import AppKit
import Combine
import SwiftUI

/// One sampled clock for transient playback presentation, independent of audio callbacks.
@MainActor
final class DiscogsPresentationClock: ObservableObject {
    static let shared = DiscogsPresentationClock()
    @Published private(set) var now: DiscogsFetchStamp?
    private let sample: () -> DiscogsFetchStamp?
    private var task: Task<Void, Never>?
    private var observations: [AnyCancellable] = []

    init(sample: @escaping () -> DiscogsFetchStamp? = DiscogsClock.sample,
         startsTimer: Bool = true) {
        self.sample = sample
        now = sample()
        guard startsTimer else { return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                self?.refresh()
            }
        }
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.refresh() } }
            .store(in: &observations)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.refresh() } }
            .store(in: &observations)
    }

    deinit { task?.cancel() }
    func refresh() { now = sample() }
}

extension ArtworkReference {
    var discogsEvidence: DiscogsContentEvidence? {
        if case .discogsRemote(_, let evidence) = self { return evidence }
        return nil
    }

    func isAvailable(at now: DiscogsFetchStamp?) -> Bool {
        discogsEvidence?.isFresh(at: now) ?? true
    }
}

extension AudioDisc {
    var artworkReference: ArtworkReference? {
        artworkURL.map { url in
            if let discogsEvidence { return .discogsRemote(url, evidence: discogsEvidence) }
            return .remote(url)
        }
    }
}

@MainActor
struct DiscogsTrackAttributionView: View {
    let track: Track
    let now: DiscogsFetchStamp?
    var body: some View {
        if let evidence = track.audioCDDiscogsEvidence, evidence.isFresh(at: now), let page = evidence.sourcePageURL {
            DiscogsAttributionView(sourcePageURL: page)
        }
    }
}
