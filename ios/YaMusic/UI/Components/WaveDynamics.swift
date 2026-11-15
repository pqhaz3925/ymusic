import CoreGraphics
import Foundation

/// Must match `WaveUniforms` in WaveBlob.metal.
nonisolated struct WaveUniforms {
    var bands = SIMD4<Float>.zero
    /// x = kick punch, y = high-end sparkle, z = energy (slow loudness), w = sway (slow bass).
    var pulse = SIMD4<Float>.zero
    var rippleAge = SIMD4<Float>(repeating: 100)
    var rippleAmp = SIMD4<Float>.zero
    var lab0 = SIMD4<Float>.zero
    var lab1 = SIMD4<Float>.zero
    var lab2 = SIMD4<Float>.zero
    var lab3 = SIMD4<Float>.zero
    var size = SIMD2<Float>.zero
    var touch = SIMD2<Float>.zero
    var time: Float = 0
    var flow: Float = 0
    var touchAmt: Float = 0
    var intensity: Float = 0.6
    var dim: Float = 1
}

/// Turns what the analyser hears into the motion of the backdrop, one display frame at a time,
/// so nothing ever jumps: band levels with a quick attack and a slower release, a slow "energy"
/// that follows loudness, a punch per kick, and the two things that make the picture move
/// *with* the track — the fluid's own clock runs faster while the music is loud and is eased
/// forward by every kick, and each kick sends a band of light rolling up the sheets.
///
/// Anything that bends the picture's geometry gets a slow value or an eased one: a shape
/// that follows the raw beat twitches, a shape that leans into it dances.
nonisolated struct WaveSmoother {
    /// Both clocks wrap here. The shader only uses them as `sin(clock * c)` with `c` a multiple
    /// of 0.001, for which this period is seamless, and a `Float` stays precise below it.
    static let period = 2000 * Double.pi
    static let idleIntensity: Float = 0.55

    private(set) var time: Double = 0
    private(set) var flow: Double = 0
    private(set) var bands = SIMD4<Float>.zero
    private(set) var punch: Float = 0
    private(set) var sparkle: Float = 0
    private(set) var energy: Float = 0
    /// Bass, slowly: how hard the fluid folds.
    private(set) var sway: Float = 0
    private(set) var intensity: Float = WaveSmoother.idleIntensity
    private(set) var colors: [SIMD3<Float>] = []
    private(set) var touchAmount: Float = 0
    /// Seconds since each of the last kicks (large = none) and how hard it was.
    private(set) var rippleAge = SIMD4<Float>(repeating: 100)
    private(set) var rippleAmp = SIMD4<Float>.zero
    var touchPoint = CGPoint.zero
    var touchTarget: Float = 0

    /// A kick's shove, and the extra flow speed that eases toward it.
    private var shove: Float = 0
    private var surge: Float = 0
    private var lastKick: Float = 0
    private var sinceRipple: Float = 1
    private var newestRipple = 0

    /// Nothing left to animate once playback has stopped: the next frame would look the same.
    var isAtRest: Bool {
        abs(intensity - Self.idleIntensity) < 0.004 && energy < 0.004 && punch < 0.004 && sparkle < 0.004
            && sway < 0.01 && surge < 0.004 && bands.max() < 0.004 && rippleAge.min() > 2 && touchAmount < 0.004 && touchTarget == 0
    }

    /// A still frame: no cross-fade, no music. The clocks stay where they are, so a still
    /// continues the picture that was on screen.
    mutating func snap(palette: [SIMD3<Float>], isPlaying: Bool) {
        colors = palette
        intensity = isPlaying ? 1 : Self.idleIntensity
        energy = isPlaying ? 0.5 : 0
        bands = .zero
        sway = 0
        punch = 0
        sparkle = 0
        shove = 0
        surge = 0
        rippleAge = SIMD4(repeating: 100)
        rippleAmp = .zero
        touchAmount = 0
    }

    mutating func step(dt rawDt: Double, frame: SpectrumFrame, isPlaying: Bool, palette: [SIMD3<Float>]) {
        let dt = Float(min(max(rawDt, 0), 0.1))
        // Exponential smoothing; `rate` ≈ 1/time-constant in seconds.
        func k(_ rate: Float) -> Float { 1 - exp(-rate * dt) }
        let f = isPlaying ? frame : .zero

        // Quick attack, slower release: lively but no flicker.
        let rising = f.bands .> bands
        let attack = SIMD4<Float>(repeating: k(16)), decay = SIMD4<Float>(repeating: k(4))
        bands += (f.bands - bands) * attack.replacing(with: decay, where: .!rising)
        energy += (f.level - energy) * k(f.level > energy ? 2.2 : 0.9)
        sway += (f.bands.x - sway) * k(f.bands.x > sway ? 3 : 1.2)
        punch += (f.kick - punch) * k(f.kick > punch ? 22 : 4.5)
        sparkle += (f.snap - sparkle) * k(f.snap > sparkle ? 24 : 7)

        // A kick: a new band of light and a shove to the fluid. The onset keeps growing for a
        // couple of frames, so the newest one takes its final strength during that time.
        rippleAge += SIMD4(repeating: dt)
        sinceRipple += dt
        if f.kick > 0.3, f.kick > lastKick + 0.1, sinceRipple > 0.15 {
            newestRipple = (newestRipple + 1) % 4
            rippleAge[newestRipple] = 0
            rippleAmp[newestRipple] = f.kick
            shove += 0.9 * f.kick
            sinceRipple = 0
        } else if sinceRipple < 0.08, f.kick > rippleAmp[newestRipple] {
            shove += 0.9 * (f.kick - rippleAmp[newestRipple])
            rippleAmp[newestRipple] = f.kick
        }
        lastKick = f.kick
        surge += (shove - surge) * k(9)
        shove -= shove * k(3)

        // Calmer motion when paused; louder music flows faster.
        let speed: Float = isPlaying ? 0.30 + 0.50 * energy + 0.20 * sway : 0.14
        flow = (flow + Double(dt * (speed + surge))).truncatingRemainder(dividingBy: Self.period)
        time = (time + Double(dt) * (isPlaying ? 1.0 : 0.45)).truncatingRemainder(dividingBy: Self.period)

        intensity += ((isPlaying ? 1 : Self.idleIntensity) - intensity) * k(2)

        // ~1 s palette cross-fade.
        if colors.count != palette.count { colors = palette }
        for i in colors.indices { colors[i] += (palette[i] - colors[i]) * k(3.3) }

        // Spring-ish touch: quick in, soft decay out.
        touchAmount += (touchTarget - touchAmount) * k(touchTarget > touchAmount ? 10 : 2.5)
    }

    /// Everything the shader needs except the drawable's size and the touch point.
    var uniforms: WaveUniforms {
        var u = WaveUniforms()
        u.bands = bands
        u.pulse = SIMD4(punch, sparkle, energy, sway)
        u.rippleAge = rippleAge
        u.rippleAmp = rippleAmp
        if colors.count == 4 {
            u.lab0 = waveOKLab(colors[0])
            u.lab1 = waveOKLab(colors[1])
            u.lab2 = waveOKLab(colors[2])
            u.lab3 = waveOKLab(colors[3])
        }
        u.time = Float(time)
        u.flow = Float(flow)
        u.touchAmt = touchAmount
        u.intensity = intensity
        return u
    }
}

/// sRGB (gamma-encoded) -> OKLab, done on the CPU for the 4 palette entries instead of per pixel.
nonisolated func waveOKLab(_ c: SIMD3<Float>) -> SIMD4<Float> {
    func lin(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    let r = lin(c.x), g = lin(c.y), b = lin(c.z)
    let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return SIMD4(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
                 0)
}
