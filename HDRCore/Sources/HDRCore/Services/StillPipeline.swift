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
        /// The SDR color space to tone map into: the source's own when it is an
        /// SDR space (keeps e.g. Display P3 gamut), BT.709 for video.
        let sdrColorSpace: CGColorSpace
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
        let sdrSpace = sdrColorSpace(of: url)
        // Orientation is applied to the pixels so previews are upright; the export
        // then writes orientation 1.
        if let ciImage = CIImage(contentsOf: url, options: [.expandToHDR: true, .applyOrientationProperty: true]),
           let cg = ciContext.createCGImage(ciImage, from: ciImage.extent, format: .RGBAf, colorSpace: extendedSRGB) {
            return DecodedHDR(cgImage: cg, contentHeadroom: max(ciImage.contentHeadroom, 0), sdrColorSpace: sdrSpace)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldAllowFloat: true,
            kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR
        ]
        guard let cg = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else { return nil }
        return DecodedHDR(cgImage: cg, contentHeadroom: 0, sdrColorSpace: sdrSpace)
    }

    /// The source's SDR base color space (e.g. Display P3 for iPhone photos), or
    /// Display P3 when the source is itself encoded in an HDR space (PQ/HLG/extended).
    static func sdrColorSpace(of url: URL) -> CGColorSpace {
        let fallback = CGColorSpace(name: CGColorSpace.displayP3)!
        guard let space = CIImage(contentsOf: url)?.colorSpace,
              space.model == .rgb,
              !CGColorSpaceUsesITUR_2100TF(space),
              !CGColorSpaceUsesExtendedRange(space) else { return fallback }
        return space
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

    /// The source's metadata (EXIF, GPS, TIFF, maker notes…) for the SDR copy, at
    /// maximum quality. Orientation is reset because the pixels are already upright;
    /// the HDR gain map is an auxiliary image and is simply not carried over.
    static func exportProperties(from url: URL) -> [CFString: Any] {
        var properties: [CFString: Any] = [:]
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let copied = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            properties = copied
        }
        // Let the destination derive these from the new pixels / color space.
        for key in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyDepth,
                    kCGImagePropertyProfileName, kCGImagePropertyColorModel, kCGImagePropertyHasAlpha] {
            properties.removeValue(forKey: key)
        }
        properties[kCGImagePropertyOrientation] = 1
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        properties[kCGImageDestinationLossyCompressionQuality] = 1.0
        return properties
    }

    /// Tone maps the source into an 8-bit SDR file at `destination`.
    static func exportSDR(source: URL, destination: URL, toneMapper: any ToneMapper) throws {
        guard let decoded = loadHDR(from: source) else { throw ExportError.decodeFailed(source) }
        guard let sdr = toneMapper.toneMapToSDR(
            decoded.cgImage, contentHeadroom: decoded.contentHeadroom, colorSpace: decoded.sdrColorSpace
        ) else {
            throw ExportError.toneMapFailed(source)
        }
        guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, outputUTI(for: source), 1, nil) else {
            throw ExportError.writeFailed(destination)
        }
        CGImageDestinationAddImage(dest, sdr, exportProperties(from: source) as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.writeFailed(destination) }
    }
}
