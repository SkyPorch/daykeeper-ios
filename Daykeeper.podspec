Pod::Spec.new do |spec|
  spec.name = "Daykeeper"
  spec.version = "0.1.0"
  spec.summary = "Headless customer support for Daykeeper on Apple platforms"
  spec.description = <<-DESC
    The official Daykeeper customer SDK for authenticated conversation history,
    unread state, replies, and safe recovery from uncertain writes.
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
  spec.module_name = "Daykeeper"
  spec.source_files = "Sources/Daykeeper/**/*.swift"
  spec.resource_bundles = {
    "Daykeeper_Privacy" => ["Sources/Daykeeper/Resources/PrivacyInfo.xcprivacy"],
  }
end
