// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Daykeeper",
  platforms: [.iOS(.v15), .macOS(.v12)],
  products: [
    .library(name: "Daykeeper", targets: ["Daykeeper"]),
    .library(name: "DaykeeperUI", targets: ["DaykeeperUI"]),
  ],
  targets: [
    .target(name: "Daykeeper", resources: [.process("Resources/PrivacyInfo.xcprivacy")]),
    .target(name: "DaykeeperUI", dependencies: ["Daykeeper"]),
    .testTarget(name: "DaykeeperTests", dependencies: ["Daykeeper"]),
    .testTarget(name: "DaykeeperUITests", dependencies: ["DaykeeperUI"]),
  ]
)
