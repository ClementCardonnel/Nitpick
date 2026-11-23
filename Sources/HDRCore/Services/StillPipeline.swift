import Foundation
import ImageIO
import CoreGraphics
import CoreImage
import UniformTypeIdentifiers

/// Still pipeline: decode (keeping extended range / applying gain maps) and encode.
enum StillPipeline {
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    /// Loads the HDR rendition of the image when the format has one
    /// (gain-map JPEG/HEIC, float TIFF, ProPhoto), otherwise the plain image.
    ///
    /// Primary path: Core Image with `.expandToHDR`, which applies embedded gain
    /// maps and expands to an extended-range color space. Fallback: raw ImageIO
    /// decode with the HDR decode request (keeps float formats as-is).
    static func loadHDRCGImage(from url: URL) -> CGImage? {
        if let ciImage = CIImage(contentsOf: url, options: [.expandToHDR: true]),
           let cg = ciContext.createCGImage(ciImage, from: ciImage.extent, format: .RGBAf, colorSpace: srgb) {
            return cg
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldAllowFloat: true,
            kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR
        ]
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
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
        guard let hdr = loadHDRCGImage(from: source) else { throw ExportError.decodeFailed(source) }
        guard let sdr = toneMapper.toneMapToSDR(hdr) else { throw ExportError.toneMapFailed(source) }
        guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, outputUTI(for: source), 1, nil) else {
            throw ExportError.writeFailed(destination)
        }
        CGImageDestinationAddImage(dest, sdr, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.writeFailed(destination) }
    }
}
