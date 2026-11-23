import AppKit
import CoreGraphics

/// The only bridge between CoreGraphics previews and AppKit, kept in the app target.
enum NSImageBridge {
    static func image(from cgImage: CGImage) -> NSImage? {
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
