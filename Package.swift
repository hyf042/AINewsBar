// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AINewsBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/nmdias/FeedKit.git", from: "9.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "AINewsBar",
            dependencies: ["FeedKit"],
            path: "Sources/AINewsBar"
        ),
        .testTarget(
            name: "AINewsBarTests",
            dependencies: ["AINewsBar"],
            path: "Tests/AINewsBarTests"
        ),
    ]
)
