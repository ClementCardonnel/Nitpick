import SwiftUI
import UniformTypeIdentifiers
import HDRCore

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarList(viewModel: viewModel)
        } detail: {
            VStack(spacing: 0) {
                PreviewArea(viewModel: viewModel)
                Divider()
                ExportBar(viewModel: viewModel)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
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
