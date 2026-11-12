import SwiftUI

/// Audio-reactive "My Wave" backdrop.
///
/// A thin SwiftUI shell over `WaveLayerView` (see WaveRenderer.swift), which draws the
/// `WaveBlob.metal` shader into a tiny Metal drawable on its own display link. Nothing here
/// is re-evaluated per frame: SwiftUI only pushes a new `WaveConfig` when an input changes.
///
/// It stops drawing by itself when off screen, in the background, under Reduce Motion, when
/// the device is hot, or when the user picked the static wave in Settings.
struct WaveBackground: View {
    var isPlaying: Bool = false
    /// 2–4 colors, usually derived from the current cover. Empty = default magenta/yellow.
    var palette: [Color] = []
    /// Stop rendering entirely (e.g. scrolled out of view).
    var active: Bool = true
    /// Finger position in **global** coordinates; the blobs lean toward it. `nil` = lifted.
    var externalTouch: CGPoint? = nil
    /// Overall brightness, 0...1.
    var dim: Double = 1

    /// Yandex-like default: magenta, violet, yellow, hot pink.
    static let defaultPalette: [Color] = [
        Color(red: 0.93, green: 0.18, blue: 0.62),
        Color(red: 0.52, green: 0.22, blue: 0.95),
        Color(red: 1.00, green: 0.80, blue: 0.10),
        Color(red: 1.00, green: 0.38, blue: 0.42),
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.self) private var environment
    @Environment(Player.self) private var player: Player?
    @Environment(AppSettings.self) private var settings: AppSettings?

    var body: some View {
        Group {
            if WaveMetal.shared != nil {
                WaveLayerRepresentable(config: config, spectrum: player?.spectrumSource)
            } else {
                fallback
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var config: WaveConfig {
        WaveConfig(isPlaying: isPlaying,
                   palette: resolvedPalette,
                   active: active,
                   motion: settings?.waveMotion ?? .full,
                   reduceMotion: reduceMotion,
                   touch: externalTouch,
                   dim: Float(min(max(dim, 0), 1)))
    }

    /// Palette padded/truncated to exactly 4 resolved sRGB colors.
    private var resolvedPalette: [SIMD3<Float>] {
        let src = palette.isEmpty ? Self.defaultPalette : palette
        return (0..<4).map { i in
            let r = src[i % src.count].resolve(in: environment)
            return SIMD3(r.red, r.green, r.blue)
        }
    }

    /// No Metal (should not happen on real hardware): a plain static glow.
    private var fallback: some View {
        let c = palette.isEmpty ? Self.defaultPalette : palette
        return RadialGradient(colors: [c[c.count > 2 ? 2 : 0], c[0].opacity(0.7), .black],
                              center: UnitPoint(x: 0.5, y: 0.34), startRadius: 10, endRadius: 320)
            .opacity(dim)
    }
}

#Preview {
    WaveBackground(isPlaying: true)
        .ignoresSafeArea()
        .background(.black)
}
