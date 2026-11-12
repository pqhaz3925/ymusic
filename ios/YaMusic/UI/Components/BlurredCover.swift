import CoreImage
import SwiftUI
import UIKit

/// Static full-screen backdrop made from a cover: blurred and saturated once, off the main actor,
/// cached per URL. On screen it is a plain image plus a scrim, so it costs nothing per frame.
/// Pass a small cover URL (~100 px); the upscale adds to the softness.
struct BlurredCover: View {
    let url: URL?

    private struct Shown: Equatable {
        let url: URL
        let image: UIImage
    }

    @State private var shown: Shown?

    var body: some View {
        ZStack {
            Theme.background
            if let shown {
                Color.clear
                    .overlay {
                        Image(uiImage: shown.image)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFill()
                    }
                    .clipped()
                    .opacity(0.75)
                    .id(shown.url)
                    .transition(.opacity)
            }
            // Scrim keeps text and controls legible over bright covers.
            LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.1), .black.opacity(0.65)],
                           startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else {
                withAnimation(.easeInOut(duration: 0.5)) { shown = nil }
                return
            }
            if let hit = BlurredCoverRenderer.shared.cached(url) {
                shown = Shown(url: url, image: hit)
                return
            }
            guard let image = await BlurredCoverRenderer.shared.render(url), !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) { shown = Shown(url: url, image: image) }
        }
    }
}

/// Downloads, blurs and caches backdrops. NSCache and CIContext are thread-safe.
nonisolated final class BlurredCoverRenderer: @unchecked Sendable {
    static let shared = BlurredCoverRenderer()

    private let cache = NSCache<NSURL, UIImage>()
    private let context = CIContext(options: [.cacheIntermediates: false])

    private init() { cache.countLimit = 24 }

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    @concurrent
    func render(_ url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = process(data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    private func process(_ data: Data) -> UIImage? {
        guard let input = CIImage(data: data) else { return nil }
        let side = max(input.extent.width, input.extent.height)
        guard side > 0 else { return nil }
        // Work at ~64 px: the blur is cheap and the later upscale is smooth.
        let scale = min(1, 64 / side)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = small.extent.integral
        let blurred = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 6)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.5,
                kCIInputBrightnessKey: -0.05,
            ])
            .cropped(to: extent)
        // Bright covers (white artwork) would turn the whole player grey and wash out the white
        // controls: scale the backdrop down so its average luminance never exceeds ~0.3.
        let gain = min(1, 0.3 / max(meanLuminance(blurred, extent: extent), 0.01))
        let toned = gain < 1
            ? blurred.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
            ])
            : blurred
        guard let cg = context.createCGImage(toned, from: extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Average luminance (0...1) of `image`, read back from a 1×1 render.
    private func meanLuminance(_ image: CIImage, extent: CGRect) -> CGFloat {
        let avg = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)])
        var px = [UInt8](repeating: 0, count: 4)
        context.render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (0.2126 * CGFloat(px[0]) + 0.7152 * CGFloat(px[1]) + 0.0722 * CGFloat(px[2])) / 255
    }
}
