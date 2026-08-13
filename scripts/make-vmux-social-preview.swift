import AppKit
import CoreGraphics

// Renders the GitHub social preview card from the app's own glyph layer, so the
// repository link previews match the icon. GitHub renders these at 1280x640 and
// crops toward the centre, so the content stays well inside the edges.
let width = 1280
let height = 640
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

let glyphPath = "design/vmux-icon-v.png"
guard let glyphImage = NSImage(contentsOfFile: glyphPath),
      let glyph = glyphImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("missing \(glyphPath)")
}

guard let ctx = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("context") }

// The icon plate's own gradient, so the card and the app icon read as a pair.
if let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgb(0x303031), rgb(0x141313)] as CFArray,
    locations: [0, 1]
) {
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: CGFloat(height)),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
}

let glyphHeight: CGFloat = 360
let glyphWidth = glyphHeight * CGFloat(glyph.width) / CGFloat(glyph.height)

let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsContext

let wordmark = NSAttributedString(
    string: "vmux",
    attributes: [
        .font: NSFont.systemFont(ofSize: 168, weight: .bold),
        .foregroundColor: NSColor.white,
    ]
)
let tagline = NSAttributedString(
    string: "a cmux fork",
    attributes: [
        .font: NSFont.systemFont(ofSize: 46, weight: .regular),
        .foregroundColor: NSColor(white: 0.62, alpha: 1),
    ]
)

// Centre the glyph and the text as one group, so the card is balanced rather
// than weighted to one side.
let wordmarkSize = wordmark.size()
let taglineSize = tagline.size()
let gap: CGFloat = 56
let textWidth = max(wordmarkSize.width, taglineSize.width)
let groupWidth = glyphWidth + gap + textWidth
let groupOriginX = (CGFloat(width) - groupWidth) / 2

ctx.draw(
    glyph,
    in: CGRect(
        x: groupOriginX,
        y: (CGFloat(height) - glyphHeight) / 2,
        width: glyphWidth,
        height: glyphHeight
    )
)

let textX = groupOriginX + glyphWidth + gap
let blockHeight = wordmarkSize.height + 12 + taglineSize.height
let blockBottom = (CGFloat(height) - blockHeight) / 2
tagline.draw(at: CGPoint(x: textX + 4, y: blockBottom))
wordmark.draw(at: CGPoint(x: textX, y: blockBottom + taglineSize.height + 12))

NSGraphicsContext.restoreGraphicsState()

guard let image = ctx.makeImage(),
      let data = NSBitmapImageRep(cgImage: image)
        .representation(using: .png, properties: [:]) else {
    fatalError("encode")
}
let output = "docs/assets/vmux-social-preview.png"
try! data.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
