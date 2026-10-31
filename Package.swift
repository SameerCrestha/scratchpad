// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Scratchpad",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Scratchpad",
            path: "Sources/Scratchpad",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
