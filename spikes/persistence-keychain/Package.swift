// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "DataForgePersistenceKeychainSpike",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(
      name: "dataforge-persistence-keychain-probe",
      targets: ["PersistenceKeychainProbe"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/groue/GRDB.swift.git",
      exact: "7.11.1")
  ],
  targets: [
    .target(
      name: "PersistenceKeychainCore",
      dependencies: [
        .product(name: "GRDB", package: "GRDB.swift")
      ],
      linkerSettings: [
        .linkedFramework("Security")
      ]),
    .executableTarget(
      name: "PersistenceKeychainProbe",
      dependencies: ["PersistenceKeychainCore"]),
    .testTarget(
      name: "PersistenceKeychainCoreTests",
      dependencies: ["PersistenceKeychainCore"]),
  ],
  swiftLanguageModes: [.v6])
