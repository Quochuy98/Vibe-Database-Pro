// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "NSTableViewGridSpike",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "GridSpikeCore", targets: ["GridSpikeCore"]),
    .library(name: "GridSpikeAppKit", targets: ["GridSpikeAppKit"]),
    .executable(name: "grid-evidence", targets: ["GridEvidence"]),
  ],
  targets: [
    .target(name: "GridSpikeCore"),
    .target(
      name: "GridSpikeAppKit",
      dependencies: ["GridSpikeCore"]
    ),
    .executableTarget(
      name: "GridEvidence",
      dependencies: ["GridSpikeCore", "GridSpikeAppKit"]
    ),
    .testTarget(
      name: "GridSpikeCoreTests",
      dependencies: ["GridSpikeCore"]
    ),
    .testTarget(
      name: "GridSpikeAppKitTests",
      dependencies: ["GridSpikeAppKit", "GridSpikeCore"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
