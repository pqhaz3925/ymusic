import Foundation
import Observation

/// How lively the "My Wave" backdrop is. Lower modes exist purely to save battery.
nonisolated enum WaveMotion: String, CaseIterable, Codable, Sendable, Identifiable {
    case full, eco, still
    var id: Self { self }
    var title: String {
        switch self {
        case .full: "Полная"
        case .eco: "Экономная"
        case .still: "Статичная"
        }
    }
}

/// User preferences, persisted in `UserDefaults` as one JSON blob.
///
/// Every property is a computed view over `values`, so SwiftUI observation and `@Bindable`
/// bindings work and each write is saved immediately.
@Observable
final class AppSettings {
    nonisolated struct Values: Codable, Equatable, Sendable {
        var streamQualityWiFi: AudioQuality = .lossless
        var streamQualityCellular: AudioQuality = .hq
        var downloadQuality: AudioQuality = .hq
        var adaptiveQuality = true
        var downloadOverCellular = false
        var autoDownloadLiked = false
        var offlineMode = false
        var waveMotion: WaveMotion = .full
        /// Cap for the transient streaming cache (explicit downloads are never evicted).
        var cacheLimitBytes: Int64 = 1 << 30
        /// Optional so settings saved before this field existed still decode.
        var waveTuning: WaveTuning?
    }

    private static let key = "ym.settings.v1"
    private let defaults: UserDefaults
    private var values: Values

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let v = try? JSONDecoder().decode(Values.self, from: data) {
            values = v
        } else {
            values = Values()
        }
    }

    /// Quality for streaming on Wi-Fi / Ethernet.
    var streamQualityWiFi: AudioQuality { get { values.streamQualityWiFi } set { update { $0.streamQualityWiFi = newValue } } }
    /// Quality for streaming on cellular or a personal hotspot.
    var streamQualityCellular: AudioQuality { get { values.streamQualityCellular } set { update { $0.streamQualityCellular = newValue } } }
    /// Quality of tracks saved for offline listening.
    var downloadQuality: AudioQuality { get { values.downloadQuality } set { update { $0.downloadQuality = newValue } } }
    /// Temporarily lower the stream quality on a weak link and restore it when the link recovers.
    var adaptiveQuality: Bool { get { values.adaptiveQuality } set { update { $0.adaptiveQuality = newValue } } }
    var downloadOverCellular: Bool { get { values.downloadOverCellular } set { update { $0.downloadOverCellular = newValue } } }
    /// Keep every liked track downloaded.
    var autoDownloadLiked: Bool { get { values.autoDownloadLiked } set { update { $0.autoDownloadLiked = newValue } } }
    /// Manual "downloaded only" switch: no network use for playback even when online.
    var offlineMode: Bool { get { values.offlineMode } set { update { $0.offlineMode = newValue } } }
    var waveMotion: WaveMotion { get { values.waveMotion } set { update { $0.waveMotion = newValue } } }
    var cacheLimitBytes: Int64 { get { values.cacheLimitBytes } set { update { $0.cacheLimitBytes = newValue } } }
    /// "Настроить Мою волну" filters.
    var waveTuning: WaveTuning {
        get { values.waveTuning ?? WaveTuning() }
        set { update { $0.waveTuning = newValue.isDefault ? nil : newValue } }
    }

    private func update(_ change: (inout Values) -> Void) {
        var v = values
        change(&v)
        guard v != values else { return }
        values = v
        if let data = try? JSONEncoder().encode(v) { defaults.set(data, forKey: Self.key) }
    }
}
