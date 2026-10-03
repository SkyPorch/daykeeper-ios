#!/usr/bin/env bash
set -euo pipefail
trap 'rm -rf DerivedData .build' EXIT
rm -rf DerivedData .build TestResults
xcodebuild -version
swift --version
pod _1.16.2_ --version
node Scripts/check-contract.mjs
swift format lint --strict --recursive Package.swift Sources Tests Examples
swift test --jobs 2 --skip WireTests -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
node Scripts/check-wire.mjs
node Scripts/check-cocoapods.mjs
xcodebuild -jobs 2 -scheme DaykeeperUI -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData/Generic CODE_SIGNING_ALLOWED=NO build
if [[ "$GITHUB_EVENT_NAME" != pull_request_target ]]; then
  node Scripts/check-ios.mjs
fi
