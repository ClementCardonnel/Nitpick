import Foundation
import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import ImageIO

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

    private static let extendedSRGB = CGColorSpace(name: CGColorSpace.extendedSRGB)!

    /// First frame of the video as an extended-range CGImage (left preview pane),
    /// plus its content headroom from the format description when present.
    static func firstFrameHDR(from url: URL) async -> StillPipeline.DecodedHDR? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: hdrReadSettings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }
        guard let sample = output.copyNextSampleBuffer(),
              let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let decoded = CIImage(cvPixelBuffer: buffer)
        // Frames are stored in the sensor's orientation; the track's transform says
        // how to display them (e.g. portrait iPhone video is landscape + 90°).
        let ciImage = decoded.oriented(orientation(for: transform))
        let context = CIContext(options: nil)
        // Render into extended sRGB so HDR values above 1.0 survive.
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent, format: .RGBAf, colorSpace: extendedSRGB) else { return nil }
        return StillPipeline.DecodedHDR(cgImage: cg, contentHeadroom: max(decoded.contentHeadroom, 0))
    }

    /// Maps a track's `preferredTransform` (y-down rotation) to the image
    /// orientation that displays its frames upright. Mirrored transforms are rare
    /// for camera footage and fall back to `.up`.
    static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a.rounded(), transform.b.rounded(), transform.c.rounded(), transform.d.rounded()) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
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
        // Encode frames in their stored (natural) orientation and carry the track's
        // transform over to the output, exactly like the source. (Applying the
        // transform to the size yields negative dimensions for rotated video.)
        let width = Int(naturalSize.width.rounded())
        let height = Int(naturalSize.height.rounded())
        guard width > 0, height > 0 else { throw ExportError.decodeFailed(source) }
        let duration = (try? await asset.load(.duration)) ?? .positiveInfinity

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: hdrReadSettings)
        guard reader.canAdd(videoOutput) else { throw ExportError.decodeFailed(source) }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioFormatHint: CMFormatDescription?
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
            audioFormatHint = try? await audioTrack.load(.formatDescriptions).first
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
            videoInput.transform = preferredTransform
            guard writer.canAdd(videoInput) else { throw ExportError.writeFailed(destination) }
            writer.add(videoInput)

            var audioInput: AVAssetWriterInput?
            if audioOutput != nil {
                // Passthrough into MP4 needs the source format, or canAdd rejects
                // the input and the audio is silently dropped.
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormatHint)
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

            // Interleave video (decode → tone map → encode) and audio (passthrough):
            // AVAssetWriter wants both tracks fed together and can stop accepting
            // one input until the other catches up, so a video-then-audio pass
            // could stall forever.
            var videoDone = false
            var audioDone = audioInput == nil
            while !(videoDone && audioDone) {
                try Task.checkCancellation()
                var madeProgress = false
                if !videoDone, videoInput.isReadyForMoreMediaData {
                    madeProgress = true
                    if let sample = videoOutput.copyNextSampleBuffer() {
                        if let buffer = CMSampleBufferGetImageBuffer(sample),
                           let sdrBuffer = toneMapper.toneMapToSDR(pixelBuffer: buffer) {
                            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
                            adaptor.append(sdrBuffer, withPresentationTime: presentationTime)
                            if duration.seconds > 0, duration.seconds.isFinite {
                                progress(min(presentationTime.seconds / duration.seconds, 1))
                            }
                        }
                    } else {
                        videoInput.markAsFinished()
                        videoDone = true
                    }
                }
                if !audioDone, let audioOutput, let audioInput, audioInput.isReadyForMoreMediaData {
                    madeProgress = true
                    if let sample = audioOutput.copyNextSampleBuffer() {
                        audioInput.append(sample)
                    } else {
                        audioInput.markAsFinished()
                        audioDone = true
                    }
                }
                if writer.status == .failed { throw writer.error ?? ExportError.writeFailed(destination) }
                if !madeProgress { try await Task.sleep(nanoseconds: 5_000_000) }
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
