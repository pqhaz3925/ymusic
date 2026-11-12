import Metal
import QuartzCore
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias WavePlatformView = UIView
#else
import AppKit
typealias WavePlatformView = NSView
#endif

// MARK: - Inputs

/// Everything the renderer needs from SwiftUI. Pushed only when a value changes.
struct WaveConfig: Equatable {
    var isPlaying = false
    /// Exactly 4 sRGB colors.
    var palette: [SIMD3<Float>] = []
    var active = true
    var motion: WaveMotion = .full
    var reduceMotion = false
    /// Global coordinates, `nil` = no finger.
    var touch: CGPoint?
    var dim: Float = 1
}

/// Must match `WaveUniforms` in WaveBlob.metal.
nonisolated struct WaveUniforms {
    var spectrum = SIMD4<Float>.zero
    var lab0 = SIMD4<Float>.zero
    var lab1 = SIMD4<Float>.zero
    var lab2 = SIMD4<Float>.zero
    var lab3 = SIMD4<Float>.zero
    var size = SIMD2<Float>.zero
    var touch = SIMD2<Float>.zero
    var time: Float = 0
    var touchAmt: Float = 0
    var intensity: Float = 0.6
    var dim: Float = 1
}

// MARK: - Shared GPU objects

/// Device, queue and pipeline, created once. `nil` when Metal isn't available.
final class WaveMetal {
    static let shared = WaveMetal()

    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let pipeline: any MTLRenderPipelineState

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: .main),
              let vertex = library.makeFunction(name: "waveVertex"),
              let fragment = library.makeFunction(name: "waveFragment") else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = vertex
        d.fragmentFunction = fragment
        d.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: d) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }
}

// MARK: - Smoothing

/// Per-frame easing of everything that feeds the shader, so nothing ever jumps.
struct WaveSmoother {
    private(set) var time: Double = 0
    private(set) var spectrum = SIMD4<Float>.zero
    private(set) var intensity: Float = 0.6
    private(set) var colors: [SIMD3<Float>] = []
    private(set) var touchAmount: Float = 0
    var touchPoint = CGPoint.zero
    var touchTarget: Float = 0

    /// Still frames skip the cross-fade.
    mutating func snap(palette: [SIMD3<Float>], isPlaying: Bool) {
        colors = palette
        intensity = isPlaying ? 1 : 0.55
        spectrum = .zero
        touchAmount = 0
    }

    mutating func step(dt rawDt: Double, spectrum target: SIMD4<Float>, isPlaying: Bool, palette: [SIMD3<Float>]) {
        let dt = Float(min(max(rawDt, 0), 0.1))
        // Exponential smoothing; `rate` ≈ 1/time-constant in seconds.
        func k(_ rate: Float) -> Float { 1 - exp(-rate * dt) }

        // Calmer motion when paused.
        time = (time + Double(dt) * (isPlaying ? 1.0 : 0.45)).truncatingRemainder(dividingBy: 10_000)

        // Fast attack, slower release: punchy but no flicker.
        let rising = target .> spectrum
        let attack = SIMD4<Float>(repeating: k(14)), decay = SIMD4<Float>(repeating: k(4))
        spectrum += (target - spectrum) * attack.replacing(with: decay, where: .!rising)

        intensity += ((isPlaying ? 1 : 0.55) - intensity) * k(2)

        // ~1 s palette cross-fade.
        if colors.count != palette.count { colors = palette }
        for i in colors.indices { colors[i] += (palette[i] - colors[i]) * k(3.3) }

        // Spring-ish touch: quick in, soft decay out.
        touchAmount += (touchTarget - touchAmount) * k(touchTarget > touchAmount ? 10 : 2.5)
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

// MARK: - View

/// Hosts the CAMetalLayer and paces rendering.
///
/// Cost model, and why it is built this way:
/// - The drawable is ~0.3 px per point (about 120×200 px for the home hero), i.e. ~25 k
///   fragments a frame instead of ~2.5 M at native resolution. Core Animation upscales it.
/// - Frames come from a `CADisplayLink` capped at 30 Hz while music plays and 15 Hz when idle
///   (half that in eco mode / Low Power Mode / when the device is warm).
/// - The link only exists while the view is visible, the app is active and motion is allowed.
///   Otherwise a single still frame is drawn and nothing runs at all.
final class WaveLayerView: WavePlatformView {
    var spectrum: SpectrumSource? {
        didSet { if spectrum !== oldValue { stopWatching(oldValue); refresh() } }
    }

    var config = WaveConfig() {
        didSet {
            guard config != oldValue else { return }
            applyTouch()
            if config.palette != oldValue.palette || config.dim != oldValue.dim || config.isPlaying != oldValue.isPlaying {
                needsStill = true
            }
            refresh()
        }
    }

    private var link: CADisplayLink?
    private var smoother = WaveSmoother()
    private var lastTimestamp: CFTimeInterval = 0
    private var appActive = true
    private var needsStill = true
    private var watching = false
    nonisolated(unsafe) private var observers: [any NSObjectProtocol] = []

    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    // MARK: Setup

    #if canImport(UIKit)
    override class var layerClass: AnyClass { CAMetalLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .black
        setUp()
    }
    #else
    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        setUp()
    }

    override func makeBackingLayer() -> CALayer { CAMetalLayer() }
    #endif

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func setUp() {
        guard let metal = WaveMetal.shared, let l = metalLayer else { return }
        l.device = metal.device
        l.pixelFormat = .bgra8Unorm
        l.framebufferOnly = true
        l.isOpaque = true
        l.maximumDrawableCount = 2
        l.contentsGravity = .resize
        l.magnificationFilter = .linear
        l.backgroundColor = CGColor(gray: 0, alpha: 1)

        let nc = NotificationCenter.default
        func on(_ name: Notification.Name, _ body: @escaping @MainActor (WaveLayerView) -> Void) {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { body(self) } }
            })
        }
        #if canImport(UIKit)
        appActive = UIApplication.shared.applicationState != .background
        on(UIApplication.didBecomeActiveNotification) { $0.appActive = true; $0.needsStill = true; $0.refresh() }
        // Stop at "will resign" already: no GPU work may be in flight once we're in the background.
        on(UIApplication.willResignActiveNotification) { $0.appActive = false; $0.refresh() }
        #else
        on(NSApplication.didBecomeActiveNotification) { $0.appActive = true; $0.needsStill = true; $0.refresh() }
        on(NSApplication.didHideNotification) { $0.appActive = false; $0.refresh() }
        on(NSApplication.didUnhideNotification) { $0.appActive = true; $0.refresh() }
        #endif
        on(ProcessInfo.thermalStateDidChangeNotification) { $0.refresh() }
        on(.NSProcessInfoPowerStateDidChange) { $0.refresh() }
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: Lifecycle

    #if canImport(UIKit)
    override func didMoveToWindow() {
        super.didMoveToWindow()
        needsStill = true
        refresh()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resizeDrawable()
    }
    #else
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsStill = true
        refresh()
    }

    override func layout() {
        super.layout()
        resizeDrawable()
    }

    // A hosted NSView isn't necessarily laid out when SwiftUI resizes it.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resizeDrawable()
    }
    #endif

    private func resizeDrawable() {
        guard let l = metalLayer, bounds.width > 1, bounds.height > 1 else { return }
        // ~0.3 px per point, clamped so tiny and huge views both stay sane.
        let w = min(max(bounds.width * 0.3, 64), 220)
        let size = CGSize(width: w.rounded(), height: max(1, (w * bounds.height / bounds.width).rounded()))
        if l.drawableSize != size {
            l.drawableSize = size
            needsStill = true
            refresh()
        }
    }

    // MARK: Pacing

    private var visible: Bool {
        window != nil && appActive && config.active && bounds.width > 1 && bounds.height > 1
    }

    private var throttled: Bool {
        config.motion == .eco || ProcessInfo.processInfo.isLowPowerModeEnabled
            || ProcessInfo.processInfo.thermalState == .fair
    }

    /// 0 = don't animate.
    private var targetFPS: Float {
        guard visible, !config.reduceMotion, config.motion != .still else { return 0 }
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: return 0
        default: break
        }
        let fps: Float = config.isPlaying ? 30 : 15
        return throttled ? fps / 2 : fps
    }

    /// Re-evaluate whether to run the display link, after any input changed.
    private func refresh() {
        let fps = targetFPS
        if fps > 0 {
            startLink(fps: fps)
            startWatching()
        } else {
            stopLink()
            stopWatching(spectrum)
            if visible, needsStill { drawStill() }
        }
    }

    private func startLink(fps: Float) {
        if link == nil {
            #if canImport(UIKit)
            let l = CADisplayLink(target: WeakLinkTarget(self), selector: #selector(WeakLinkTarget.tick(_:)))
            #else
            let l = displayLink(target: WeakLinkTarget(self), selector: #selector(WeakLinkTarget.tick(_:)))
            #endif
            l.add(to: .main, forMode: .common)
            link = l
            lastTimestamp = 0
        }
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: min(fps, 10), maximum: fps, preferred: fps)
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    private func startWatching() {
        guard !watching, let spectrum else { return }
        spectrum.beginWatching()
        watching = true
    }

    private func stopWatching(_ source: SpectrumSource?) {
        guard watching else { return }
        source?.endWatching()
        watching = false
    }

    // MARK: Frames

    fileprivate func tick(_ link: CADisplayLink) {
        guard targetFPS > 0 else { refresh(); return }
        let now = link.targetTimestamp
        let dt = lastTimestamp > 0 ? now - lastTimestamp : 1.0 / 30
        lastTimestamp = now
        smoother.step(dt: dt,
                      spectrum: config.isPlaying ? (spectrum?.snapshot() ?? .zero) : .zero,
                      isPlaying: config.isPlaying,
                      palette: config.palette)
        draw()
    }

    private func drawStill() {
        needsStill = false
        smoother.snap(palette: config.palette, isPlaying: config.isPlaying)
        draw()
    }

    private func applyTouch() {
        if let p = config.touch {
            #if canImport(UIKit)
            smoother.touchPoint = convert(p, from: nil)
            #else
            smoother.touchPoint = p
            #endif
            smoother.touchTarget = 1
        } else {
            smoother.touchTarget = 0
        }
    }

    private func draw() {
        guard let metal = WaveMetal.shared, let l = metalLayer,
              l.drawableSize.width >= 1, l.drawableSize.height >= 1,
              smoother.colors.count == 4,
              let drawable = l.nextDrawable(),
              let buffer = metal.queue.makeCommandBuffer() else { return }

        let size = l.drawableSize
        let sx = Float(size.width / max(bounds.width, 1)), sy = Float(size.height / max(bounds.height, 1))
        var u = WaveUniforms()
        u.spectrum = smoother.spectrum
        u.lab0 = waveOKLab(smoother.colors[0])
        u.lab1 = waveOKLab(smoother.colors[1])
        u.lab2 = waveOKLab(smoother.colors[2])
        u.lab3 = waveOKLab(smoother.colors[3])
        u.size = SIMD2(Float(size.width), Float(size.height))
        u.touch = SIMD2(Float(smoother.touchPoint.x) * sx, Float(smoother.touchPoint.y) * sy)
        u.time = Float(smoother.time)
        u.touchAmt = smoother.touchAmount
        u.intensity = smoother.intensity
        u.dim = config.dim

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(metal.pipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<WaveUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// `CADisplayLink` retains its target; this keeps the view free to go away.
private final class WeakLinkTarget: NSObject {
    weak var view: WaveLayerView?
    init(_ view: WaveLayerView) { self.view = view }

    @objc func tick(_ link: CADisplayLink) {
        guard let view else { link.invalidate(); return }
        view.tick(link)
    }
}

// MARK: - SwiftUI bridge

#if canImport(UIKit)
struct WaveLayerRepresentable: UIViewRepresentable {
    var config: WaveConfig
    var spectrum: SpectrumSource?

    func makeUIView(context: Context) -> WaveLayerView { WaveLayerView(frame: .zero) }

    func updateUIView(_ view: WaveLayerView, context: Context) {
        view.spectrum = spectrum
        view.config = config
    }
}
#else
struct WaveLayerRepresentable: NSViewRepresentable {
    var config: WaveConfig
    var spectrum: SpectrumSource?

    func makeNSView(context: Context) -> WaveLayerView { WaveLayerView(frame: .zero) }

    func updateNSView(_ view: WaveLayerView, context: Context) {
        view.spectrum = spectrum
        view.config = config
    }
}
#endif
