import Foundation
import CoreGraphics

/// One file in the queue.
public struct FileItem: Identifiable {
    public enum Kind: String, Sendable {
        case still
        case video
    }

    public enum Status: Sendable {
        case loading
        case ready
        case error(String)
    }

    /// Static previews rendered by the Core (CGImage keeps the module UI-free).
    public struct Previews {
        public let hdr: CGImage?
        public let sdr: CGImage?
        public init(hdr: CGImage?, sdr: CGImage?) {
            self.hdr = hdr
            self.sdr = sdr
        }
    }

    public let id: UUID
    public let url: URL
    public let displayName: String
    public let kind: Kind
    public var status: Status
    public var previews: Previews?

    public init(url: URL, kind: Kind) {
        self.id = UUID()
        self.url = url
        self.displayName = url.lastPathComponent
        self.kind = kind
        self.status = .loading
        self.previews = nil
    }
}

extension FileItem: @unchecked Sendable {}
extension FileItem.Previews: @unchecked Sendable {}

public struct ExportProgress: Equatable, Sendable {
    public var completed: Int
    public var total: Int
    public var currentFileName: String
    public init(completed: Int, total: Int, currentFileName: String) {
        self.completed = completed
        self.total = total
        self.currentFileName = currentFileName
    }
}

public struct ExportFailure: Equatable, Sendable {
    public var fileName: String
    public var message: String
    public init(fileName: String, message: String) {
        self.fileName = fileName
        self.message = message
    }
}

public struct ExportSummary: Equatable, Sendable {
    /// Exported files, in export order.
    public var succeeded: [URL]
    public var failed: [ExportFailure]
    public init(succeeded: [URL], failed: [ExportFailure]) {
        self.succeeded = succeeded
        self.failed = failed
    }
}

/// Outcome of decoding one file, delivered back into the reducer.
public enum LoadResult: Sendable {
    case success(FileItem.Previews)
    case failure(String)
}

public enum ExportState: Equatable, Sendable {
    case idle
    case choosingDestination
    case running(ExportProgress)
    case finished(ExportSummary)
}

/// The whole app state. Mutated only inside `AppViewModel.update`.
public struct AppState: Sendable {
    public var items: [FileItem]
    public var selectedID: UUID?
    public var export: ExportState

    public init(items: [FileItem] = [], selectedID: UUID? = nil, export: ExportState = .idle) {
        self.items = items
        self.selectedID = selectedID
        self.export = export
    }

    public static let empty = AppState()
}
