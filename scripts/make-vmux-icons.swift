import AppKit
import CoreGraphics

// Derives the vmux icons from the shipped cmux artwork, so the plate is the
// original's pixels and the glyph is the original chevron itself: hue-mapped
// from blue to red and rotated a quarter turn so it points down.
let canvas = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

// Where the chevron sat in the icon, with a margin for its glow. Only this
// window is repainted, so the plate's rim and falloff stay untouched.
let patchRect = (minX: 300, maxX: 780, minY: 210, maxY: 830)

// The Figma layer is authored larger than the icon; this is the scale the
// repo's dark-icon generator already used to land it on the 1024pt canvas.
let layerScale: CGFloat = 0.7996

func loadRGBA(_ path: String, width: Int, height: Int) -> [UInt8] {
    guard let image = NSImage(contentsOfFile: path),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { fatalError("load \(path)") }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    guard let data = ctx.data else { fatalError("pixels") }
    return Array(UnsafeBufferPointer(
        start: data.assumingMemoryBound(to: UInt8.self),
        count: width * 4 * height
    ))
}

func makeImage(_ pixels: [UInt8], width: Int, height: Int) -> CGImage {
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
          ) else { fatalError("image") }
    return image
}

func writePNG(_ image: CGImage, to path: String) {
    guard let data = NSBitmapImageRep(cgImage: image)
        .representation(using: .png, properties: [:]) else { fatalError("encode") }
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

// MARK: - Colour

func rgbToHSV(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
    let maxV = max(r, g, b), minV = min(r, g, b)
    let delta = maxV - minV
    var h = 0.0
    if delta > 0 {
        if maxV == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if maxV == g { h = (b - r) / delta + 2 }
        else { h = (r - g) / delta + 4 }
        h /= 6
        if h < 0 { h += 1 }
    }
    return (h, maxV == 0 ? 0 : delta / maxV, maxV)
}

func hsvToRGB(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
    if s == 0 { return (v, v, v) }
    let sector = (h - floor(h)) * 6
    let i = floor(sector)
    let f = sector - i
    let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
    switch Int(i) % 6 {
    case 0: return (v, t, p)
    case 1: return (q, v, p)
    case 2: return (p, v, t)
    case 3: return (p, q, v)
    case 4: return (t, p, v)
    default: return (v, p, q)
    }
}

/// Maps the chevron's cyan-to-indigo ramp onto red-to-pink, keeping every
/// pixel's saturation and brightness so the gradient and glow survive intact.
func recolored(_ pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
    let cyanHue = 0.53, indigoHue = 0.64
    let redHue = 0.035, pinkHue = 0.95 - 1.0  // wrap below zero, unwrapped later
    var out = pixels
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let a = Double(pixels[i + 3]) / 255
        guard a > 0 else { continue }
        // Premultiplied: recover straight colour before converting.
        let r = Double(pixels[i]) / 255 / a
        let g = Double(pixels[i + 1]) / 255 / a
        let b = Double(pixels[i + 2]) / 255 / a
        let (h, s, v) = rgbToHSV(min(r, 1), min(g, 1), min(b, 1))
        let t = (h - cyanHue) / (indigoHue - cyanHue)
        let mapped = redHue + t * (pinkHue - redHue)
        let (nr, ng, nb) = hsvToRGB(mapped, s, v)
        out[i] = UInt8(max(0, min(255, nr * a * 255)))
        out[i + 1] = UInt8(max(0, min(255, ng * a * 255)))
        out[i + 2] = UInt8(max(0, min(255, nb * a * 255)))
    }
    return out
}

// MARK: - Plate

/// Erases the chevron by repainting only its window, interpolating each row
/// between plate colours sampled just outside the glyph on either side.
func plateOnly(from path: String) -> CGImage {
    var pixels = loadRGBA(path, width: canvas, height: canvas)
    let bpr = canvas * 4
    let leftX = patchRect.minX - 20
    let rightX = patchRect.maxX + 20

    for y in patchRect.minY...patchRect.maxY {
        let l = y * bpr + leftX * 4
        let r = y * bpr + rightX * 4
        guard pixels[l + 3] == 255, pixels[r + 3] == 255 else { continue }
        let left = (Double(pixels[l]), Double(pixels[l + 1]), Double(pixels[l + 2]))
        let right = (Double(pixels[r]), Double(pixels[r + 1]), Double(pixels[r + 2]))

        for x in patchRect.minX...patchRect.maxX {
            let o = y * bpr + x * 4
            guard pixels[o + 3] == 255 else { continue }
            let t = Double(x - leftX) / Double(rightX - leftX)
            pixels[o] = UInt8(left.0 + (right.0 - left.0) * t)
            pixels[o + 1] = UInt8(left.1 + (right.1 - left.1) * t)
            pixels[o + 2] = UInt8(left.2 + (right.2 - left.2) * t)
        }
    }
    return makeImage(pixels, width: canvas, height: canvas)
}

// MARK: - Glyph

let layerWidth = 639, layerHeight = 818
let redLayer = makeImage(
    recolored(
        loadRGBA("/tmp/orig-chevron-layer.png", width: layerWidth, height: layerHeight),
        width: layerWidth,
        height: layerHeight
    ),
    width: layerWidth,
    height: layerHeight
)

/// Draws the recoloured chevron rotated a quarter turn clockwise, so it points
/// down, centred on the icon canvas.
func drawGlyph(in ctx: CGContext) {
    let w = CGFloat(layerWidth) * layerScale
    let h = CGFloat(layerHeight) * layerScale
    ctx.saveGState()
    ctx.translateBy(x: CGFloat(canvas) / 2, y: CGFloat(canvas) / 2)
    ctx.rotate(by: -.pi / 2)
    ctx.draw(redLayer, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
    ctx.restoreGState()
}

func context() -> CGContext {
    guard let ctx = CGContext(
        data: nil,
        width: canvas,
        height: canvas,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("context") }
    return ctx
}

func compose(plate: CGImage, to path: String) {
    let ctx = context()
    ctx.draw(plate, in: CGRect(x: 0, y: 0, width: CGFloat(canvas), height: CGFloat(canvas)))
    drawGlyph(in: ctx)
    guard let image = ctx.makeImage() else { fatalError("compose") }
    writePNG(image, to: path)
}

compose(plate: plateOnly(from: "/tmp/orig-icon-1024.png"), to: "/tmp/vmux-light.png")
compose(plate: plateOnly(from: "/tmp/orig-dark-1024.png"), to: "/tmp/vmux-dark.png")
compose(plate: plateOnly(from: "/tmp/orig-debug-1024.png"), to: "/tmp/vmux-debug.png")

let glyphCtx = context()
drawGlyph(in: glyphCtx)
guard let glyphImage = glyphCtx.makeImage() else { fatalError("glyph") }
writePNG(glyphImage, to: "/tmp/vmux-glyph.png")
