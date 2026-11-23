import SwiftUI
import AppKit
import QuartzCore

/// Displays an HDR CGImage the way Quick Look does: through a CALayer that asks
/// for EDR headroom *and* tone maps whenever the display can't provide enough.
///
/// The headroom macOS grants is dynamic — it depends on the display, its
/// brightness, and whether the window is focused (background windows get less).
/// With the default `toneMapMode` (`.automatic`), extended-range float contents
/// are *clipped* to whatever headroom is available, which blew out highlights on
/// the built-in display and in unfocused windows. `.ifSupported` makes Core
/// Animation tone map extended-range contents to the current headroom instead,
/// using the CGImage's content headroom metadata.
struct HDRImageView: NSViewRepresentable {
    let image: CGImage

    func makeNSView(context: Context) -> LayerView {
        LayerView()
    }

    func updateNSView(_ nsView: LayerView, context: Context) {
        nsView.show(image)
    }

    final class LayerView: NSView {
        private let imageLayer = CALayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            imageLayer.contentsGravity = .resizeAspect
            imageLayer.preferredDynamicRange = .high
            imageLayer.toneMapMode = .ifSupported
            layer?.addSublayer(imageLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func show(_ image: CGImage) {
            guard (imageLayer.contents as AnyObject?) !== image else { return }
            imageLayer.contents = image
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageLayer.frame = bounds
            CATransaction.commit()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        }
    }
}
