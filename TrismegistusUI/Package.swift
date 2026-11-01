// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrismegistusUI",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "TrismegistusUI", targets: ["TrismegistusUI"])
    ],
    targets: [
        // Inter and JetBrains Mono (SIL OFL 1.1), registered on first use of a type role (Fonts.swift).
        .target(name: "TrismegistusUI", resources: [.copy("Resources/Fonts")]),
        .testTarget(name: "TrismegistusUITests", dependencies: ["TrismegistusUI"]),
    ]
)
