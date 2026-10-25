// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NokaelCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NokaelCore", targets: ["NokaelCore"])
    ],
    targets: [
        .target(name: "NokaelCore"),
        .testTarget(name: "NokaelCoreTests", dependencies: ["NokaelCore"])
    ]
)
