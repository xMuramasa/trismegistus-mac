// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrismegistusKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TrismegistusKit", targets: ["TrismegistusKit"])
    ],
    targets: [
        .target(name: "TrismegistusKit"),
        // Resources are read through #filePath (like protocol/), so they're excluded rather than bundled.
        .testTarget(name: "TrismegistusKitTests", dependencies: ["TrismegistusKit"], exclude: ["Resources"]),
    ]
)
