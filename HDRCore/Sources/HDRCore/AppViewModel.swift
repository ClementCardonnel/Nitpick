import Foundation
import Combine

/// A side effect returned by the reducer. The view model executes these and feeds
/// their outcomes back in as new actions, so `update` stays the single place
/// where state changes.
public enum AppEffect: Sendable {
    case loadItem(id: UUID, url: URL)
    case chooseExportFolder
    case runExport(items: [FileItem], folder: URL)
}

/// Elm-style view model (RE:Flex pillar 2). Lives in the UI-free Core: the SwiftUI
/// shell only observes `state` and calls `send`.
///
/// `@MainActor` is a Dispatch concept, not a UI import — the Core still has no
/// AppKit/SwiftUI dependency and can run headlessly on the main actor.
@MainActor
public final class AppViewModel: ObservableObject {
    @Published public private(set) var state: AppState

    private let services: CoreServices
    private let cancelFlag = CancelFlag()

    public init(services: CoreServices, state: AppState = .empty) {
        self.services = services
        self.state = state
    }

    public func send(_ action: AppAction) {
        if case .exportCancelled = action { cancelFlag.cancel() }
        let (newState, effects) = Self.update(state: state, action: action)
        state = newState
        for effect in effects { run(effect) }
    }

    /// The reducer: the only place where `AppState` changes.
    public static func update(state: AppState, action: AppAction) -> (AppState, [AppEffect]) {
        var s = state
        switch action {
        case .filesDropped(let urls):
            var effects: [AppEffect] = []
            for url in urls {
                guard let kind = MediaPipeline.supportedKind(for: url) else {
                    var item = FileItem(url: url, kind: .still)
                    item.status = .error("Unsupported format")
                    s.items.append(item)
                    continue
                }
                let item = FileItem(url: url, kind: kind)
                s.items.append(item)
                if s.selectedID == nil { s.selectedID = item.id }
                effects.append(.loadItem(id: item.id, url: url))
            }
            return (s, effects)

        case .itemSelected(let id):
            s.selectedID = id
            return (s, [])

        case .itemRemoved(let id):
            s.items.removeAll { $0.id == id }
            if s.selectedID == id { s.selectedID = s.items.first?.id }
            return (s, [])

        case .loadFinished(let id, let result):
            if let i = s.items.firstIndex(where: { $0.id == id }) {
                switch result {
                case .success(let previews):
                    s.items[i].previews = previews
                    s.items[i].status = .ready
                case .failure(let message):
                    s.items[i].status = .error(message)
                }
            }
            return (s, [])


        case .exportRequested:
            guard case .idle = s.export else { return (s, []) }
            guard s.items.contains(where: { if case .ready = $0.status { return true }; return false }) else {
                return (s, [])
            }
            s.export = .choosingDestination
            return (s, [.chooseExportFolder])

        case .exportFolderChosen(let folder):
            guard case .choosingDestination = s.export else { return (s, []) }
            guard let folder else {
                s.export = .idle
                return (s, [])
            }
            let ready = s.items.filter { if case .ready = $0.status { return true }; return false }
            guard !ready.isEmpty else {
                s.export = .idle
                return (s, [])
            }
            s.export = .running(ExportProgress(completed: 0, total: ready.count, currentFileName: ""))
            return (s, [.runExport(items: ready, folder: folder)])

        case .exportProgress(let progress):
            if case .running = s.export { s.export = .running(progress) }
            return (s, [])

        case .exportCancelled:
            // The flag is read by the running export effect; state stays .running
            // until the exporter reports back.
            return (s, [])

        case .exportFinished(let summary):
            s.export = .finished(summary)
            return (s, [])

        case .dismissExportSummary:
            if case .finished = s.export { s.export = .idle }
            return (s, [])
        }
    }

    // MARK: - Effect execution

    private func run(_ effect: AppEffect) {
        switch effect {
        case .loadItem(let id, let url):
            Task {
                let result = await services.mediaLoader.loadPreviews(for: url)
                DispatchQueue.main.async { self.send(.loadFinished(id: id, result: result)) }
            }

        case .chooseExportFolder:
            Task {
                let folder = await services.chooseExportFolder()
                DispatchQueue.main.async { self.send(.exportFolderChosen(folder)) }
            }

        case .runExport(let items, let folder):
            cancelFlag.reset()
            Task {
                let summary = await services.exporter.export(
                    items: items,
                    to: folder,
                    progress: { progress in
                        DispatchQueue.main.async { self.send(.exportProgress(progress)) }
                    },
                    isCancelled: { self.cancelFlag.isCancelled }
                )
                DispatchQueue.main.async { self.send(.exportFinished(summary)) }
            }
        }
    }
}

/// Simple thread-safe cancellation flag for the running export.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isCancelled
    }

    func cancel() {
        lock.lock(); _isCancelled = true; lock.unlock()
    }

    func reset() {
        lock.lock(); _isCancelled = false; lock.unlock()
    }
}
