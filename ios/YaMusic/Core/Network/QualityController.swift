import Foundation
import Observation

/// Decides which quality to ask the server for.
///
/// `preferred` is the user's choice for the current link (Wi-Fi vs cellular). With adaptive
/// quality on, `effective` drops below it while the link can't keep up (stalls, timeouts,
/// measured throughput too low for the bitrate) and climbs back as far as the link carries once the
/// link has measured healthy twice in a row. A link change to an unmetered network restores it at once.
@Observable
final class QualityController {
    private let settings: AppSettings
    private let network: NetworkMonitor

    /// Adaptive ceiling. `nil` = no downgrade in effect.
    private(set) var ceiling: AudioQuality?
    /// Smoothed download speed in kbit/s; `nil` until measured on the current link.
    private(set) var throughputKbps: Double?

    @ObservationIgnored private var holdUntil = Date.distantPast
    @ObservationIgnored private var healthySince: Date?
    @ObservationIgnored private var lastLink: NetworkMonitor.Link = .other

    init(settings: AppSettings, network: NetworkMonitor) {
        self.settings = settings
        self.network = network
        lastLink = network.link
    }

    /// The user's choice for the current link.
    var preferred: AudioQuality {
        let q = network.isExpensive || network.link == .cellular
            ? settings.streamQualityCellular : settings.streamQualityWiFi
        // Low Data Mode is an explicit "use less" from the user.
        return network.isConstrained ? min(q, .lq) : q
    }

    /// What to request right now.
    var effective: AudioQuality {
        guard settings.adaptiveQuality, let ceiling else { return preferred }
        return min(preferred, ceiling)
    }

    /// The link is holding quality below the user's choice.
    var isDegraded: Bool { effective < preferred }

    // MARK: Signals

    /// Playback ran out of buffered audio, or a chunk request timed out.
    func reportStall() {
        guard settings.adaptiveQuality else { return }
        healthySince = nil
        stepDown(hold: 45)
    }

    /// A throughput sample from an active audio download (bytes over wall time).
    /// `bitrateKbps` is the bitrate of the stream being fetched, when known.
    func reportThroughput(bytesPerSecond: Double, bitrateKbps: Double? = nil) {
        guard bytesPerSecond > 0 else { return }
        syncLink()
        let kbps = bytesPerSecond * 8 / 1000
        throughputKbps = throughputKbps.map { $0 * 0.7 + kbps * 0.3 } ?? kbps
        guard settings.adaptiveQuality, let speed = throughputKbps else { return }
        let now = Date()
        let current = effective
        // The API reports 0 for FLAC; treat it as unknown.
        let need = bitrateKbps.flatMap { $0 > 0 ? $0 : nil } ?? current.nominalKbps

        // Can't sustain the current level with headroom: drop.
        if speed < need * 1.3, current > .lq {
            healthySince = nil
            stepDown(hold: 30)
            return
        }
        // Comfortably above the next level, seen at least twice a few seconds apart: climb back
        // one step. (Samples can be sparse: on a fast link there is one per track.)
        guard isDegraded, let up = current.higher else { healthySince = nil; return }
        if speed > up.nominalKbps * 2.5 {
            guard let since = healthySince else { healthySince = now; return }
            if now.timeIntervalSince(since) >= 6, now >= holdUntil {
                // Go as high as the link comfortably carries, not just one step: a link that
                // came back at full speed should not need three tracks to get back to lossless.
                let best = AudioQuality.allCases.last { $0 <= preferred && speed > $0.nominalKbps * 2.5 } ?? up
                ceiling = best >= preferred ? nil : max(best, up)
                healthySince = nil
                holdUntil = now.addingTimeInterval(10)
            }
        } else {
            healthySince = nil
        }
    }

    /// The network path changed (call from an observer of `NetworkMonitor.generation`).
    func linkChanged() { syncLink() }

    /// Forget the downgrade (user changed settings, or wants to retry at full quality).
    func reset() {
        ceiling = nil
        healthySince = nil
        holdUntil = .distantPast
    }

    // MARK: Internals

    private func stepDown(hold: TimeInterval) {
        guard let lower = effective.lower else { return }
        ceiling = lower
        holdUntil = Date().addingTimeInterval(hold)
    }

    private func syncLink() {
        let link = network.link
        guard link != lastLink else { return }
        lastLink = link
        // Old measurements say nothing about the new link.
        throughputKbps = nil
        healthySince = nil
        if link == .wifi || link == .wired { reset() }
    }
}
