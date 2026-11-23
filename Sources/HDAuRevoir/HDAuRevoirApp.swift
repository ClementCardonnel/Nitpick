import SwiftUI
import AppKit
import HDRCore

@main
struct HDAuRevoirApp: App {
    @StateObject private var viewModel = AppViewModel(
        services: .live(chooseExportFolder: Self.chooseExportFolder)
    )

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear {
                    // `open HDAuRevoir file.heic` / `swift run HDAuRevoir file.heic`
                    let args = ProcessInfo.processInfo.arguments.dropFirst()
                    let urls = args.compactMap { URL(fileURLWithPath: $0).isFileURL ? URL(fileURLWithPath: $0) : nil }
                    if !urls.isEmpty { viewModel.send(.filesDropped(urls)) }
                }
        }
    }

    /// The one platform capability the Core asks for: a destination folder picker.
    @Sendable private static func chooseExportFolder() async -> URL? {
        await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "Export"
            panel.message = "Choose a folder for the SDR exports"
            return panel.runModal() == .OK ? panel.url : nil
        }
    }
}
