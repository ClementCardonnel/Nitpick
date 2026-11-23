import Foundation
import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo

/// AVFoundation-based video pipeline: read HDR frames, tone map each to 8-bit SDR,
/// encode H.264 `.mp4`, and pass the audio track through.
enum VideoPipeline {
    /// Pixel format requested from the decoder: half-float RGBA keeps the HDR range.
    /// ('RGhA' = kCVPixelFormatType_64RGBAHalfFloat; the constant is not exported to
    /// Swift under that name in the macOS 26 SDK, the fourcc is stable ABI.)
    private static let hdrPixelFormat = OSType(0x52476841)

    private static var hdrReadSettings: [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: hdrPixelFormat,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
    }

    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// First frame of the video as an extended-range CGImage (left preview pane).
    static func firstFrameHDR(from url: URL) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: hdrReadSettings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }
        guard let sample = output.copyNextSampleBuffer(),
              let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext(options: [.workingColorSpace: srgb])
        return context.createCGImage(ciImage, from: ciImage.extent, format: .RGBAf, colorSpace: srgb)
    }

    /// Exports the whole video as 8-bit SDR H.264 `.mp4` with audio passthrough.
    /// `progress` receives 0...1 for the video pass.
    static func exportSDR(
        source: URL,
        destination: URL,
        toneMapper: any ToneMapper,
        progress: @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack(source)
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let displaySize = naturalSize.applying(preferredTransform)
        let width = Int(displaySize.width.rounded())
        let height = Int(displaySize.height.rounded())
        guard width > 0, height > 0 else { throw ExportError.decodeFailed(source) }
        let duration = (try? await asset.load(.duration)) ?? .positiveInfinity

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: hdrReadSettings)
        guard reader.canAdd(videoOutput) else { throw ExportError.decodeFailed(source) }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderTrackOutput?
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil) // compressed passthrough
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }
        guard reader.startReading() else {
            throw reader.error ?? ExportError.decodeFailed(source)
        }

        do {
            let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ])
            videoInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(videoInput) else { throw ExportError.writeFailed(destination) }
            writer.add(videoInput)

            var audioInput: AVAssetWriterInput?
            if audioOutput != nil {
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
                input.expectsMediaDataInRealTime = false
                if writer.canAdd(input) {
                    writer.add(input)
                    audioInput = input
                }
            }

            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
                ]
            )

            guard writer.startWriting() else { throw writer.error ?? ExportError.writeFailed(destination) }
            writer.startSession(atSourceTime: .zero)

            // Video pass: decode → tone map → encode, frame by frame.
            while reader.status == .reading {
                guard let sample = videoOutput.copyNextSampleBuffer() else { break }
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
                guard let sdrBuffer = toneMapper.toneMapToSDR(pixelBuffer: buffer) else { continue }
                while !videoInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
                adaptor.append(sdrBuffer, withPresentationTime: presentationTime)
                if duration.seconds > 0, duration.seconds.isFinite {
                    progress(min(presentationTime.seconds / duration.seconds, 1))
                }
            }
            videoInput.markAsFinished()

            // Audio pass: passthrough of the compressed samples.
            if let audioOutput, let audioInput {
                while let sample = audioOutput.copyNextSampleBuffer() {
                    while !audioInput.isReadyForMoreMediaData {
                        try await Task.sleep(nanoseconds: 5_000_000)
                    }
                    audioInput.append(sample)
                }
                audioInput.markAsFinished()
            }

            nonisolated(unsafe) let writerForContinuation = writer
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                writerForContinuation.finishWriting {
                    if writerForContinuation.status == .failed {
                        continuation.resume(throwing: writerForContinuation.error ?? ExportError.writeFailed(destination))
                    } else {
                        continuation.resume()
                    }
                }
            }
            reader.cancelReading()
        } catch {
            reader.cancelReading()
            try? FileManager.default.removeItem(at: destination) // never leave a partial file
            throw error
        }
    }
}
