import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { mkdir } from "node:fs/promises";
import { run, withFixture } from "./fixture-runner.mjs";

// Always create a fresh device. No existing device ID or "booted" destination
// is accepted. Cleanup targets only the exact device created by this run.
const inventory = JSON.parse(await run("xcrun", ["simctl", "list", "runtimes", "-j"], { capture: true }));
const runtime = inventory.runtimes.filter(item => item.isAvailable && item.platform === "iOS"
  && Number(item.version.split(".")[0]) >= 18)
  .sort((a, b) => b.version.localeCompare(a.version, undefined, { numeric: true }))[0];
assert.ok(runtime, "Install an iOS 18+ Simulator runtime (minimum-OS certification remains separate)");
const runID = randomUUID().toLowerCase();
await mkdir(`TestResults/${runID}`, { recursive: true });
const device = await run("xcrun", ["simctl", "create", `Daykeeper-sdk-${runID}`,
  "com.apple.CoreSimulator.SimDeviceType.iPhone-16", runtime.identifier], { capture: true });
assert.match(device, /^[A-F0-9-]{36}$/i);
console.log(JSON.stringify({ runID, device, runtime: runtime.identifier }));
try {
  // xcodebuild can begin the first app launch while a newly created simulator
  // is still finishing its cold boot. Wait for this exact owned device before
  // starting the loopback fixture so a runner delay cannot consume the SDK's
  // intentionally short request deadline.
  await run("xcrun", ["simctl", "boot", device], { timeout: 120_000 });
  await run("xcrun", ["simctl", "bootstatus", device, "-b"], { timeout: 600_000 });
  await withFixture(origin => run("xcodebuild", ["test", "-project",
    "Examples/DaykeeperExample/DaykeeperExample.xcodeproj", "-scheme", "DaykeeperExample",
    "-destination", `platform=iOS Simulator,id=${device}`, "-parallel-testing-enabled", "NO",
    "-maximum-concurrent-test-simulator-destinations", "1", "-derivedDataPath", "DerivedData/Example",
    "-resultBundlePath", `TestResults/${runID}/Messenger.xcresult`, "CODE_SIGNING_ALLOWED=NO"], {
    env: { TEST_RUNNER_DAYKEEPER_TEST_ORIGIN: origin }, timeout: 900_000,
  }));
} finally {
  async function ownedDevice() {
    const devices = JSON.parse(await run("xcrun", ["simctl", "list", "devices", "-j"], { capture: true }));
    const owned = Object.values(devices.devices).flat().find(item => item.udid === device);
    assert.equal(owned?.name, `Daykeeper-sdk-${runID}`, "Do not clean up an unrecognized device");
    return owned;
  }
  const owned = await ownedDevice();
  if (owned.state !== "Shutdown") {
    try { await run("xcrun", ["simctl", "shutdown", device]); }
    catch (error) {
      // Xcode can finish shutting down between inventory and our command.
      // Accept only a fresh, identity-checked Shutdown state, not arbitrary failure.
      if ((await ownedDevice()).state !== "Shutdown") throw error;
    }
  }
  assert.equal((await ownedDevice()).state, "Shutdown");
  await run("xcrun", ["simctl", "delete", device]);
  console.log(`Removed isolated SDK simulator ${device}; result bundle retained.`);
}
