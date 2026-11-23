import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// ImageIO-based still pipeline: decode (keeping extended range) and encode.
enum StillPipeline {
    /// Loads the HDR rendition of the image when the format has one
    /// (gain-map JPEG, 10-bit HEIC, ProPhoto), otherwise the plain image.
    static func loadHDRCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // Ask ImageIO for the HDR rendition (gain map / extended range) when the
        // format has one; plain SDR sources decode normally.
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
