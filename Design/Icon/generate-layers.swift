// Renders the Nitpick app icon layers (1024×1024 PNGs) used by AppIcon.icon.
// Usage: swift Design/Icon/generate-layers.swift <output-directory>
//
// Concept: a split sun. Left = blown-out HDR (pale, glowing), right = tamed SDR
// (dark, textured photosphere with a bright limb and coronal loops).
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let center = CGPoint(x: 512, y: 512)
let radius: CGFloat = 300
let space = CGColorSpace(name: CGColorSpace.displayP3)!
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

// Deterministic randomness so re-running gives the same artwork.
var seed: UInt64 = 0x5EED_2026
func random() -> CGFloat {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat((seed >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha
    ])!
}

/// A transparent canvas in top-left-origin coordinates.
func canvas(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    return ctx.makeImage()!
}

/// Draws a full-canvas image upright (CGContext.draw would flip it in our y-down canvas).
func drawUpright(_ ctx: CGContext, _ image: CGImage) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    ctx.restoreGState()
}

func gaussianBlur(_ image: CGImage, _ amount: Double) -> CGImage {
    let ci = CIImage(cgImage: image).clampedToExtent().applyingGaussianBlur(sigma: amount)
        .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    return CIContext().createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: space)!
}

func save(_ image: CGImage, _ name: String) {
    let url = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote", url.path)
}

let leftHalf = CGRect(x: 0, y: 0, width: 512, height: size)
let rightHalf = CGRect(x: 512, y: 0, width: 512, height: size)
let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

// MARK: Background — warm HDR half with its glow (the right half is the canvas fill).
save(canvas { ctx in
    ctx.clip(to: leftHalf)
    let sky = CGGradient(colorsSpace: space, colors: [
        color(0x7A3A6E), color(0xC9475A), color(0xE8604A), color(0xF08A4C)
    ] as CFArray, locations: [0, 0.35, 0.7, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(size)), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [
        color(0xFFD86B, 0.95), color(0xFFB347, 0.55), color(0xF5823F, 0.0)
    ] as CFArray, locations: [0, 0.45, 1])!
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: radius * 0.9,
                           endCenter: center, endRadius: radius * 1.75, options: [])
}, "background-hdr.png")

// MARK: HDR half-sun — pale, blown out.
save(canvas { ctx in
    ctx.clip(to: leftHalf)
    ctx.addEllipse(in: disc)
    ctx.clip()
    let face = CGGradient(colorsSpace: space, colors: [
        color(0xFFFBE3), color(0xFFF1B8), color(0xFFDE7A)
    ] as CFArray, locations: [0, 0.75, 1])!
    ctx.drawRadialGradient(face, startCenter: CGPoint(x: center.x - 40, y: center.y - 30), startRadius: 0,
                           endCenter: center, endRadius: radius, options: [])
}, "sun-hdr.png")

// MARK: SDR half-sun — dark photosphere, granulation, active regions, bright limb.
let granules = gaussianBlur(canvas { ctx in
    ctx.addEllipse(in: disc)
    ctx.clip()
    ctx.setFillColor(color(0x1E0806))
    ctx.fill(disc)
    // Fine mottling.
    for _ in 0..<9000 {
        let x = center.x - radius + random() * radius * 2
        let y = center.y - radius + random() * radius * 2
        let r = 1 + random() * 2.6
        ctx.setFillColor(color(0x5A1C0C, 0.25 + random() * 0.35))
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
    // Faint plasma filaments.
    for _ in 0..<160 {
        let p = CGPoint(x: center.x - radius + random() * radius * 2, y: center.y - radius + random() * radius * 2)
        let angle = random() * .pi * 2
        let length = 10 + random() * 30
        ctx.setStrokeColor(color(0xB8401A, 0.18 + random() * 0.25))
        ctx.setLineWidth(0.8 + random())
        ctx.move(to: p)
        ctx.addQuadCurve(
            to: CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length),
            control: CGPoint(x: p.x + cos(angle + 0.9) * length * 0.5, y: p.y + sin(angle + 0.9) * length * 0.5))
        ctx.strokePath()
    }
    // Active regions: bright cores with short filaments.
    for region in [CGPoint(x: 760, y: 420), CGPoint(x: 625, y: 690)] {
        for _ in 0..<12 {
            let angle = random() * .pi * 2
            let length = 8 + random() * 18
            ctx.setStrokeColor(color(0xFF9A3C, 0.3))
            ctx.setLineWidth(1.5 + random() * 1.5)
            ctx.move(to: region)
            ctx.addQuadCurve(
                to: CGPoint(x: region.x + cos(angle) * length, y: region.y + sin(angle) * length),
                control: CGPoint(x: region.x + cos(angle + 0.6) * length * 0.6, y: region.y + sin(angle + 0.6) * length * 0.6))
            ctx.strokePath()
        }
        ctx.setFillColor(color(0xFFD27A, 0.9))
        ctx.fillEllipse(in: CGRect(x: region.x - 4, y: region.y - 4, width: 8, height: 8))
    }
}, 0.9)

save(canvas { ctx in
    ctx.clip(to: rightHalf)
    ctx.saveGState()
    ctx.addEllipse(in: disc)
    ctx.clip()
    drawUpright(ctx, granules)
    // Limb brightening: an orange rim that fades inward.
    let limb = CGGradient(colorsSpace: space, colors: [
        color(0xFF7A1A, 0), color(0xFF6A14, 0.18), color(0xFF9A2E, 0.95)
    ] as CFArray, locations: [0, 0.9, 1])!
    ctx.drawRadialGradient(limb, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    ctx.restoreGState()
    ctx.setStrokeColor(color(0xFFB347))
    ctx.setLineWidth(5)
    ctx.strokeEllipse(in: disc.insetBy(dx: 2.5, dy: 2.5))
}, "sun-sdr.png")

// MARK: Corona — loops and glow spilling past the SDR limb (drawn additively).
let loops = canvas { ctx in
    ctx.clip(to: rightHalf)
    ctx.setLineCap(.round)
    func loop(at angle: CGFloat, span: CGFloat, height: CGFloat, strands: Int) {
        for i in 0..<strands {
            let a0 = angle - span / 2 + CGFloat(i) * 0.012
            let a1 = angle + span / 2 + CGFloat(i) * 0.012
            let p0 = CGPoint(x: center.x + cos(a0) * radius, y: center.y + sin(a0) * radius)
            let p1 = CGPoint(x: center.x + cos(a1) * radius, y: center.y + sin(a1) * radius)
            let h = height * (0.75 + random() * 0.35)
            let c0 = CGPoint(x: center.x + cos(a0) * (radius + h), y: center.y + sin(a0) * (radius + h))
            let c1 = CGPoint(x: center.x + cos(a1) * (radius + h), y: center.y + sin(a1) * (radius + h))
            ctx.setStrokeColor(color(0xFFB050, 0.5 + random() * 0.4))
            ctx.setLineWidth(1.2 + random() * 1.8)
            ctx.move(to: p0)
            ctx.addCurve(to: p1, control1: c0, control2: c1)
            ctx.strokePath()
        }
    }
    loop(at: -.pi * 0.22, span: 0.26, height: 140, strands: 6)   // big loop, upper right
    loop(at: -.pi * 0.31, span: 0.07, height: 60, strands: 3)
    loop(at: .pi * 0.06, span: 0.06, height: 70, strands: 4)     // flare, right edge
    loop(at: -.pi * 0.06, span: 0.04, height: 30, strands: 3)
}
save(canvas { ctx in
    drawUpright(ctx, gaussianBlur(loops, 7))
    drawUpright(ctx, gaussianBlur(loops, 3))
    drawUpright(ctx, loops)
    // Thin outer glow hugging the limb.
    ctx.clip(to: rightHalf)
    let corona = CGGradient(colorsSpace: space, colors: [
        color(0xFF8A2A, 0.55), color(0xFF6A1A, 0.0)
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(corona, startCenter: center, startRadius: radius,
                           endCenter: center, endRadius: radius + 46, options: [])
}, "corona.png")
