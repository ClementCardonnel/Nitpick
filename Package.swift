// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Nitpick",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "HDRCore", targets: ["HDRCore"])
    ],
    targets: [
        // RE:Flex pillar 1: a UI-free core module. No AppKit/SwiftUI imports allowed here.
        .target(name: "HDRCore", path: "Sources/HDRCore"),
        // Thin SwiftUI shell (RE:Flex pillar 2 lives in HDRCore's view model).
        .executableTarget(
            name: "Nitpick",
            dependencies: ["HDRCore"],
            path: "Sources/Nitpick"
        )
    ],
    swiftLanguageModes: [.v6]
)
