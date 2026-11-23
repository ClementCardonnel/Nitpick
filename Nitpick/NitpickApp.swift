import SwiftUI
import AppKit
import HDRCore

@main
struct NitpickApp: App {
    @StateObject private var viewModel = AppViewModel(
        services: .live(chooseExportFolder: Self.chooseExportFolder)
    )

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear {
                    // Files passed as launch arguments (handy for debugging). Only
                    // existing files count: Xcode also passes flags such as
                    // `-NSDocumentRevisionsDebugMode YES`. Under the App Sandbox a
                    // file is only readable if the user granted it, e.g. by drop.
                    let args = ProcessInfo.processInfo.arguments.dropFirst().filter { !$0.hasPrefix("-") }
                    let urls = args
                        .map { URL(fileURLWithPath: $0) }
                        .filter { FileManager.default.fileExists(atPath: $0.path) }
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
