import Foundation
import Synchronization

/// Where the playhead is, readable from the audio thread without a lock.
///
/// An audio tap sees samples well before they are heard (about half a second with `AVPlayer`),
/// so the analyser must hold its results until the playhead reaches them. The player sets the
/// mapping on state changes (play, pause, seek, stall); in between the playhead just follows
/// the host clock.
nonisolated final class PlayheadClock: Sendable {
    private static let stopped = Int64.min
    /// Media time minus host uptime, in nanoseconds; `stopped` while nothing is sounding.
    private let offset = Atomic<Int64>(stopped)

    /// Playback is running at normal speed and is at `mediaTime` right now.
    func run(from mediaTime: TimeInterval) {
        guard mediaTime.isFinite, abs(mediaTime) < 1e7 else { stop(); return }
        offset.store(Int64(mediaTime * 1e9) - Self.uptime(), ordering: .relaxed)
    }

    /// Playback is paused, stalled, seeking or over.
    func stop() { offset.store(Self.stopped, ordering: .relaxed) }

    /// Media time being heard right now, in seconds; `nil` while stopped.
    var now: Double? {
        let o = offset.load(ordering: .relaxed)
        guard o != Self.stopped else { return nil }
        return Double(o + Self.uptime()) / 1e9
    }

    private static func uptime() -> Int64 { Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) }
}
