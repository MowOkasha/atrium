// Renders Atrium's app icon: three stacked panes of glass with a name tag on the front pane.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let cs = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

/// Apple-style continuous corner ("squircle") path.
func squircle(_ rect: CGRect, radius r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let k: CGFloat = 1.28 // extends the curve like Apple's continuous corners
    let c = r * k
    let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    p.move(to: CGPoint(x: x0 + c, y: y0))
    p.addLine(to: CGPoint(x: x1 - c, y: y0))
    p.addCurve(to: CGPoint(x: x1, y: y0 + c), control1: CGPoint(x: x1 - c * 0.35, y: y0), control2: CGPoint(x: x1, y: y0 + c * 0.35))
    p.addLine(to: CGPoint(x: x1, y: y1 - c))
    p.addCurve(to: CGPoint(x: x1 - c, y: y1), control1: CGPoint(x: x1, y: y1 - c * 0.35), control2: CGPoint(x: x1 - c * 0.35, y: y1))
    p.addLine(to: CGPoint(x: x0 + c, y: y1))
    p.addCurve(to: CGPoint(x: x0, y: y1 - c), control1: CGPoint(x: x0 + c * 0.35, y: y1), control2: CGPoint(x: x0, y: y1 - c * 0.35))
    p.addLine(to: CGPoint(x: x0, y: y0 + c))
    p.addCurve(to: CGPoint(x: x0 + c, y: y0), control1: CGPoint(x: x0, y: y0 + c * 0.35), control2: CGPoint(x: x0 + c * 0.35, y: y0))
    p.closeSubpath()
    return p
}

func linear(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locations)!
}

// Body (macOS icon grid: 824pt body centered in 1024 canvas).
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = squircle(body, radius: 150)

// Drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0, 0, 0, 0.38))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0.06, 0.09, 0.22))
ctx.fillPath()
ctx.restoreGState()

// Background gradient: midnight indigo → electric blue → cyan glow
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
ctx.drawLinearGradient(
    linear([color(0.36, 0.88, 1.0), color(0.14, 0.45, 0.95), color(0.09, 0.11, 0.40)], [0, 0.5, 1]),
    start: CGPoint(x: 200, y: 960), end: CGPoint(x: 820, y: 80),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// soft light bloom upper-left
ctx.drawRadialGradient(
    linear([color(1, 1, 1, 0.30), color(1, 1, 1, 0)], [0, 1]),
    startCenter: CGPoint(x: 280, y: 880), startRadius: 0,
    endCenter: CGPoint(x: 280, y: 880), endRadius: 560, options: [])
// depth vignette lower-right
ctx.drawRadialGradient(
    linear([color(0.02, 0.03, 0.12, 0), color(0.02, 0.03, 0.12, 0.45)], [0, 1]),
    startCenter: CGPoint(x: 470, y: 560), startRadius: 300,
    endCenter: CGPoint(x: 470, y: 560), endRadius: 720, options: [])
ctx.restoreGState()

// Glass panes, back to front.
struct Pane { let rect: CGRect; let fill: CGFloat; let rim: CGFloat }
let w: CGFloat = 470, h: CGFloat = 350
let panes = [
    Pane(rect: CGRect(x: 360, y: 450, width: w, height: h), fill: 0.13, rim: 0.40),
    Pane(rect: CGRect(x: 277, y: 350, width: w, height: h), fill: 0.20, rim: 0.55),
    Pane(rect: CGRect(x: 194, y: 250, width: w, height: h), fill: 0.30, rim: 0.85),
]

for (i, pane) in panes.enumerated() {
    let path = squircle(pane.rect, radius: 52)

    // shadow beneath each pane
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0.02, 0.04, 0.20, 0.35))
    ctx.addPath(path)
    ctx.setFillColor(color(1, 1, 1, pane.fill))
    ctx.fillPath()
    ctx.restoreGState()

    // frosted vertical sheen
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        linear([color(1, 1, 1, pane.fill + 0.22), color(1, 1, 1, pane.fill * 0.35)], [0, 1]),
        start: CGPoint(x: pane.rect.minX, y: pane.rect.maxY),
        end: CGPoint(x: pane.rect.maxX, y: pane.rect.minY), options: [])
    ctx.restoreGState()

    // rim light: bright top-left, fading bottom-right
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(i == 2 ? 5 : 4)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        linear([color(1, 1, 1, pane.rim), color(1, 1, 1, pane.rim * 0.15), color(1, 1, 1, pane.rim * 0.5)], [0, 0.6, 1]),
        start: CGPoint(x: pane.rect.minX, y: pane.rect.maxY),
        end: CGPoint(x: pane.rect.maxX, y: pane.rect.minY), options: [])
    ctx.restoreGState()
}

// Name tag on the front pane: a crisp pill + softer line beneath, like a label.
let front = panes[2].rect
let pill = CGRect(x: front.minX + 56, y: front.maxY - 56 - 46, width: 190, height: 46)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: color(0.05, 0.10, 0.40, 0.30))
ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 23, cornerHeight: 23, transform: nil))
ctx.setFillColor(color(1, 1, 1, 0.96))
ctx.fillPath()
ctx.restoreGState()

let line = CGRect(x: front.minX + 56, y: pill.minY - 40, width: 120, height: 18)
ctx.addPath(CGPath(roundedRect: line, cornerWidth: 9, cornerHeight: 9, transform: nil))
ctx.setFillColor(color(1, 1, 1, 0.45))
ctx.fillPath()

// Top gloss across the body.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
ctx.drawLinearGradient(
    linear([color(1, 1, 1, 0.16), color(1, 1, 1, 0)], [0, 1]),
    start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])
ctx.restoreGState()

// Hairline edge on the body.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.setLineWidth(3)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(
    linear([color(1, 1, 1, 0.45), color(1, 1, 1, 0.05)], [0, 1]),
    start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
