// swift-tools-version: 6.0
// BlithCore: platform-independent health intelligence. Models, the local store, sync,
// analytics, the insight engine and the assistant tool layer live here and depend only on
// Foundation, so `swift test` runs on Linux and in CI without a simulator.
import PackageDescription

let package = Package(
    name: "BlithCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "BlithCore", targets: ["BlithCore"]),
    ],
    targets: [
        .target(name: "BlithCore"),
        // Developer tool: runs the assistant end-to-end against sample data from a terminal.
        .executableTarget(name: "BlithCLI", dependencies: ["BlithCore"]),
        .testTarget(name: "BlithCoreTests", dependencies: ["BlithCore"]),
    ]
)
