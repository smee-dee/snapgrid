// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GridKeys",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "gridkeys", targets: ["gridkeys"]),
    ],
    targets: [
        .target(name: "GridKeysCore"),
        .executableTarget(name: "gridkeys", dependencies: ["GridKeysCore"]),
        .testTarget(name: "GridKeysCoreTests", dependencies: ["GridKeysCore"]),
    ]
)
