// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WebMux",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/will-lumley/FaviconFinder.git", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "WebMux",
            dependencies: ["FaviconFinder"],
            path: "Sources/WebMux"
        ),
    ]
)
