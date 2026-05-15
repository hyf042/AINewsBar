// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "AINewsBar",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/nmdias/FeedKit.git", from: "9.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "AINewsBar",
            dependencies: ["FeedKit"],
            path: "Sources/AINewsBar",
            resources: [.process("Resources")]
        ),
    ]
)
