import ImageIO
import SwiftUI

/// Extracts a 4-color wave palette from cover art.
///
/// The cover is downscaled to 32×32, pixels are bucketed by hue (12 buckets) weighted by
/// saturation × brightness (greys and near-blacks are ignored), and the 4 heaviest buckets
/// become the palette. Colors are saturation-boosted and brightness-clamped so they glow on
/// black yet keep contrast for white text. Results are cached per URL.
enum CoverPalette {
    private static var cache: [URL: [Color]] = [:]

    /// `nil` when the image can't be loaded or is essentially greyscale (caller uses the default).
    static func colors(for url: URL) async -> [Color]? {
        if let hit = cache[url] { return hit }
        guard let rgb = await extract(url), !rgb.isEmpty else { return nil }
        let colors = rgb.map { Color(.sRGB, red: Double($0.x), green: Double($0.y), blue: Double($0.z)) }
        cache[url] = colors
        return colors
    }

    // MARK: - Off-main work

    @concurrent
    private nonisolated static func extract(_ url: URL) async -> [SIMD3<Float>]? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let pixels = downscale(cg, side: 32) else { return nil }
        return dominant(pixels)
    }

    /// RGBA8 pixels of `image` drawn into a `side`×`side` bitmap.
    private nonisolated static func downscale(_ image: CGImage, side: Int) -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: side * side * 4)
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return ok ? buf : nil
    }

    private nonisolated static func dominant(_ px: [UInt8]) -> [SIMD3<Float>]? {
        let bucketCount = 12
        var weight = [Float](repeating: 0, count: bucketCount)
        var sum = [SIMD3<Float>](repeating: .zero, count: bucketCount)

        for i in stride(from: 0, to: px.count, by: 4) {
            let c = SIMD3(Float(px[i]), Float(px[i + 1]), Float(px[i + 2])) / 255
            let (h, s, v) = hsv(c)
            guard s > 0.18, v > 0.15 else { continue }        // skip greys and shadows
            let w = s * v * s                                  // favour vivid pixels
            let b = min(Int(h * Float(bucketCount)), bucketCount - 1)
            weight[b] += w
            sum[b] += c * w
        }

        let ranked = weight.indices.filter { weight[$0] > 0.5 }.sorted { weight[$0] > weight[$1] }
        guard !ranked.isEmpty else { return nil }

        var out = ranked.prefix(4).map { tune(sum[$0] / weight[$0]) }
        // Fewer than 4 hues: fill with hue-shifted variants of the dominant one.
        let base = hsv(out[0])
        // Wider hue spread than before so a one-hue cover still yields a multi-colour cloud.
        var shift: Float = 0.14
        while out.count < 4 {
            out.append(rgb(h: (base.h + shift).truncatingRemainder(dividingBy: 1), s: base.s, v: max(0.5, base.v - 0.15)))
            shift = -shift * 1.6
        }
        return out
    }

    /// Boost saturation, clamp brightness to a range that blooms but keeps white text readable.
    private nonisolated static func tune(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let (h, s, v) = hsv(c)
        // Floor saturation high so muted covers still give a vivid, Yandex-like glow.
        return rgb(h: h, s: min(1, max(0.82, s * 1.6)), v: min(0.98, max(0.78, v * 1.3)))
    }

    private nonisolated static func hsv(_ c: SIMD3<Float>) -> (h: Float, s: Float, v: Float) {
        let mx = c.max(), mn = c.min(), d = mx - mn
        var h: Float = 0
        if d > 1e-5 {
            if mx == c.x { h = (c.y - c.z) / d }
            else if mx == c.y { h = 2 + (c.z - c.x) / d }
            else { h = 4 + (c.x - c.y) / d }
            h = (h / 6).truncatingRemainder(dividingBy: 1)
            if h < 0 { h += 1 }
        }
        return (h, mx > 0 ? d / mx : 0, mx)
    }

    private nonisolated static func rgb(h: Float, s: Float, v: Float) -> SIMD3<Float> {
        let i = Int(h * 6) % 6, f = h * 6 - Float(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return [v, t, p]
        case 1: return [q, v, p]
        case 2: return [p, v, t]
        case 3: return [p, q, v]
        case 4: return [t, p, v]
        default: return [v, p, q]
        }
    }
}
