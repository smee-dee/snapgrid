// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Snapgrid",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "snapgrid", targets: ["snapgrid"]),
    ],
    targets: [
        .target(name: "SnapgridCore"),
        .executableTarget(name: "snapgrid", dependencies: ["SnapgridCore"]),
        .testTarget(name: "SnapgridCoreTests", dependencies: ["SnapgridCore"]),
    ]
)
