import SwiftUI
import AppKit
import HDRCore

struct ExportBar: View {
    @ObservedObject var viewModel: AppViewModel

    private var readyCount: Int {
        viewModel.state.items.filter { if case .ready = $0.status { return true }; return false }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            switch viewModel.state.export {
            case .idle:
                exportButton
            case .finished(let summary):
                exportButton
                summaryText(summary)
                Button("Dismiss") { viewModel.send(.dismissExportSummary) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            case .choosingDestination:
                ProgressView().scaleEffect(0.7)
                Text("Choose a destination folder…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .running(let progress):
                ProgressView(
                    value: Double(progress.completed),
                    total: Double(max(progress.total, 1))
                )
                .frame(width: 240)
                Text(label(for: progress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Cancel") { viewModel.send(.exportCancelled) }
            }
        }
        .padding(10)
    }

    private var exportButton: some View {
        Button {
            viewModel.send(.exportRequested)
        } label: {
            Label("Export SDR…", systemImage: "square.and.arrow.down")
        }
        .disabled(readyCount == 0)
    }

    private func label(for progress: ExportProgress) -> String {
        let base = "\(progress.completed) / \(progress.total)"
        return progress.currentFileName.isEmpty ? base : "\(base) — \(progress.currentFileName)"
    }

    @ViewBuilder
    private func summaryText(_ summary: ExportSummary) -> some View {
        let count = summary.succeeded.count
        if count > 0 {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting(summary.succeeded)
            } label: {
                Label("Exported \(count) file\(count == 1 ? "" : "s")", systemImage: "folder")
            }
            .buttonStyle(.link)
            .font(.caption)
            .help("Show in Finder")
        }
        if !summary.failed.isEmpty {
            let failed = summary.failed.map { "\($0.fileName): \($0.message)" }.joined(separator: "; ")
            Text((count > 0 ? "" : "Nothing exported. ") + "Failed: \(failed)")
                .font(.caption)
                .foregroundStyle(Color.orange)
                .lineLimit(2)
        }
    }
}
