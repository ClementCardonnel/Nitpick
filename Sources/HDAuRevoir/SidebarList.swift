import SwiftUI
import HDRCore

struct SidebarList: View {
    @ObservedObject var viewModel: AppViewModel

    private var selection: Binding<UUID?> {
        Binding(
            get: { viewModel.state.selectedID },
            set: { if let id = $0 { viewModel.send(.itemSelected(id)) } }
        )
    }

    var body: some View {
        List(selection: selection) {
            ForEach(viewModel.state.items) { item in
                HStack(spacing: 8) {
                    Thumbnail(image: item.previews?.sdr ?? item.previews?.hdr)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        statusView(item.status, kind: item.kind)
                    }
                    Spacer()
                    Button {
                        viewModel.send(.itemRemoved(item.id))
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from queue")
                }
                .tag(item.id)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if viewModel.state.items.isEmpty {
                Text("Drop HDR files here")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Files")
    }

    @ViewBuilder
    private func statusView(_ status: FileItem.Status, kind: FileItem.Kind) -> some View {
        switch status {
        case .loading:
            Text("Loading…").font(.caption2).foregroundStyle(.secondary)
        case .ready:
            Text(kind == .video ? "HDR video" : "HDR image").font(.caption2).foregroundStyle(.secondary)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(1)
        }
    }
}

private struct Thumbnail: View {
    let image: CGImage?

    var body: some View {
        Group {
            if let image, let nsImage = NSImageBridge.image(from: image) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        ProgressView().scaleEffect(0.5)
                    }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
