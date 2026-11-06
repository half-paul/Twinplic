// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TwinplicCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TwinplicCore", targets: ["TwinplicCore"])
    ],
    targets: [
        .target(name: "TwinplicCore"),
        .testTarget(name: "TwinplicCoreTests", dependencies: ["TwinplicCore"]),
    ]
)
