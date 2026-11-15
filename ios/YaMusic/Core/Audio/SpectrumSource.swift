import Foundation
import os

/// What the analyser knows about one instant of the music. Everything is 0...1.
nonisolated struct SpectrumFrame: Sendable, Equatable {
    /// Band energies: x = bass, y = low-mid, z = high-mid, w = treble, each against its own recent peak.
    var bands = SIMD4<Float>.zero
    /// Low-end onset (kick, 808 hit): jumps on the hit and is gone within ~0.2 s.
    var kick: Float = 0
    /// High-end onset (snare, clap, hat).
    var snap: Float = 0
    /// Loudness against the track's own recent ceiling: low in intros and breakdowns, 1 in the drop.
    var level: Float = 0

    static let zero = SpectrumFrame()
}

/// Thread-safe timeline between the audio analyser and whatever draws it.
///
/// An audio tap sees samples well before they are heard (about half a second with `AVPlayer`,
/// in buffers of up to a few thousand frames), so the analyser stamps every result with the
/// media time it belongs to and the renderer asks for "what is sounding now" from its own
/// display link. That keeps the picture on the beat however the tap happens to chop the stream.
///
/// Deliberately *not* observable: publishing band energies through SwiftUI observation
/// re-rendered views at the audio rate.
///
/// The analyser only does its FFT while somebody is watching (`isWatched`), so audio in the
/// background / on the lock screen costs nothing extra.
nonisolated final class SpectrumSource: @unchecked Sendable {
    /// Where the playhead is. The player keeps it current.
    let clock = PlayheadClock()

    /// ~86 results a second: room for several seconds of tap lead.
    private static let capacity = 512
    /// A result older than this says nothing about the present (stall, analyser gone).
    private static let stale = 0.25
    /// Onsets are short: a reader that comes less often than they last still gets them,
    /// looking back this far at most.
    private static let onsetWindow = 0.1

    private struct State {
        var frames = [SpectrumFrame](repeating: .zero, count: SpectrumSource.capacity)
        var times = [Double](repeating: 0, count: SpectrumSource.capacity)
        var head = 0
        var count = 0
        var lastRead = -Double.infinity
        var watchers = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// What is being heard right now (`lead` seconds from now, to cover the display's own
    /// latency). Zero while playback is paused, stalled or not analysed.
    func snapshot(lead: Double = 0) -> SpectrumFrame {
        guard let now = clock.now else { return .zero }
        return frame(at: now + lead)
    }

    /// The newest result at or before `mediaTime`; its onsets are the strongest since the last read.
    func frame(at mediaTime: Double) -> SpectrumFrame {
        state.withLock { s in
            var out = SpectrumFrame.zero
            var found = false
            var k = s.count - 1
            while k >= 0 {
                let i = (s.head + k) % Self.capacity
                let t = s.times[i]
                k -= 1
                if t > mediaTime { continue }
                if !found {
                    guard mediaTime - t < Self.stale else { break }
                    out = s.frames[i]
                    found = true
                    continue
                }
                if t <= s.lastRead || mediaTime - t > Self.onsetWindow { break }
                out.kick = max(out.kick, s.frames[i].kick)
                out.snap = max(out.snap, s.frames[i].snap)
            }
            s.lastRead = mediaTime
            return out
        }
    }

    /// Called by the analyser (audio thread): `frame` describes the audio at `mediaTime`.
    func append(_ frame: SpectrumFrame, at mediaTime: Double) {
        state.withLock { s in
            if s.count == Self.capacity {
                s.head = (s.head + 1) % Self.capacity
                s.count -= 1
            }
            let i = (s.head + s.count) % Self.capacity
            s.frames[i] = frame
            s.times[i] = mediaTime
            s.count += 1
        }
    }

    /// Media time jumped (seek, new item): what is queued belongs to another place.
    func discard() {
        state.withLock { $0.count = 0; $0.head = 0; $0.lastRead = -.infinity }
    }

    /// True while at least one visualiser is on screen. Producers should skip their work otherwise.
    var isWatched: Bool { state.withLock { $0.watchers > 0 } }

    /// A visualiser came on screen. Balance with `endWatching()`.
    func beginWatching() { state.withLock { $0.watchers += 1 } }
    func endWatching() { state.withLock { $0.watchers = max(0, $0.watchers - 1) } }
}
