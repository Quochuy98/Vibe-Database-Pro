// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "TextKitEditorSpike",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(
      name: "TextKitEditorSpike",
      targets: ["TextKitEditorSpike"]
    ),
    .executable(
      name: "TextKitEditorEvidence",
      targets: ["TextKitEditorEvidence"]
    ),
  ],
  targets: [
    .target(name: "TextKitEditorSpike"),
    .executableTarget(
      name: "TextKitEditorEvidence",
      dependencies: ["TextKitEditorSpike"]
    ),
    .testTarget(
      name: "TextKitEditorSpikeTests",
      dependencies: ["TextKitEditorSpike"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
