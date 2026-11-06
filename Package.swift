// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CopyFXCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CopyFXCore", targets: ["CopyFXCore"])
    ],
    targets: [
        .target(name: "CopyFXCore"),
        .testTarget(name: "CopyFXCoreTests", dependencies: ["CopyFXCore"]),
    ]
)
