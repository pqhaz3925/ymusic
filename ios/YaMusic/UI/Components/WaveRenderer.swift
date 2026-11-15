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

// MARK: - View

/// Hosts the CAMetalLayer and paces rendering. The motion itself is `WaveSmoother`
/// (WaveDynamics.swift); this view only decides when a frame is worth drawing.
///
/// Cost model, and why it is built this way:
/// - On the phone the drawable is half a pixel per point (about 200×390 px for the home hero),
///   i.e. ~75 k fragments a frame instead of ~2.5 M at native resolution; Core Animation
///   upscales it. A Mac has the GPU to spare and gets one pixel per point.
/// - Frames come from a `CADisplayLink`: 30 Hz while music plays and 15 Hz when idle on the
///   phone, 60 / 30 Hz on a Mac (half that in eco mode / Low Power Mode / when the device is warm).
/// - The link only exists while the view is visible, the app is active and motion is allowed.
///   Otherwise a single still frame is drawn and nothing runs at all. When playback stops the
///   picture is given a moment to come to rest first, so it never freezes mid-beat.
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
        // Clamped so tiny and huge views both stay sane.
        #if canImport(UIKit)
        let w = min(max(bounds.width * 0.5, 64), 256)
        #else
        let w = min(max(bounds.width, 64), 1600)
        #endif
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

    /// On screen, and neither the user nor the device objects to motion.
    private var mayAnimate: Bool {
        guard visible, !config.reduceMotion else { return false }
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: return false
        default: return true
        }
    }

    /// 0 = don't animate.
    private var targetFPS: Float {
        guard mayAnimate, config.motion != .still else { return 0 }
        #if canImport(UIKit)
        let fps: Float = config.isPlaying ? 30 : 15
        #else
        let fps: Float = config.isPlaying ? 60 : 30
        #endif
        return throttled ? fps / 2 : fps
    }

    /// The animation was just switched off (pause, static mode) while the picture is still
    /// in motion: keep drawing until it has come to rest.
    private var settling: Bool { link != nil && mayAnimate && !smoother.isAtRest }

    /// Re-evaluate whether to run the display link, after any input changed.
    private func refresh() {
        let fps = targetFPS
        if fps > 0 {
            startLink(fps: fps)
            startWatching()
        } else if settling {
            startLink(fps: 30)
            stopWatching(spectrum)
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
        let animating = targetFPS > 0
        guard animating || settling else { refresh(); return }
        let now = link.targetTimestamp
        let dt = lastTimestamp > 0 ? now - lastTimestamp : 1.0 / 30
        lastTimestamp = now
        let playing = animating && config.isPlaying
        // This frame is on screen a little after its target time: show what will be sounding then.
        let lead = min(max(now - CACurrentMediaTime(), 0), 0.05) + 0.012
        smoother.step(dt: dt,
                      frame: playing ? (spectrum?.snapshot(lead: lead) ?? .zero) : .zero,
                      isPlaying: playing,
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
        var u = smoother.uniforms
        u.size = SIMD2(Float(size.width), Float(size.height))
        u.touch = SIMD2(Float(smoother.touchPoint.x) * sx, Float(smoother.touchPoint.y) * sy)
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
