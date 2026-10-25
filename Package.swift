// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacUsageTracker",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MacUsageTracker",
            targets: ["MacUsageTracker"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacUsageTracker",
            path: "Sources/MacUsageTracker"
        )
    ]
)
