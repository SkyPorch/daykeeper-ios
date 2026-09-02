// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Daykeeper",
  defaultLocalization: "en",
  platforms: [.iOS(.v15), .macOS(.v12)],
  products: [
    .library(name: "Daykeeper", targets: ["Daykeeper"]),
    .library(name: "DaykeeperUI", targets: ["DaykeeperUI"]),
  ],
  targets: [
    .target(name: "Daykeeper", resources: [.process("Resources/PrivacyInfo.xcprivacy")]),
    .target(
      name: "DaykeeperUI", dependencies: ["Daykeeper"],
      resources: [.process("Resources")]),
    .testTarget(name: "DaykeeperTests", dependencies: ["Daykeeper"]),
    .testTarget(name: "DaykeeperUITests", dependencies: ["DaykeeperUI"]),
  ]
)
