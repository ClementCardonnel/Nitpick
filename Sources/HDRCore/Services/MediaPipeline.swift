import Foundation
import UniformTypeIdentifiers

/// Shared input classification (Foundation only — keeps the Core UI-free).
enum MediaPipeline {
    static func supportedKind(for url: URL) -> FileItem.Kind? {
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
              let type = values.contentType else { return nil }
        if type.conforms(to: .movie)
            || type.conforms(to: .video)
            || type.conforms(to: .mpeg4Movie)
            || type.conforms(to: .quickTimeMovie) {
            return .video
        }
        if type.conforms(to: .image) {
            return .still
        }
        return nil
    }
}
