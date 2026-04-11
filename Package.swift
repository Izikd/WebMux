// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WebMux",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/will-lumley/FaviconFinder.git", from: "5.0.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.3.7"),
    ],
    targets: [
        .executableTarget(
            name: "WebMux",
            dependencies: ["FaviconFinder", "SwiftSoup"],
            path: "Sources/WebMux"
        ),
    ]
)
