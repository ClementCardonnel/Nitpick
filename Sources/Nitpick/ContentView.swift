import SwiftUI
import UniformTypeIdentifiers
import HDRCore

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarList(viewModel: viewModel)
                // The sidebar opens at `min` on macOS, so min is sized to show a
                // typical camera file name ("IMG_7207.MOV") uncropped; the column
                // stays user-resizable up to `max`.
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 360)
        } detail: {
            VStack(spacing: 0) {
                PreviewArea(viewModel: viewModel)
                Divider()
                ExportBar(viewModel: viewModel)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            Task {
                let urls = await Self.collectURLs(from: providers)
                guard !urls.isEmpty else { return }
                await MainActor.run { viewModel.send(.filesDropped(urls)) }
            }
            return true
        }
    }

    private static func collectURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await loadURL(provider) { urls.append(url) }
        }
        return urls
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
