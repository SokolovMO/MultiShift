// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MultiShiftCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MultiShiftCore", targets: ["MultiShiftCore"])],
    targets: [
        .target(name: "MultiShiftCore", path: "Sources/Core"),
        .testTarget(name: "MultiShiftCoreTests", dependencies: ["MultiShiftCore"], path: "Tests/CoreTests"),
    ]
)
