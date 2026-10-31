// swift-tools-version: 6.2
import PackageDescription

// The transcription pipeline, shared by the Mac app and the Windows sidecar (`murmur`).
// Apple-only pieces (Apple's transcriber, Apple Intelligence, Uhm) compile out elsewhere.
let package = Package(
    name: "MurmurEngine",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MurmurEngine", targets: ["MurmurEngine"]),
        .executable(name: "murmur", targets: ["murmur"]),
    ],
    dependencies: [
        .package(path: "../MurmurCore"),
        // Exact: the model folders are laid out per SDK version, and builds on different versions re-download each other's models.
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git", exact: "4.2.0"),
    ],
    targets: [
        // Media Foundation decoding for Windows; compiles to nothing elsewhere.
        .target(
            name: "CMediaFoundation",
            linkerSettings: [
                .linkedLibrary("mfplat", .when(platforms: [.windows])),
                .linkedLibrary("mfreadwrite", .when(platforms: [.windows])),
                .linkedLibrary("mfuuid", .when(platforms: [.windows])),
                .linkedLibrary("ole32", .when(platforms: [.windows])),
            ]
        ),
        .target(
            name: "MurmurEngine",
            dependencies: [
                .product(name: "MurmurCore", package: "MurmurCore"),
                .target(name: "CMediaFoundation", condition: .when(platforms: [.windows])),
                .product(name: "Voz", package: "desert-ant-core"),
                .product(name: "Who", package: "desert-ant-core"),
                .product(name: "Ear", package: "desert-ant-core"),
                .product(name: "Align", package: "desert-ant-core"),
                .product(name: "Tongue", package: "desert-ant-core"),
                .product(name: "Clear", package: "desert-ant-core"),
                .product(name: "Redact", package: "desert-ant-core"),
                // Uhm runs on Core ML only.
                .product(name: "Uhm", package: "desert-ant-core", condition: .when(platforms: [.macOS])),
            ]
        ),
        .executableTarget(
            name: "murmur",
            dependencies: [
                "MurmurEngine",
                .product(name: "MurmurCore", package: "MurmurCore"),
                .product(name: "Voz", package: "desert-ant-core"),
            ]
        ),
        .testTarget(name: "MurmurEngineTests", dependencies: ["MurmurEngine"]),
    ],
    // The same as the app target: the pipeline predates strict concurrency checking.
    swiftLanguageModes: [.v5]
)
