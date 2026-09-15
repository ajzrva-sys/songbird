import Foundation
import MediaPlayer
import AppKit

/// Wires hardware media keys / Control Center to PlaybackEngine and publishes Now Playing info.
@MainActor
public final class NowPlayingCommandCenter {
    private weak var engine: PlaybackEngine?
    private var lastArtworkTrackID: UUID?
    private var lastArtworkReference: ArtworkReference?
    private var artworkTask: Task<Void, Never>?

    public init() {}

    public func attach(engine: PlaybackEngine) {
        self.engine = engine
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.engine?.playIfPossible()
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.engine?.pauseIfPlaying()
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.engine?.togglePlayPause()
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.engine?.playNext()
            }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.engine?.playPrevious()
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                self?.engine?.seekTo(event.positionTime)
            }
            return .success
        }

        updateNowPlaying()
    }

    public func updateNowPlaying(forceArtwork: Bool = false) {
        guard let engine else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        guard let track = engine.queue.currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            lastArtworkTrackID = nil
            artworkTask?.cancel()
            artworkTask = nil
            return
        }

        let metadata = Self.metadata(for: track)
        let reference = Self.artworkReference(for: track)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: metadata.title.isEmpty ? "Unknown" : metadata.title,
            MPMediaItemPropertyArtist: metadata.artist,
            MPMediaItemPropertyAlbumTitle: metadata.album,
            MPMediaItemPropertyPlaybackDuration: engine.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: engine.position,
            MPNowPlayingInfoPropertyPlaybackRate: engine.status == .playing ? 1.0 : 0.0,
        ]

        let needsArt = forceArtwork || lastArtworkTrackID != track.id || lastArtworkReference != reference
        if needsArt {
            lastArtworkTrackID = track.id
            lastArtworkReference = reference
            artworkTask?.cancel()
            artworkTask = loadArtwork(for: track)
        } else if reference != nil, let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] {
            info[MPMediaItemPropertyArtwork] = existing
        }

        MPNowPlayingInfoCenter.default().playbackState =
            engine.status == .playing ? .playing
            : engine.status == .paused ? .paused
            : .stopped
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for track: Track) -> Task<Void, Never>? {
        guard let reference = Self.artworkReference(for: track) else { return nil }
        let trackID = track.id
        return Task { @MainActor [weak self] in
            guard let image = await ArtworkThumbnailService.shared.image(
                for: reference,
                pointSize: CGSize(width: 512, height: 512),
                scale: 1
            ), Task.isCancelled == false,
               self?.engine?.queue.currentTrack?.id == trackID,
               Self.artworkReference(for: track) == reference else { return }
            let size = NSSize(width: image.width, height: image.height)
            let nsImage = NSImage(cgImage: image, size: size)
            let artwork = MPMediaItemArtwork(boundsSize: size) { _ in nsImage }
            var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            current[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = current
        }
    }

    static func metadata(for track: Track) -> AudioCDTrackMetadata {
        if track.audioCDDiscogsEvidence != nil {
            return track.audioCDOriginalMetadata ?? .defaultMetadata(trackNumber: track.trackNumber)
        }
        return AudioCDTrackMetadata(title: track.title, artist: track.artist, album: track.album)
    }

    static func artworkReference(for track: Track) -> ArtworkReference? {
        guard track.audioCDDiscogsEvidence == nil else { return nil }
        return ArtworkReference.resolved(for: track)
    }
}
