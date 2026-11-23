import SwiftUI
import HDRCore

struct PreviewArea: View {
    @ObservedObject var viewModel: AppViewModel

    private var selected: FileItem? {
        viewModel.state.items.first { $0.id == viewModel.state.selectedID }
    }

    var body: some View {
        if let item = selected {
            HStack(spacing: 0) {
                Pane(title: "HDR", image: item.previews?.hdr)
                Divider()
                Pane(title: "SDR", image: item.previews?.sdr)
            }
        } else {
            ContentUnavailableView(
                "No file selected",
                systemImage: "photo.on.rectangle.angled",
                description: Text("Drag & drop HDR images or videos onto the window")
            )
        }
    }
}

private struct Pane: View {
    let title: String
    let image: CGImage?

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
            Divider()
            GeometryReader { geometry in
                if let image, let nsImage = NSImageBridge.image(from: image) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    ProgressView()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
    }
}
