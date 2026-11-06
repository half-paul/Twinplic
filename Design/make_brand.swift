// Generates the CopyFX app icon and logo files.
// Run from the project root: swift Design/make_brand.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let space = CGColorSpace(name: CGColorSpace.sRGB)!

struct Hex {
    let value: UInt32
    var css: String { String(format: "#%06X", value) }
    var cg: CGColor {
        CGColor(colorSpace: space, components: [
            CGFloat((value >> 16) & 255) / 255, CGFloat((value >> 8) & 255) / 255, CGFloat(value & 255) / 255, 1,
        ])!
    }
}

let inkTop = Hex(value: 0x1C4D4B)
let inkBottom = Hex(value: 0x0F2F30)
let lime = Hex(value: 0xC9F24B)
let paper = Hex(value: 0xF2F6EE)
let mist = Hex(value: 0x4F8F88)
let pine = Hex(value: 0x2E7D74)

/// Continuous (Apple-style) rounded rectangle.
func squircle(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let c = min(rad, min(r.width, r.height) / 2 / 1.528665)
    let a = 1.528665 * c, b = 1.08849296 * c, d = 0.86840694 * c, e = 0.63149379 * c
    let f = 0.07491139 * c, g = 0.37282383 * c, h = 0.16905956 * c
    let x0 = r.minX, x1 = r.maxX, y0 = r.minY, y1 = r.maxY
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    p.move(to: pt(x0 + a, y0))
    p.addLine(to: pt(x1 - a, y0))
    p.addCurve(to: pt(x1 - e, y0 + f), control1: pt(x1 - b, y0), control2: pt(x1 - d, y0))
    p.addCurve(to: pt(x1 - f, y0 + e), control1: pt(x1 - g, y0 + h), control2: pt(x1 - h, y0 + g))
    p.addCurve(to: pt(x1, y0 + a), control1: pt(x1, y0 + d), control2: pt(x1, y0 + b))
    p.addLine(to: pt(x1, y1 - a))
    p.addCurve(to: pt(x1 - f, y1 - e), control1: pt(x1, y1 - b), control2: pt(x1, y1 - d))
    p.addCurve(to: pt(x1 - e, y1 - f), control1: pt(x1 - h, y1 - g), control2: pt(x1 - g, y1 - h))
    p.addCurve(to: pt(x1 - a, y1), control1: pt(x1 - d, y1), control2: pt(x1 - b, y1))
    p.addLine(to: pt(x0 + a, y1))
    p.addCurve(to: pt(x0 + e, y1 - f), control1: pt(x0 + b, y1), control2: pt(x0 + d, y1))
    p.addCurve(to: pt(x0 + f, y1 - e), control1: pt(x0 + g, y1 - h), control2: pt(x0 + h, y1 - g))
    p.addCurve(to: pt(x0, y1 - a), control1: pt(x0, y1 - d), control2: pt(x0, y1 - b))
    p.addLine(to: pt(x0, y0 + a))
    p.addCurve(to: pt(x0 + f, y0 + e), control1: pt(x0, y0 + b), control2: pt(x0, y0 + d))
    p.addCurve(to: pt(x0 + e, y0 + f), control1: pt(x0 + h, y0 + g), control2: pt(x0 + g, y0 + h))
    p.addCurve(to: pt(x0 + a, y0), control1: pt(x0 + d, y0), control2: pt(x0 + b, y0))
    p.closeSubpath()
    return p
}

/// The mark: two offset sheets inside a square of side `extent`, centred on `center`.
func sheets(center: CGPoint, extent: CGFloat, overlap: CGFloat) -> (CGPath, CGPath) {
    let size = (extent + overlap) / 2
    let rad = size * 0.242
    let half = extent / 2
    let a = squircle(CGRect(x: center.x - half, y: center.y - half, width: size, height: size), rad)
    let b = squircle(CGRect(x: center.x + half - size, y: center.y + half - size, width: size, height: size), rad)
    return (a, b)
}

func drawMark(_ c: CGContext, _ a: CGPath, _ b: CGPath, front: Hex, back: Hex, shared: Hex) {
    c.addPath(a); c.setFillColor(front.cg); c.fillPath()
    c.addPath(b); c.setFillColor(back.cg); c.fillPath()
    c.saveGState()
    c.addPath(a); c.clip()
    c.addPath(b); c.setFillColor(shared.cg); c.fillPath()
    c.restoreGState()
}

let iconBody = squircle(CGRect(x: 100, y: 100, width: 824, height: 824), 185)

/// Draws the icon on the 1024 grid. Sizes of 32px and under get a larger mark.
func drawIcon(_ c: CGContext, small: Bool) {
    c.saveGState()
    c.addPath(iconBody); c.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [inkTop.cg, inkBottom.cg] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    if !small {
        // Thin inner edge keeps the shape visible on dark backgrounds. The clip halves the stroke.
        c.addPath(iconBody)
        c.setStrokeColor(paper.cg.copy(alpha: 0.16)!)
        c.setLineWidth(10)
        c.strokePath()
    }
    c.restoreGState()
    let (a, b) = sheets(center: CGPoint(x: 512, y: 512), extent: small ? 680 : 596, overlap: small ? 240 : 212)
    drawMark(c, a, b, front: paper, back: mist, shared: lime)
}

func pixels(_ w: Int, _ h: Int, scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(h))
    c.scaleBy(x: scale, y: -scale)
    draw(c)
    return c.makeImage()!
}

func writePNG(_ image: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("Could not write \(path)") }
}

// MARK: Wordmark. Monoline letters drawn from strokes, so no font licence applies.

let stroke: CGFloat = 27
let capHeight: CGFloat = 150
let xTop: CGFloat = 44
let descender: CGFloat = 198

func outline(_ build: (CGMutablePath) -> Void) -> CGPath {
    let p = CGMutablePath()
    build(p)
    return p.copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

/// Returns the letter outline and its advance, with the left edge of the centreline at x.
func letterC(_ x: CGFloat) -> (CGPath, CGFloat) {
    let r = capHeight / 2, angle = CGFloat.pi * 0.27
    let path = outline { $0.addArc(center: CGPoint(x: x + r, y: r), radius: r, startAngle: -angle, endAngle: angle, clockwise: true) }
    return (path, r + r * cos(angle))
}

func letterO(_ x: CGFloat) -> (CGPath, CGFloat) {
    let r = (capHeight - xTop) / 2
    let path = outline { $0.addEllipse(in: CGRect(x: x, y: xTop, width: r * 2, height: r * 2)) }
    return (path, r * 2)
}

func letterP(_ x: CGFloat) -> (CGPath, CGFloat) {
    let r = (capHeight - xTop) / 2
    let path = outline {
        $0.addEllipse(in: CGRect(x: x, y: xTop, width: r * 2, height: r * 2))
        $0.move(to: CGPoint(x: x, y: xTop + r))
        $0.addLine(to: CGPoint(x: x, y: descender))
    }
    return (path, r * 2)
}

func letterY(_ x: CGFloat) -> (CGPath, CGFloat) {
    let w: CGFloat = 92
    let path = outline {
        $0.move(to: CGPoint(x: x, y: xTop))
        $0.addLine(to: CGPoint(x: x + w * 0.5, y: capHeight))
        $0.move(to: CGPoint(x: x + w, y: xTop))
        $0.addLine(to: CGPoint(x: x + w * 0.28, y: descender))
    }
    return (path, w)
}

func letterF(_ x: CGFloat) -> (CGPath, CGFloat) {
    let w: CGFloat = 84
    let path = outline {
        $0.move(to: CGPoint(x: x + w, y: 0))
        $0.addLine(to: CGPoint(x: x, y: 0))
        $0.addLine(to: CGPoint(x: x, y: capHeight))
        $0.move(to: CGPoint(x: x, y: 70))
        $0.addLine(to: CGPoint(x: x + w * 0.82, y: 70))
    }
    return (path, w)
}

func letterX(_ x: CGFloat) -> (CGPath, CGFloat) {
    let w: CGFloat = 104
    let path = outline {
        $0.move(to: CGPoint(x: x, y: 0))
        $0.addLine(to: CGPoint(x: x + w, y: capHeight))
        $0.move(to: CGPoint(x: x + w, y: 0))
        $0.addLine(to: CGPoint(x: x, y: capHeight))
    }
    return (path, w)
}

/// Lays out the name. Returns the "Copy" and "FX" outlines and the total width.
func wordmark() -> (CGPath, CGPath, CGFloat) {
    let gap: CGFloat = 46
    var x: CGFloat = 0
    let copy = CGMutablePath(), fx = CGMutablePath()
    for letter in [letterC, letterO, letterP, letterY] {
        let (p, advance) = letter(x)
        copy.addPath(p)
        x += advance + gap
    }
    x += 18
    for letter in [letterF, letterX] {
        let (p, advance) = letter(x)
        fx.addPath(p)
        x += advance + gap
    }
    return (copy, fx, x - gap)
}

// MARK: SVG

func svgPath(_ p: CGPath) -> String {
    var d = ""
    func n(_ v: CGFloat) -> String { String(format: "%.2f", v) }
    p.applyWithBlock { element in
        let e = element.pointee, q = e.points
        switch e.type {
        case .moveToPoint: d += "M\(n(q[0].x)) \(n(q[0].y))"
        case .addLineToPoint: d += "L\(n(q[0].x)) \(n(q[0].y))"
        case .addQuadCurveToPoint: d += "Q\(n(q[0].x)) \(n(q[0].y)) \(n(q[1].x)) \(n(q[1].y))"
        case .addCurveToPoint: d += "C\(n(q[0].x)) \(n(q[0].y)) \(n(q[1].x)) \(n(q[1].y)) \(n(q[2].x)) \(n(q[2].y))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

func svgMark(_ a: CGPath, _ b: CGPath, front: Hex, back: Hex, shared: Hex) -> String {
    """
    <defs><clipPath id="front"><path d="\(svgPath(a))"/></clipPath></defs>
    <path fill="\(front.css)" d="\(svgPath(a))"/>
    <path fill="\(back.css)" d="\(svgPath(b))"/>
    <path fill="\(shared.css)" clip-path="url(#front)" d="\(svgPath(b))"/>
    """
}

func writeSVG(_ w: CGFloat, _ h: CGFloat, _ content: String, _ path: String) {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(Int(w)) \(Int(h))" width="\(Int(w))" height="\(Int(h))">
    \(content)
    </svg>

    """
    try! svg.write(toFile: path, atomically: true, encoding: .utf8)
}

// MARK: Output

let fm = FileManager.default
let iconSet = "App/Assets.xcassets/AppIcon.appiconset"
let logoDir = "Design/logo"
for dir in [iconSet, logoDir] { try! fm.createDirectory(atPath: dir, withIntermediateDirectories: true) }

// App icon
let slots: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var entries: [String] = []
for slot in slots {
    let px = slot.points * slot.scale
    let name = "icon_\(slot.points)x\(slot.points)\(slot.scale == 2 ? "@2x" : "").png"
    writePNG(pixels(px, px, scale: CGFloat(px) / 1024) { drawIcon($0, small: px <= 32) }, "\(iconSet)/\(name)")
    entries.append("""
        { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(slot.scale)x", "size" : "\(slot.points)x\(slot.points)" }
    """)
}
let contents = "{\n  \"images\" : [\n\(entries.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try! contents.write(toFile: "\(iconSet)/Contents.json", atomically: true, encoding: .utf8)
try! "{\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
    .write(toFile: "App/Assets.xcassets/Contents.json", atomically: true, encoding: .utf8)

// Mark and logo, in a version for light backgrounds and one for dark
struct Theme { let name: String; let front, back, shared, copy, fx: Hex }
let themes = [
    Theme(name: "light-bg", front: inkBottom, back: mist, shared: lime, copy: inkBottom, fx: pine),
    Theme(name: "dark-bg", front: paper, back: mist, shared: lime, copy: paper, fx: lime),
]

let (copy, fx, wordWidth) = wordmark()
let markSide: CGFloat = 512
let pad: CGFloat = 32
for t in themes {
    // Mark alone
    let (a, b) = sheets(center: CGPoint(x: markSide / 2, y: markSide / 2), extent: markSide - pad * 2, overlap: 196)
    writeSVG(markSide, markSide, svgMark(a, b, front: t.front, back: t.back, shared: t.shared), "\(logoDir)/mark-\(t.name).svg")
    writePNG(pixels(1024, 1024, scale: 2) { drawMark($0, a, b, front: t.front, back: t.back, shared: t.shared) }, "\(logoDir)/mark-\(t.name).png")

    // Mark and name. The name's cap height is 60% of the mark.
    let lockupH: CGFloat = 320
    let markH: CGFloat = 256
    let textScale = markH * 0.6 / capHeight
    let textX = pad + markH + 72
    let textY = (lockupH - capHeight * textScale) / 2
    let lockupW = (textX + wordWidth * textScale + stroke * textScale / 2 + pad).rounded(.up)
    let (la, lb) = sheets(center: CGPoint(x: pad + markH / 2, y: lockupH / 2), extent: markH, overlap: 98)
    var place = CGAffineTransform(translationX: textX, y: textY).scaledBy(x: textScale, y: textScale)
    let placedCopy = copy.copy(using: &place)!
    let placedFX = fx.copy(using: &place)!
    let text = "<path fill=\"\(t.copy.css)\" d=\"\(svgPath(placedCopy))\"/>\n<path fill=\"\(t.fx.css)\" d=\"\(svgPath(placedFX))\"/>"
    writeSVG(lockupW, lockupH, svgMark(la, lb, front: t.front, back: t.back, shared: t.shared) + "\n" + text, "\(logoDir)/logo-\(t.name).svg")
    writePNG(pixels(Int(lockupW) * 2, Int(lockupH) * 2, scale: 2) { c in
        drawMark(c, la, lb, front: t.front, back: t.back, shared: t.shared)
        c.addPath(placedCopy); c.setFillColor(t.copy.cg); c.fillPath()
        c.addPath(placedFX); c.setFillColor(t.fx.cg); c.fillPath()
    }, "\(logoDir)/logo-\(t.name).png")
}

// Icon master, for use outside the app
writePNG(pixels(1024, 1024, scale: 1) { drawIcon($0, small: false) }, "\(logoDir)/app-icon-1024.png")
print("Done")
