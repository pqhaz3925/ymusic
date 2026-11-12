import Foundation
import os

/// Thread-safe mailbox between the audio analyser and whatever draws it.
///
/// Deliberately *not* observable: publishing band energies through SwiftUI observation
/// re-rendered views at the audio rate. The wave renderer polls `snapshot()` from its own
/// display link instead, and nobody else is woken up.
///
/// The analyser only does its FFT while somebody is watching (`isWatched`), so audio in the
/// background / on the lock screen costs nothing extra.
nonisolated final class SpectrumSource: @unchecked Sendable {
    private struct State {
        var bands = SIMD4<Float>.zero
        var watchers = 0
        var stamp: UInt64 = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Latest band energies, 0...1: x = bass, y = low-mid, z = high-mid, w = treble.
    /// Returns zero when nothing has been published for ~0.3 s (playback paused or stalled).
    func snapshot() -> SIMD4<Float> {
        let now = DispatchTime.now().uptimeNanoseconds
        return state.withLock { now &- $0.stamp > 300_000_000 ? .zero : $0.bands }
    }

    /// Called by the analyser (any thread).
    func publish(_ bands: SIMD4<Float>) {
        let now = DispatchTime.now().uptimeNanoseconds
        state.withLock { $0.bands = bands; $0.stamp = now }
    }

    /// True while at least one visualiser is on screen. Producers should skip their work otherwise.
    var isWatched: Bool { state.withLock { $0.watchers > 0 } }

    /// A visualiser came on screen. Balance with `endWatching()`.
    func beginWatching() { state.withLock { $0.watchers += 1 } }
    func endWatching() { state.withLock { $0.watchers = max(0, $0.watchers - 1) } }
}
