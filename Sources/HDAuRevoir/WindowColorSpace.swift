import SwiftUI
import AppKit

/// Gives the window an extended (HDR-capable) backing store.
///
/// Without this, the window's color space is 8-bit sRGB and any HDR CGImage
/// drawn into it is *clamped* at 1.0 (blown-out highlights). With an extended
/// color space, the compositor renders HDR content with EDR on HDR displays and
/// applies the system tone mapping on SDR displays — the same thing Quick Look
/// triggers when it opens an HDR file.
struct HDRWindowColorSpace: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        HDRWindowColorSpaceView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class HDRWindowColorSpaceView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                let extended = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.extendedSRGB)!)
                if window.colorSpace != extended {
                    window.colorSpace = extended
                }
            }
        }
    }
}
