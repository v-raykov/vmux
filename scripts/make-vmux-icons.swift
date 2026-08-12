import AppKit
import CoreGraphics

// Reproduces the original cmux icon treatment with a red V: same plate
// geometry, same gradient plate, same soft same-hue glyph glow, same variant
// bands. Colors were sampled from the original artwork.
let canvas: CGFloat = 1024
let plateInset: CGFloat = 96
let plateCornerRadius: CGFloat = 185

// sRGB throughout: CGColor(red:green:blue:) builds a generic-RGB color, which
// the compositor lightens on its way into the bitmap, so sampled output no
// longer matches the artwork these values were taken from.
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

let glyphTop = rgb(0xFF2D05)
let glyphBottom = rgb(0xFF2E63)
let glyphGlow = rgb(0xFF4526, alpha: 0.85)

enum Backdrop {
    case platedLight
    case platedDark
    case fullBleedWhite
}

struct Band {
    let fill: CGColor
    let topY: CGFloat
    let text: String
    let fontSize: CGFloat
}

func context() -> CGContext {
    guard let context = CGContext(
        data: nil,
        width: Int(canvas),
        height: Int(canvas),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("context") }
    return context
}

func write(_ image: CGImage, to path: String) {
    guard let data = NSBitmapImageRep(cgImage: image)
        .representation(using: .png, properties: [:]) else { fatalError("encode") }
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

func platePath() -> CGPath {
    CGPath(
        roundedRect: CGRect(
            x: plateInset,
            y: plateInset,
            width: canvas - plateInset * 2,
            height: canvas - plateInset * 2
        ),
        cornerWidth: plateCornerRadius,
        cornerHeight: plateCornerRadius,
        transform: nil
    )
}

/// The V, as a closed outline: flat arm tops, a solid wedge at the point, and
/// inner edges parallel to the outer ones.
func glyphPath() -> CGPath {
    // Sized against the original chevron's footprint (36% wide, 51% tall) so the
    // V carries the same weight in the dock rather than reading squat.
    let centerX = canvas / 2
    let halfSpan: CGFloat = 258
    let topY: CGFloat = 265
    let tipY: CGFloat = 775
    let armWidth: CGFloat = 146

    let outerLeft = centerX - halfSpan
    let outerRight = centerX + halfSpan
    let innerLeft = outerLeft + armWidth
    // Inner edges share the outer slope, so the inner vertex sits higher.
    let slope = (tipY - topY) / halfSpan
    let innerTipY = topY + (centerX - innerLeft) * slope

    let path = CGMutablePath()
    // Flipped vertically: CoreGraphics origin is bottom-left.
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: canvas - y) }
    path.move(to: p(outerLeft, topY))
    path.addLine(to: p(centerX, tipY))
    path.addLine(to: p(outerRight, topY))
    path.addLine(to: p(outerRight - armWidth, topY))
    path.addLine(to: p(centerX, innerTipY))
    path.addLine(to: p(innerLeft, topY))
    path.closeSubpath()
    return path
}

func drawVerticalGradient(
    in ctx: CGContext,
    clipTo path: CGPath,
    stops: [(CGFloat, CGColor)],
    rect: CGRect
) {
    guard let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: stops.map(\.1) as CFArray,
        locations: stops.map(\.0)
    ) else { return }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()
}

func makeIcon(backdrop: Backdrop, band: Band?) -> CGImage {
    let ctx = context()
    let full = CGRect(x: 0, y: 0, width: canvas, height: canvas)

    switch backdrop {
    case .fullBleedWhite:
        ctx.setFillColor(rgb(0xFFFFFF))
        ctx.fill(full)
    case .platedLight, .platedDark:
        let path = platePath()
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -8),
            blur: 24,
            color: rgb(0x000000, alpha: 0.35)
        )
        ctx.addPath(path)
        ctx.setFillColor(rgb(0x000000))
        ctx.fillPath()
        ctx.restoreGState()

        // Sampled down the original plate. The bright rim collapses within the
        // first ~13% of the height; a plain two-stop gradient smears that
        // highlight over the whole plate and reads washed out.
        let darkStops: [(CGFloat, CGColor)] = [
            (0.00, rgb(0x656466)),
            (0.05, rgb(0x5F6161)),
            (0.13, rgb(0x303031)),
            (0.29, rgb(0x2B292B)),
            (0.50, rgb(0x242323)),
            (0.73, rgb(0x1B1B1A)),
            (0.88, rgb(0x151614)),
            (1.00, rgb(0x141313)),
        ]
        let lightStops: [(CGFloat, CGColor)] = [
            (0.00, rgb(0xFFFFFF)),
            (0.13, rgb(0xFFFFFF)),
            (0.50, rgb(0xF6F6F5)),
            (0.88, rgb(0xEDEDEC)),
            (1.00, rgb(0xECECEC)),
        ]
        drawVerticalGradient(
            in: ctx,
            clipTo: path,
            stops: backdrop == .platedLight ? lightStops : darkStops,
            rect: path.boundingBox
        )
    }

    // Glyph: glow first, then the gradient fill inside the same outline.
    let glyph = glyphPath()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 42, color: glyphGlow)
    ctx.addPath(glyph)
    ctx.setFillColor(glyphTop)
    ctx.fillPath()
    ctx.restoreGState()

    drawVerticalGradient(
        in: ctx,
        clipTo: glyph,
        stops: [(0, glyphTop), (1, glyphBottom)],
        rect: glyph.boundingBox
    )

    if let band {
        let bandRect = CGRect(x: 0, y: 0, width: canvas, height: canvas - band.topY)
        ctx.setFillColor(band.fill)
        ctx.fill(bandRect)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: band.fontSize, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let line = NSAttributedString(string: band.text, attributes: attributes)
        let size = line.size()
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        line.draw(at: CGPoint(
            x: (canvas - size.width) / 2,
            y: bandRect.midY - size.height / 2
        ))
        NSGraphicsContext.restoreGraphicsState()
    }

    guard let image = ctx.makeImage() else { fatalError("image") }
    return image
}

/// Transparent glyph for the Icon Composer layer, which supplies its own plate.
func makeGlyphOnly() -> CGImage {
    let ctx = context()
    let glyph = glyphPath()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 42, color: glyphGlow)
    ctx.addPath(glyph)
    ctx.setFillColor(glyphTop)
    ctx.fillPath()
    ctx.restoreGState()
    drawVerticalGradient(
        in: ctx,
        clipTo: glyph,
        stops: [(0, glyphTop), (1, glyphBottom)],
        rect: glyph.boundingBox
    )
    guard let image = ctx.makeImage() else { fatalError("glyph") }
    return image
}

write(makeIcon(backdrop: .platedLight, band: nil), to: "/tmp/vmux-light.png")
write(makeIcon(backdrop: .platedDark, band: nil), to: "/tmp/vmux-dark.png")
write(
    makeIcon(
        backdrop: .platedLight,
        band: Band(fill: rgb(0xFF6B00), topY: 880, text: "DEV", fontSize: 104)
    ),
    to: "/tmp/vmux-debug.png"
)
write(
    makeIcon(
        backdrop: .fullBleedWhite,
        band: Band(fill: rgb(0x8C3CDC), topY: 839, text: "NIGHTLY", fontSize: 104)
    ),
    to: "/tmp/vmux-nightly.png"
)
write(makeGlyphOnly(), to: "/tmp/vmux-glyph.png")
