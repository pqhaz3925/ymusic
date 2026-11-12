import SwiftUI
import UIKit

/// Shares the mini player's namespace with the full-screen cover so the cover art can zoom between them.
enum NowPlayingTransition {
    static let sourceID = "now-playing-cover"
    static var namespace: Namespace.ID?
}

/// Applies `.navigationTransition(.zoom)` only when the mini player has registered a source.
struct ZoomFromMiniPlayer: ViewModifier {
    func body(content: Content) -> some View {
        if let ns = NowPlayingTransition.namespace {
            content.navigationTransition(.zoom(sourceID: NowPlayingTransition.sourceID, in: ns))
        } else {
            content
        }
    }
}

enum PlayerFormat {
    /// `m:ss` (or `h:mm:ss`).
    static func time(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// "850 кбит/с" or "12,4 Мбит/с".
    static func speed(kbps: Double) -> String {
        if kbps < 1000 { return "\(Int(kbps.rounded())) кбит/с" }
        return (kbps / 1000).formatted(.number.precision(.fractionLength(1))) + " Мбит/с"
    }

    /// `flac-mp4` -> `FLAC`, `he-aac-mp4` -> `HE-AAC`.
    static func codec(_ raw: String) -> String {
        var s = raw.lowercased()
        if s.hasSuffix("-mp4") { s.removeLast(4) }
        return s.uppercased()
    }

    /// Russian plural: 1 трек, 2 трека, 5 треков.
    static func tracks(_ n: Int) -> String {
        let m10 = n % 10, m100 = n % 100
        let word = m10 == 1 && m100 != 11 ? "трек"
            : (2...4).contains(m10) && !(12...14).contains(m100) ? "трека" : "треков"
        return "\(n) \(word)"
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

/// Single-line text that scrolls horizontally when it does not fit. Truncates instead under Reduce Motion.
///
/// The scroll is one repeating Core Animation on a UIKit layer: it runs in the render server,
/// so SwiftUI does no per-frame work. It restarts only when the text, font or width changes.
struct PlayerMarquee: UIViewRepresentable {
    let text: String
    var style: UIFont.TextStyle = .body
    var weight: UIFont.Weight = .regular
    var secondary = false

    func makeUIView(context: Context) -> MarqueeLabelView {
        let v = MarqueeLabelView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    func updateUIView(_ view: MarqueeLabelView, context: Context) {
        view.configure(text: text,
                       font: font(context.environment),
                       color: secondary ? UIColor.white.withAlphaComponent(0.6) : .label,
                       animates: !context.environment.accessibilityReduceMotion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarqueeLabelView, context: Context) -> CGSize? {
        let f = font(context.environment)
        let height = ceil(f.lineHeight)
        if let w = proposal.width, w.isFinite { return CGSize(width: w, height: height) }
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: f]).width)
        return CGSize(width: textWidth, height: height)
    }

    private func font(_ env: EnvironmentValues) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style,
                                        compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        let sized = UIFont.systemFont(ofSize: base.pointSize, weight: weight)
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(env.dynamicTypeSize))
        return UIFontMetrics(forTextStyle: style).scaledFont(for: sized, compatibleWith: traits)
    }
}

/// Two labels on a strip; the strip slides left by one text width + gap, pauses, repeats.
final class MarqueeLabelView: UIView {
    private let strip = UIView()
    private let first = UILabel()
    private let second = UILabel()
    private let fade = CAGradientLayer()

    private var animates = true
    /// What the running animation was built for; layout passes with the same key are no-ops.
    private var builtFor: Key?

    private struct Key: Equatable {
        var text: String
        var fontSize: CGFloat
        var width: CGFloat
        var height: CGFloat
        var animates: Bool
    }

    private let gap: CGFloat = 36
    private let speed: CGFloat = 28
    private let pause: CFTimeInterval = 1.6

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        for l in [first, second] {
            l.numberOfLines = 1
            l.lineBreakMode = .byTruncatingTail
            l.isAccessibilityElement = false
            strip.addSubview(l)
        }
        addSubview(strip)
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        fade.locations = [0, 0.9, 1]
        NotificationCenter.default.addObserver(self, selector: #selector(restart),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, font: UIFont, color: UIColor, animates: Bool) {
        accessibilityLabel = text
        for l in [first, second] {
            if l.text != text { l.text = text }
            if l.font != font { l.font = font }
            if l.textColor != color { l.textColor = color }
        }
        if self.animates != animates { self.animates = animates }
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Animations can be dropped while off-window; rebuild on return.
        if window != nil { restart() }
    }

    @objc private func restart() {
        builtFor = nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let key = Key(text: first.text ?? "", fontSize: first.font.pointSize,
                      width: bounds.width, height: bounds.height, animates: animates)
        guard key != builtFor else { return }
        builtFor = key

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        strip.layer.removeAnimation(forKey: "marquee")
        let textWidth = ceil(first.intrinsicContentSize.width)
        let scrolls = animates && window != nil && bounds.width > 0 && textWidth > bounds.width + 1

        guard scrolls else {
            second.isHidden = true
            strip.frame = bounds
            first.frame = bounds
            layer.mask = nil
            return
        }

        second.isHidden = false
        first.frame = CGRect(x: 0, y: 0, width: textWidth, height: bounds.height)
        second.frame = first.frame.offsetBy(dx: textWidth + gap, dy: 0)
        strip.frame = CGRect(x: 0, y: 0, width: textWidth * 2 + gap, height: bounds.height)
        fade.frame = bounds
        layer.mask = fade

        let travel = textWidth + gap
        let move = CABasicAnimation(keyPath: "transform.translation.x")
        move.fromValue = 0
        move.toValue = -travel
        move.beginTime = pause
        move.duration = CFTimeInterval(travel / speed)
        let cycle = CAAnimationGroup()
        cycle.animations = [move]
        cycle.duration = pause + move.duration
        cycle.repeatCount = .infinity
        cycle.isRemovedOnCompletion = false
        strip.layer.add(cycle, forKey: "marquee")
    }
}
