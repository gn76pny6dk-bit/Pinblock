// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PinblockCore",
    products: [
        .library(name: "PinblockCore", type: .static, targets: ["PinblockCore"])
    ],
    targets: [
        .target(name: "PinblockCore"),
        .testTarget(name: "PinblockCoreTests", dependencies: ["PinblockCore"])
    ]
)
