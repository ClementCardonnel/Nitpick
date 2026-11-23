import Foundation

/// Every intent that can change the app, Elm-style. Actions in, state out.
public enum AppAction: Sendable {
    /// User dropped files onto the window (or used File > Open).
    case filesDropped([URL])
    case itemSelected(UUID)
    case itemRemoved(UUID)

    /// Async load of one item finished (success carries the previews).
    case loadFinished(id: UUID, result: LoadResult)

    /// Export flow.
    case exportRequested
    case exportFolderChosen(URL?)
    case exportProgress(ExportProgress)
    case exportCancelled
    case exportFinished(ExportSummary)
    case dismissExportSummary
}
