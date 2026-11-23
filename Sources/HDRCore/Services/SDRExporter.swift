import Foundation

public enum ExportError: LocalizedError, CustomStringConvertible, Sendable {
    case decodeFailed(URL)
    case toneMapFailed(URL)
    case writeFailed(URL)
    case noVideoTrack(URL)

    public var description: String {
        switch self {
        case .decodeFailed(let url): return "Could not decode \(url.lastPathComponent)"
        case .toneMapFailed(let url): return "Tone mapping failed for \(url.lastPathComponent)"
        case .writeFailed(let url): return "Could not write \(url.lastPathComponent)"
        case .noVideoTrack(let url): return "No video track in \(url.lastPathComponent)"
        }
    }

    /// Surfaces `description` through `localizedDescription` in the UI.
    public var errorDescription: String? { description }
}

public protocol SDRExporter: Sendable {
    /// Exports every item into `folder`. Cancellation is checked between files:
    /// the in-flight file always finishes, already-exported files are kept.
    func export(
        items: [FileItem],
        to folder: URL,
        progress: @Sendable (ExportProgress) -> Void,
        isCancelled: @Sendable () -> Bool
    ) async -> ExportSummary
}

public final class LiveSDRExporter: SDRExporter {
    private let toneMapper: any ToneMapper

    public init(toneMapper: any ToneMapper) {
        self.toneMapper = toneMapper
    }

    public func export(
        items: [FileItem],
        to folder: URL,
        progress: @Sendable (ExportProgress) -> Void,
        isCancelled: @Sendable () -> Bool
    ) async -> ExportSummary {
        var succeeded: [String] = []
        var failed: [ExportFailure] = []
        let total = items.count
        var completed = 0

        for item in items {
            if isCancelled() { break }
            progress(ExportProgress(completed: completed, total: total, currentFileName: item.displayName))
            let destination = Self.destinationURL(for: item, in: folder)
            do {
                switch item.kind {
                case .still:
                    try StillPipeline.exportSDR(source: item.url, destination: destination, toneMapper: toneMapper)
                case .video:
                    try await VideoPipeline.exportSDR(source: item.url, destination: destination, toneMapper: toneMapper) { _ in }
                }
                succeeded.append(destination.lastPathComponent)
            } catch {
                failed.append(ExportFailure(fileName: item.displayName, message: error.localizedDescription))
                try? FileManager.default.removeItem(at: destination)
            }
            completed += 1
            progress(ExportProgress(completed: completed, total: total, currentFileName: ""))
        }
        return ExportSummary(succeeded: succeeded, failed: failed)
    }

    /// `name_SDR.ext`, never overwriting: collisions get a numeric suffix.
    static func destinationURL(for item: FileItem, in folder: URL) -> URL {
        let base = item.url.deletingPathExtension().lastPathComponent
        let ext = item.kind == .video ? "mp4" : StillPipeline.outputExtension(for: item.url)
        var candidate = folder.appendingPathComponent("\(base)_SDR.\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)_SDR \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
