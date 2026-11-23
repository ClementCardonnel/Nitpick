import Foundation
import ImageIO
import CoreGraphics
import CoreImage
import UniformTypeIdentifiers

/// Still pipeline: decode (keeping extended range / applying gain maps) and encode.
enum StillPipeline {
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let extendedSRGB = CGColorSpace(name: CGColorSpace.extendedSRGB)!
    private static let ciContext = CIContext(options: nil)

    /// A decoded HDR image plus its content headroom (from gain-map metadata when
    /// available; 0 = unknown).
    struct DecodedHDR {
        let cgImage: CGImage // float, extended sRGB — values may exceed 1.0
        let contentHeadroom: Float
    }

    /// Loads the HDR rendition of the image when the format has one
    /// (gain-map JPEG/HEIC, float TIFF, ProPhoto), otherwise the plain image.
    ///
    /// Primary path: Core Image with `.expandToHDR`, which applies embedded gain
    /// maps and expands to an HDR color space (e.g. P3_PQ). The result is rendered
    /// into an *extended* sRGB float CGImage — rendering into plain sRGB would
    /// clamp values above 1.0 and destroy the HDR range. Fallback: raw ImageIO
    /// decode with the HDR decode request (keeps float formats as-is).
    static func loadHDR(from url: URL) -> DecodedHDR? {
        if let ciImage = CIImage(contentsOf: url, options: [.expandToHDR: true]),
           let cg = ciContext.createCGImage(ciImage, from: ciImage.extent, format: .RGBAf, colorSpace: extendedSRGB) {
            return DecodedHDR(cgImage: cg, contentHeadroom: max(ciImage.contentHeadroom, 0))
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldAllowFloat: true,
            kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR
        ]
        guard let cg = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else { return nil }
        return DecodedHDR(cgImage: cg, contentHeadroom: 0)
    }

    /// Backwards-compatible CGImage-only accessor.
    static func loadHDRCGImage(from url: URL) -> CGImage? {
        loadHDR(from: url)?.cgImage
    }

    /// SDR stills keep the source container family; unknown stills export as HEIC.
    static func outputExtension(for url: URL) -> String {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return "heic" }
        if type.conforms(to: .jpeg) { return "jpg" }
        if type.conforms(to: .png) { return "png" }
        return "heic"
    }

    private static func outputUTI(for url: URL) -> CFString {
        switch outputExtension(for: url) {
        case "jpg": return UTType.jpeg.identifier as CFString
        case "png": return UTType.png.identifier as CFString
        default: return UTType.heic.identifier as CFString
        }
    }

    /// Tone maps the source into an 8-bit SDR file at `destination`.
    static func exportSDR(source: URL, destination: URL, toneMapper: any ToneMapper) throws {
        guard let decoded = loadHDR(from: source) else { throw ExportError.decodeFailed(source) }
        guard let sdr = toneMapper.toneMapToSDR(decoded.cgImage, contentHeadroom: decoded.contentHeadroom) else {
            throw ExportError.toneMapFailed(source)
        }
        guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, outputUTI(for: source), 1, nil) else {
            throw ExportError.writeFailed(destination)
        }
        CGImageDestinationAddImage(dest, sdr, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.writeFailed(destination) }
    }
}
