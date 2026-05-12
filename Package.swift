// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeNotchExpansion",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeNotchExpansion",
            path: "Sources/ClaudeNotchExpansion",
            resources: [.copy("Resources")]
        )
    ]
)
