// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrismegistusUI",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "TrismegistusUI", targets: ["TrismegistusUI"])
    ],
    targets: [
        .target(name: "TrismegistusUI"),
        .testTarget(name: "TrismegistusUITests", dependencies: ["TrismegistusUI"]),
    ]
)
