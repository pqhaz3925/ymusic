// Renders the app icon (the wave cloud + a play mark) into the two asset catalogs.
//   swift scripts/make-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let space = CGColorSpace(name: CGColorSpace.sRGB)!

/// `plate`: side of the artwork square inside the canvas (macOS icons leave a margin and round
/// their own corners; iOS icons are full-bleed and opaque, the system masks them).
func render(canvas: Int, plate: CGFloat, radius: CGFloat, opaque: Bool) -> CGImage {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: info)!
    let c = CGFloat(canvas)
    let rect = CGRect(x: (c - plate) / 2, y: (c - plate) / 2, width: plate, height: plate)
    if radius > 0 {
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
    }
    ctx.setFillColor(CGColor(colorSpace: space, components: [0.03, 0.02, 0.05, 1])!)
    ctx.fill(rect)

    // The cloud: additive radial glows in the wave's default palette.
    func glow(_ rgb: (CGFloat, CGFloat, CGFloat), _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ strength: CGFloat) {
        let stops: [(CGFloat, CGFloat)] = [(0, 1), (0.35, 0.72), (0.7, 0.22), (1, 0)]
        let colors = stops.map { CGColor(colorSpace: space, components: [rgb.0, rgb.1, rgb.2, $0.1 * strength])! }
        let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: stops.map(\.0))!
        let p = CGPoint(x: rect.minX + x * plate, y: rect.minY + y * plate)
        ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r * plate, options: [])
    }
    ctx.setBlendMode(.plusLighter)
    glow((0.52, 0.22, 0.95), 0.72, 0.58, 0.52, 0.9)    // violet, right
    glow((0.93, 0.18, 0.62), 0.30, 0.64, 0.54, 0.95)   // magenta, upper left
    // The core goes on top un-added, so it stays yellow instead of burning out to white.
    ctx.setBlendMode(.normal)
    glow((1.00, 0.42, 0.30), 0.50, 0.40, 0.44, 0.75)   // warm halo
    glow((1.00, 0.80, 0.10), 0.50, 0.38, 0.30, 1.0)    // yellow core

    // Play mark with rounded corners (fill + round-joined stroke of the same colour).
    let s = plate
    let tri = CGMutablePath()
    tri.move(to: CGPoint(x: rect.minX + 0.415 * s, y: rect.minY + 0.655 * s))
    tri.addLine(to: CGPoint(x: rect.minX + 0.415 * s, y: rect.minY + 0.345 * s))
    tri.addLine(to: CGPoint(x: rect.minX + 0.665 * s, y: rect.minY + 0.50 * s))
    tri.closeSubpath()
    ctx.setShadow(offset: CGSize(width: 0, height: -0.012 * s), blur: 0.05 * s,
                  color: CGColor(colorSpace: space, components: [0, 0, 0, 0.35]))
    ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
    ctx.setStrokeColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
    ctx.setLineWidth(0.055 * s)
    ctx.setLineJoin(.round)
    // One layer, so the shadow belongs to the whole mark (not to fill and stroke separately).
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(tri)
    ctx.drawPath(using: .fillStroke)
    ctx.endTransparencyLayer()
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func scaled(_ image: CGImage, to side: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return ctx.makeImage()!
}

// iOS: one opaque full-bleed 1024.
let ios = root.appendingPathComponent("ios/YaMusic/Resources/Assets.xcassets/AppIcon.appiconset")
write(render(canvas: 1024, plate: 1024, radius: 0, opaque: true), to: ios.appendingPathComponent("icon-1024.png"))
try! """
{
  "images" : [ { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
""".write(to: ios.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

// macOS: the standard 824 pt plate with rounded corners inside a 1024 canvas, at every size.
let mac = root.appendingPathComponent("mac/YaMusicMac/Resources/Assets.xcassets/AppIcon.appiconset")
let master = render(canvas: 1024, plate: 824, radius: 185, opaque: false)
var entries: [String] = []
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = points * scale
    let name = "icon-\(points)@\(scale)x.png"
    write(px == 1024 ? master : scaled(master, to: px), to: mac.appendingPathComponent(name))
    entries.append("    { \"filename\" : \"\(name)\", \"idiom\" : \"mac\", \"scale\" : \"\(scale)x\", \"size\" : \"\(points)x\(points)\" }")
}
try! "{\n  \"images\" : [\n\(entries.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
    .write(to: mac.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
for dir in [ios, mac] {
    try! "{\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
        .write(to: dir.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
print("icons written")
