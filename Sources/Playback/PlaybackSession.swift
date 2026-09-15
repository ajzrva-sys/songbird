import Foundation
import Combine

/// Owns the shared playback queue + engine for the app lifetime.
@MainActor
public final class PlaybackSession: ObservableObject {
    public let queue: PlaybackQueue
    public let engine: PlaybackEngine
    public let audioOutput: AudioOutputController

    public var clock: PlaybackClock { engine.clock }
    public var volumeState: PlaybackVolumeState { engine.volumeState }
    public var presentation: PlaybackPresentationState { engine.presentation }

    public init(
        backend: (any PlayerBackend)? = nil,
        pathResolver: FilesystemPathResolver = FilesystemPathResolver()
    ) {
        let queue = PlaybackQueue()
        self.queue = queue
        if let backend {
            self.engine = PlaybackEngine(
                queue: queue,
                backend: backend,
                pathResolver: pathResolver
            )
            self.audioOutput = backend.audioOutput ?? AudioOutputController()
        } else {
            let backend = NativeAudioBackend()
            self.engine = PlaybackEngine(
                queue: queue,
                backend: backend,
                pathResolver: pathResolver
            )
            self.audioOutput = backend.audioOutput ?? AudioOutputController()
        }
    }

    @discardableResult
    public func startReplacement(
        _ request: PlaybackStartRequest
    ) -> Result<Void, PlaybackStartError> {
        guard request.tracks.isEmpty == false else { return .failure(.emptySelection) }

        var tracks = request.tracks
        let startingAt: Int
        if request.randomizesTracks {
            tracks.shuffle()
            startingAt = 0
        } else {
            startingAt = request.startingAt
        }
        guard tracks.indices.contains(startingAt) else { return .failure(.emptySelection) }
        let first = tracks[startingAt]
        return engine.play(first) { [queue] in
            _ = queue.replace(with: tracks, startingAt: startingAt)
        }
    }

    @discardableResult
    public func startReplacementResolving(
        _ request: PlaybackStartRequest
    ) async -> Result<Void, PlaybackStartError> {
        guard request.tracks.isEmpty == false else { return .failure(.emptySelection) }
        var tracks = request.tracks
        let startingAt: Int
        if request.randomizesTracks {
            tracks.shuffle()
            startingAt = 0
        } else {
            startingAt = request.startingAt
        }
        guard tracks.indices.contains(startingAt) else { return .failure(.emptySelection) }
        let first = tracks[startingAt]
        return await engine.playResolving(first) { [queue] in
            _ = queue.replace(with: tracks, startingAt: startingAt)
        }
    }

    @discardableResult
    public func playOccurrence(
        entryID: PlaybackQueueEntry.ID
    ) -> Result<Void, PlaybackStartError> {
        if queue.currentEntry?.id == entryID {
            return restartCurrent()
        }
        guard let entry = queue.upcomingEntries.first(where: { $0.id == entryID }) else {
            return .failure(.emptySelection)
        }
        return engine.play(entry.track) { [queue] in
            _ = queue.promote(entryID: entry.id)
        }
    }

    @discardableResult
    public func playOccurrenceResolving(
        entryID: PlaybackQueueEntry.ID
    ) async -> Result<Void, PlaybackStartError> {
        if queue.currentEntry?.id == entryID {
            guard let track = queue.currentTrack else { return .failure(.emptySelection) }
            return await engine.playResolving(track)
        }
        guard let entry = queue.upcomingEntries.first(where: { $0.id == entryID }) else {
            return .failure(.emptySelection)
        }
        return await engine.playResolving(entry.track) { [queue] in
            _ = queue.promote(entryID: entry.id)
        }
    }

    @discardableResult
    public func restartCurrent() -> Result<Void, PlaybackStartError> {
        guard let track = queue.currentTrack else { return .failure(.emptySelection) }
        return engine.play(track)
    }

    @discardableResult
    public func playTrackNow(_ track: Track) -> Result<Void, PlaybackStartError> {
        if queue.currentTrack?.id == track.id {
            return restartCurrent()
        }
        if let queued = queue.displayedUpcomingEntries.first(where: { $0.track.id == track.id }) {
            return playOccurrence(entryID: queued.id)
        }
        return engine.play(track) { [queue] in
            _ = queue.promote(track)
        }
    }

    @discardableResult
    public func playTrackNowResolving(_ track: Track) async -> Result<Void, PlaybackStartError> {
        if queue.currentTrack?.id == track.id {
            return await engine.playResolving(track)
        }
        if let queued = queue.displayedUpcomingEntries.first(where: { $0.track.id == track.id }) {
            return await engine.playResolving(queued.track) { [queue] in
                _ = queue.promote(entryID: queued.id)
            }
        }
        return await engine.playResolving(track) { [queue] in
            _ = queue.promote(track)
        }
    }

    @discardableResult
    public func playNext(entryID: PlaybackQueueEntry.ID) -> Bool {
        queue.moveNext(entryID: entryID)
    }
}
