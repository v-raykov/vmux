import AppKit
import CoreGraphics

// Builds the vmux icons from the original artwork rather than redrawing the
// plate: each fully opaque row is flooded with its own colour sampled left of
// the old chevron, which erases the glyph while leaving the plate's shading,
// rim, shadow and squircle alpha exactly as shipped. The V is then drawn on top.
let canvas = 1024

// sRGB throughout: CGColor(red:green:blue:) builds a generic-RGB colour, which
// the compositor brightens on its way into the bitmap.
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: colorSpace,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255,
            alpha,
        ]
    )!
}

// Mirrors the chevron's own gradient: bright at the top, deeper at the point.
let glyphTop = rgb(0xFF5714)
let glyphBottom = rgb(0xF0136A)
let glyphGlow = rgb(0xFF4A20, alpha: 0.85)

/// Rows below this keep their original pixels, so a variant banner and its
/// text survive untouched.
let bannerGuardY = 860

func loadRGBA(_ path: String) -> (pixels: [UInt8], bytesPerRow: Int) {
    guard let image = NSImage(contentsOfFile: path),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let ctx = CGContext(
            data: nil,
            width: canvas,
            height: canvas,
            bitsPerComponent: 8,
            bytesPerRow: canvas * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { fatalError("load \(path)") }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(canvas), height: CGFloat(canvas)))
    guard let data = ctx.data else { fatalError("pixels") }
    let buffer = UnsafeBufferPointer(
        start: data.assumingMemoryBound(to: UInt8.self),
        count: canvas * 4 * canvas
    )
    return (Array(buffer), canvas * 4)
}

/// Erases the glyph by flooding each opaque row with the plate colour taken
/// just inside its left edge, well clear of where the chevron sat.
func plateOnly(from path: String) -> CGImage {
    var (pixels, bpr) = loadRGBA(path)

    for y in 0..<canvas {
        guard y < bannerGuardY else { continue }
        var firstOpaqueX: Int?
        for x in 0..<canvas where pixels[y * bpr + x * 4 + 3] == 255 {
            firstOpaqueX = x
            break
        }
        guard let firstOpaqueX else { continue }
        let sampleX = min(firstOpaqueX + 20, canvas - 1)
        let s = y * bpr + sampleX * 4
        let (r, g, b) = (pixels[s], pixels[s + 1], pixels[s + 2])

        for x in 0..<canvas {
            let o = y * bpr + x * 4
            guard pixels[o + 3] == 255 else { continue }
            pixels[o] = r
            pixels[o + 1] = g
            pixels[o + 2] = b
        }
    }

    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let image = CGImage(
            width: canvas,
            height: canvas,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bpr,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else { fatalError("plate image") }
    return image
}

/// The V: flat arm tops, a solid wedge at the point, inner edges parallel to
/// the outer ones.
func glyphPath() -> CGPath {
    let centerX = CGFloat(canvas) / 2
    let halfSpan: CGFloat = 250
    let topY: CGFloat = 268
    let tipY: CGFloat = 772
    let armWidth: CGFloat = 104

    let outerLeft = centerX - halfSpan
    let outerRight = centerX + halfSpan
    let innerLeft = outerLeft + armWidth
    let slope = (tipY - topY) / halfSpan
    let innerTipY = topY + (centerX - innerLeft) * slope

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: CGFloat(canvas) - y) }
    let path = CGMutablePath()
    path.move(to: p(outerLeft, topY))
    path.addLine(to: p(centerX, tipY))
    path.addLine(to: p(outerRight, topY))
    path.addLine(to: p(outerRight - armWidth, topY))
    path.addLine(to: p(centerX, innerTipY))
    path.addLine(to: p(innerLeft, topY))
    path.closeSubpath()
    return path
}

func compose(plate: CGImage, to path: String) {
    guard let ctx = CGContext(
        data: nil,
        width: canvas,
        height: canvas,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("context") }

    let full = CGRect(x: 0, y: 0, width: CGFloat(canvas), height: CGFloat(canvas))
    ctx.draw(plate, in: full)

    let glyph = glyphPath()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: glyphGlow)
    ctx.addPath(glyph)
    ctx.setFillColor(glyphTop)
    ctx.fillPath()
    ctx.restoreGState()

    guard let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [glyphTop, glyphBottom] as CFArray,
        locations: [0, 1]
    ) else { fatalError("gradient") }
    let box = glyph.boundingBox
    ctx.saveGState()
    ctx.addPath(glyph)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: box.midX, y: box.maxY),
        end: CGPoint(x: box.midX, y: box.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    guard let image = ctx.makeImage(),
          let data = NSBitmapImageRep(cgImage: image)
        .representation(using: .png, properties: [:]) else { fatalError("encode") }
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

/// Transparent glyph for the Icon Composer layer and design/ source.
func writeGlyphLayer(to path: String) {
    guard let ctx = CGContext(
        data: nil,
        width: canvas,
        height: canvas,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("context") }

    let glyph = glyphPath()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: glyphGlow)
    ctx.addPath(glyph)
    ctx.setFillColor(glyphTop)
    ctx.fillPath()
    ctx.restoreGState()

    guard let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [glyphTop, glyphBottom] as CFArray,
        locations: [0, 1]
    ) else { fatalError("gradient") }
    let box = glyph.boundingBox
    ctx.saveGState()
    ctx.addPath(glyph)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: box.midX, y: box.maxY),
        end: CGPoint(x: box.midX, y: box.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    guard let image = ctx.makeImage(),
          let data = NSBitmapImageRep(cgImage: image)
        .representation(using: .png, properties: [:]) else { fatalError("encode") }
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

compose(plate: plateOnly(from: "/tmp/orig-icon-1024.png"), to: "/tmp/vmux-light.png")
compose(plate: plateOnly(from: "/tmp/orig-dark-1024.png"), to: "/tmp/vmux-dark.png")
compose(plate: plateOnly(from: "/tmp/orig-debug-1024.png"), to: "/tmp/vmux-debug.png")
writeGlyphLayer(to: "/tmp/vmux-glyph.png")
