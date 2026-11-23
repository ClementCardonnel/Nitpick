import Foundation
import CoreGraphics
import CoreImage
import CoreVideo

/// The single seam where the tone mapping operator lives. v1 uses the system's
/// native tone mapping (`CISystemToneMap`); the deferred slider will plug in here.
public protocol ToneMapper: Sendable {
    /// Tone maps an extended-range image into an 8-bit sRGB image.
    /// `contentHeadroom` is the source's HDR headroom from metadata when known
    /// (0 = unknown → estimated from the brightest pixel).
    func toneMapToSDR(_ image: CGImage, contentHeadroom: Float) -> CGImage?
    /// Tone maps an HDR pixel buffer into an 8-bit BGRA buffer suitable for encoding.
    func toneMapToSDR(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer?
}

/// Default tone mapper: applies Apple's system tone curve (`CISystemToneMap`,
/// "consistent with other frameworks") targeting SDR (display headroom 1.0,
/// standard dynamic range), then renders to 8-bit sRGB.
///
/// Important: HDR images must be decoded into an *extended* color space
/// (e.g. `extendedSRGB`); rendering them into plain sRGB clamps values above
/// 1.0 and silently destroys the HDR range (that was the "overblown" bug).
public final class CoreGraphicsToneMapper: ToneMapper {
    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    private let extendedSRGB = CGColorSpace(name: CGColorSpace.extendedSRGB)!
    private let ciContext: CIContext

    public init() {
        self.ciContext = CIContext(options: nil)
    }

    public func toneMapToSDR(_ image: CGImage, contentHeadroom: Float) -> CGImage? {
        guard let toned = toneMap(CIImage(cgImage: image), contentHeadroom: contentHeadroom),
              let output = ciContext.createCGImage(toned, from: toned.extent, format: .BGRA8, colorSpace: srgb) else {
            return nil
        }
        return output
    }

    public func toneMapToSDR(_ image: CGImage) -> CGImage? {
        toneMapToSDR(image, contentHeadroom: 0)
    }

    public func toneMapToSDR(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // Prefer the buffer's own headroom metadata (HDR video carries it in its
        // format description attachments); PQ-encoded values are ≤ 1.0, so pixel
        // estimation is meaningless there.
        let headroom = ciImage.contentHeadroom > 1.0 ? ciImage.contentHeadroom : 0
        guard let toned = toneMap(ciImage, contentHeadroom: headroom),
              let sdrCGImage = ciContext.createCGImage(toned, from: ciImage.extent, format: .BGRA8, colorSpace: srgb) else {
            return nil
        }

        var output: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            sdrCGImage.width,
            sdrCGImage.height,
            kCVPixelFormatType_32BGRA,
            nil,
            &output
        ) == kCVReturnSuccess, let output else { return nil }

        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }

        guard let base = CVPixelBufferGetBaseAddress(output),
              let context = CGContext(
                data: base,
                width: sdrCGImage.width,
                height: sdrCGImage.height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(output),
                space: srgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else { return nil }
        context.draw(sdrCGImage, in: CGRect(x: 0, y: 0, width: sdrCGImage.width, height: sdrCGImage.height))
        return output
    }

    /// Applies CISystemToneMap targeting SDR. Returns a tone-mapped CIImage whose
    /// values are within [0, 1].
    private func toneMap(_ input: CIImage, contentHeadroom: Float) -> CIImage? {
        var image = input
        let headroom = contentHeadroom > 1.0 ? contentHeadroom : estimateHeadroom(of: input)
        if headroom > 1.0 {
            image = image.settingContentHeadroom(headroom)
        }
        guard let filter = CIFilter(name: "CISystemToneMap") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(1.0, forKey: "inputDisplayHeadroom") // SDR display
        filter.setValue(CIDynamicRangeOption.standard.rawValue, forKey: "inputPreferredDynamicRange")
        return filter.outputImage
    }

    /// Estimates content headroom (max component) by scanning a downscaled,
    /// unclamped float render in an extended color space (so HDR > 1.0 survives).
    /// ('RGfA' = kCVPixelFormatType_128RGBAFloat.)
    private func estimateHeadroom(of image: CIImage) -> Float {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, extent.isInfinite == false else { return 1.0 }
        let scale = min(1.0, 64.0 / max(extent.width, extent.height))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let width = max(1, Int(extent.width * scale))
        let height = max(1, Int(extent.height * scale))

        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, OSType(0x52476641), nil, &buffer) == kCVReturnSuccess,
              let buffer else { return 1.0 }
        let destination = CIRenderDestination(pixelBuffer: buffer)
        destination.isClamped = false // keep HDR values above 1.0
        destination.colorSpace = extendedSRGB
        _ = try? ciContext.startTask(toRender: scaled, to: destination)

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 1.0 }
        let ptr = base.assumingMemoryBound(to: Float.self)
        let rowFloats = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float>.stride
        var maxValue: Float = 1.0
        for y in 0..<height {
            let row = ptr.advanced(by: y * rowFloats)
            for x in 0..<width {
                let i = x * 4
                maxValue = max(maxValue, row[i], row[i + 1], row[i + 2])
            }
        }
        return max(1.0, maxValue)
    }
}
