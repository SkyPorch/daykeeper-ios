Pod::Spec.new do |spec|
  spec.name = "DaykeeperUI"
  spec.version = "0.1.0"
  spec.summary = "SwiftUI customer messenger for Daykeeper"
  spec.description = <<-DESC
    The official Daykeeper SwiftUI conversation list, message history, composer,
    and uncertain-write recovery interface. Depends on the headless Daykeeper pod.
  DESC
  spec.homepage = "https://www.mydaykeeper.com/developers"
  spec.license = { type: "MIT", file: "LICENSE" }
  spec.author = "SkyPorch"
  spec.source = {
    git: "https://github.com/SkyPorch/daykeeper-ios.git",
    tag: "v#{spec.version}",
  }

  spec.ios.deployment_target = "15.0"
  spec.swift_version = "5.9"
  spec.cocoapods_version = ">= 1.16.2"
  spec.module_name = "DaykeeperUI"
  spec.source_files = "Sources/DaykeeperUI/**/*.swift"
  spec.resource_bundles = {
    "DaykeeperUI" => ["Sources/DaykeeperUI/Resources/**/*.lproj/*.strings"],
  }
  spec.dependency "Daykeeper", spec.version.to_s
end
