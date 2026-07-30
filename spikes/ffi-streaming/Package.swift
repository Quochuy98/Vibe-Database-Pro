// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DataForgeFFISpike",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DataForgeFFISpike", targets: ["DataForgeFFISpike"]),
        .executable(name: "DataForgeFFIBenchmark", targets: ["DataForgeFFIBenchmark"])
    ],
    targets: [
        .target(
            name: "CDataForgeFFI",
            path: "include",
            publicHeadersPath: "."
        ),
        .target(
            name: "DataForgeFFISpike",
            dependencies: ["CDataForgeFFI"],
            path: "swift/Sources/DataForgeFFISpike",
            linkerSettings: [
                .unsafeFlags(["-L", "rust/target/release"]),
                .linkedLibrary("dataforge_ffi_spike")
            ]
        ),
        .executableTarget(
            name: "DataForgeFFIBenchmark",
            dependencies: ["DataForgeFFISpike"],
            path: "swift/Sources/DataForgeFFIBenchmark"
        ),
        .testTarget(
            name: "DataForgeFFISpikeTests",
            dependencies: ["DataForgeFFISpike", "CDataForgeFFI"],
            path: "swift/Tests/DataForgeFFISpikeTests"
        )
    ]
)
