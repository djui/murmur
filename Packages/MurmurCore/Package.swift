// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MurmurCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MurmurCore", targets: ["MurmurCore"]),
    ],
    targets: [
        .target(name: "MurmurCore"),
        .testTarget(name: "MurmurCoreTests", dependencies: ["MurmurCore"]),
    ]
)
