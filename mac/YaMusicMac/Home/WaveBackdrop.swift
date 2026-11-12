import SwiftUI

/// The "My Wave" Metal backdrop for the Mac hero, over the shared `WaveLayerView`.
///
/// Unlike the iOS `WaveBackground` it never animates while nothing plays: a paused wave is a
/// single still frame, so an idle window costs nothing. Its inputs are plain values behind an
/// equality check: the Metal view is only touched when one of them changes.
struct WaveBackdrop: View, Equatable {
    var isPlaying: Bool
    /// Hero on screen and window visible.
    var active: Bool
    var motion: WaveMotion
    var reduceMotion: Bool
    var spectrum: SpectrumSource?
    /// Colours from the current cover; empty = the default magenta / violet / yellow.
    var colors: [Color] = []

    static func == (a: Self, b: Self) -> Bool {
        a.isPlaying == b.isPlaying && a.active == b.active && a.motion == b.motion
            && a.reduceMotion == b.reduceMotion && a.spectrum === b.spectrum && a.colors == b.colors
    }

    var body: some View {
        Group {
            if WaveMetal.shared != nil {
                WaveLayerRepresentable(config: config, spectrum: spectrum)
            } else {
                RadialGradient(colors: [palette[2], palette[0].opacity(0.7), .black],
                               center: UnitPoint(x: 0.5, y: 0.34), startRadius: 10, endRadius: 420)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Exactly four colours for the shader.
    private var palette: [Color] {
        let src = colors.isEmpty ? WaveBackground.defaultPalette : colors
        return (0..<4).map { src[$0 % src.count] }
    }

    private var config: WaveConfig {
        WaveConfig(isPlaying: isPlaying,
                   palette: palette.map { c in
                       let r = NSColor(c).usingColorSpace(.sRGB) ?? .black
                       return SIMD3(Float(r.redComponent), Float(r.greenComponent), Float(r.blueComponent))
                   },
                   active: active,
                   motion: isPlaying ? motion : .still,
                   reduceMotion: reduceMotion,
                   touch: nil,
                   dim: 1)
    }
}
