// swift-tools-version: 6.2
import PackageDescription

/// RE:Flex pillar 1: the UI-free core (no AppKit/SwiftUI imports allowed here).
/// The Nitpick app target (Nitpick.xcodeproj) depends on this local package.
let package = Package(
    name: "HDRCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "HDRCore", targets: ["HDRCore"])
    ],
    targets: [
        .target(name: "HDRCore")
    ],
    swiftLanguageModes: [.v6]
)
