// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrismegistusUI",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "TrismegistusUI", targets: ["TrismegistusUI"])
    ],
    dependencies: [
        // The terminal drawer's emulator (#64): SwiftTerm (MIT), its `TerminalView` fed by the relay, not a local process.
        // Pinned to 1.11: from 1.12 the library compiles Metal shaders (Xcode's separate Metal Toolchain), and from 1.20
        // it runs a build plugin that xcodebuild refuses without -skipPackagePluginValidation.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", .upToNextMinor(from: "1.11.2")),
    ],
    targets: [
        // Inter and JetBrains Mono (SIL OFL 1.1), registered on first use of a type role (Fonts.swift).
        .target(name: "TrismegistusUI", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
                resources: [.copy("Resources/Fonts")]),
        .testTarget(name: "TrismegistusUITests", dependencies: ["TrismegistusUI"]),
    ]
)
