import Foundation
import MediaPlayer
#if canImport(UIKit)
import UIKit
private typealias ArtworkImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias ArtworkImage = NSImage
#endif

/// Lock screen / Control Center (macOS: Now Playing widget, media keys) integration:
/// Now Playing info and remote commands.
final class NowPlaying {
    /// Actions the remote commands trigger. Each one runs on the main actor.
    struct Commands {
        var play: @MainActor () -> Void
        var pause: @MainActor () -> Void
        var toggle: @MainActor () -> Void
        var next: @MainActor () -> Void
        var previous: @MainActor () -> Void
        var seek: @MainActor (TimeInterval) -> Void
        var like: @MainActor () -> Void
        var dislike: @MainActor () -> Void
    }

    private var artworkTrackId: String?
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?

    // MARK: Remote commands

    func install(_ c: Commands) {
        let center = MPRemoteCommandCenter.shared()

        func add(_ cmd: MPRemoteCommand, _ action: @escaping @MainActor () -> Void) {
            cmd.isEnabled = true
            // Handlers fire on an arbitrary thread: stay nonisolated, hop to the main actor.
            cmd.addTarget { @Sendable _ in
                Task { @MainActor in action() }
                return .success
            }
        }

        add(center.playCommand, c.play)
        add(center.pauseCommand, c.pause)
        add(center.togglePlayPauseCommand, c.toggle)
        add(center.nextTrackCommand, c.next)
        add(center.previousTrackCommand, c.previous)
        add(center.likeCommand, c.like)
        add(center.dislikeCommand, c.dislike)
        center.likeCommand.localizedTitle = "Нравится"
        center.dislikeCommand.localizedTitle = "Не нравится"
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false

        let seek = c.seek
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { @Sendable event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            Task { @MainActor in seek(t) }
            return .success
        }
    }

    // MARK: Info

    /// Call on state changes only (track, play/pause, seek, buffering). The system extrapolates
    /// elapsed time from the rate, so there is nothing to refresh in between.
    func update(track: Track?, elapsed: TimeInterval, duration: TimeInterval, playing: Bool) {
        let center = MPNowPlayingInfoCenter.default()
        guard let track else {
            artworkTask?.cancel()
            artworkTrackId = nil
            artwork = nil
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var d: [String: Any] = [
            MPMediaItemPropertyTitle: track.fullTitle,
            MPMediaItemPropertyArtist: track.artistLine,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if artworkTrackId == track.id {
            if let artwork { d[MPMediaItemPropertyArtwork] = artwork }
        } else {
            loadArtwork(for: track)
        }
        center.nowPlayingInfo = d
        // Ignored on iOS (the audio session decides there); what macOS shows.
        center.playbackState = playing ? .playing : .paused
    }

    // MARK: Artwork

    private func loadArtwork(for track: Track) {
        artworkTask?.cancel()
        artworkTrackId = track.id
        artwork = nil
        guard let url = track.coverURL(600) else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled, let art = Self.makeArtwork(data),
                  let self, self.artworkTrackId == track.id else { return }
            self.artwork = art
            let center = MPNowPlayingInfoCenter.default()
            var info = center.nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = art
            center.nowPlayingInfo = info
        }
    }

    /// Built off the main actor: MediaPlayer calls the request handler on its own queue.
    nonisolated private static func makeArtwork(_ data: Data) -> MPMediaItemArtwork? {
        guard let image = ArtworkImage(data: data) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
