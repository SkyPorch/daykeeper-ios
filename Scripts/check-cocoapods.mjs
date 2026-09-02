import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const requiredCocoaPodsVersion = "1.16.2";
const pod = ["pod", `_${requiredCocoaPodsVersion}_`];

function run(command, args, options = {}) {
  return execFileSync(command, args, {
    cwd: root,
    encoding: "utf8",
    stdio: options.capture ? ["ignore", "pipe", "inherit"] : "inherit",
  });
}

function readSpec(path) {
  const raw = run(pod[0], [...pod.slice(1), "ipc", "spec", path], {
    capture: true,
  });
  return JSON.parse(raw);
}

function assertCommon(spec, name) {
  assert.equal(spec.name, name);
  assert.equal(spec.version, "0.1.0");
  assert.equal(spec.homepage, "https://www.mydaykeeper.com/developers");
  assert.deepEqual(spec.license, { type: "MIT", file: "LICENSE" });
  assert.equal(spec.source.git, "https://github.com/SkyPorch/daykeeper-ios.git");
  assert.equal(spec.source.tag, "v0.1.0");
  assert.equal(spec.platforms.ios, "15.0");
  assert.equal(spec.swift_versions, "5.9");
  assert.equal(spec.cocoapods_version, ">= 1.16.2");
  assert.equal(spec.module_name, name);
  assert.equal(spec.prepare_command, undefined);
  assert.equal(spec.vendored_frameworks, undefined);
}

const actualCocoaPodsVersion = run(pod[0], [...pod.slice(1), "--version"], {
  capture: true,
}).trim();
assert.equal(
  actualCocoaPodsVersion,
  requiredCocoaPodsVersion,
  `CocoaPods ${requiredCocoaPodsVersion} is required; found ${actualCocoaPodsVersion}`,
);

const core = readSpec("Daykeeper.podspec");
assertCommon(core, "Daykeeper");
assert.equal(core.source_files, "Sources/Daykeeper/**/*.swift");
assert.deepEqual(core.resource_bundles, {
  Daykeeper_Privacy: ["Sources/Daykeeper/Resources/PrivacyInfo.xcprivacy"],
});
assert.equal(core.dependencies, undefined);

const ui = readSpec("DaykeeperUI.podspec");
assertCommon(ui, "DaykeeperUI");
assert.equal(ui.source_files, "Sources/DaykeeperUI/**/*.swift");
assert.deepEqual(ui.dependencies, { Daykeeper: ["0.1.0"] });
assert.equal(ui.resource_bundles, undefined);

run(pod[0], [
  ...pod.slice(1),
  "lib",
  "lint",
  "Daykeeper.podspec",
  "--platforms=ios",
  "--skip-tests",
  "--fail-fast",
  "--no-ansi",
]);
run(pod[0], [
  ...pod.slice(1),
  "lib",
  "lint",
  "DaykeeperUI.podspec",
  "--include-podspecs=Daykeeper.podspec",
  "--platforms=ios",
  "--skip-tests",
  "--fail-fast",
  "--no-ansi",
]);

console.log("CocoaPods metadata and clean consumer builds passed.");
