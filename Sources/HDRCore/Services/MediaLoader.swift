import Foundation
import CoreGraphics

public protocol MediaLoader: Sendable {
    /// Decodes the file and renders the HDR + SDR static previews.
    func loadPreviews(for url: URL) async -> LoadResult
}

public final class LiveMediaLoader: MediaLoader {
    private let toneMapper: any ToneMapper

    public init(toneMapper: any ToneMapper) {
        self.toneMapper = toneMapper
    }

    public func loadPreviews(for url: URL) async -> LoadResult {
        guard let kind = MediaPipeline.supportedKind(for: url) else {
            return .failure("Unsupported format")
        }
        switch kind {
        case .still:
            guard let decoded = StillPipeline.loadHDR(from: url) else {
                return .failure("Could not decode image")
            }
            return .success(FileItem.Previews(
                hdr: decoded.cgImage,
                sdr: toneMapper.toneMapToSDR(decoded.cgImage, contentHeadroom: decoded.contentHeadroom)
            ))
        case .video:
            guard let decoded = await VideoPipeline.firstFrameHDR(from: url) else {
                return .failure("Could not decode video")
            }
            return .success(FileItem.Previews(
                hdr: decoded.cgImage,
                sdr: toneMapper.toneMapToSDR(decoded.cgImage, contentHeadroom: decoded.contentHeadroom)
            ))
        }
    }
}
