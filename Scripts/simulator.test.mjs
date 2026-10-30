import assert from "node:assert/strict";
import test from "node:test";
import { selectSimulator } from "./simulator.mjs";

const phone = (name) => ({
  identifier: `com.apple.CoreSimulator.SimDeviceType.${name}`,
  productFamily: "iPhone",
});
const runtime = (version, devices, isAvailable = true) => ({
  identifier: `com.apple.CoreSimulator.SimRuntime.iOS-${version.replaceAll(".", "-")}`,
  version,
  platform: "iOS",
  isAvailable,
  supportedDeviceTypes: devices,
});

test("newest runtime uses its supported phone instead of an incompatible older model", () => {
  const older = runtime("26.5", [phone("iPhone-16")]);
  const newest = runtime("27.1", [phone("iPhone-Duo")]);
  const selected = selectSimulator([older, newest]);
  assert.equal(selected.runtime, newest);
  assert.equal(selected.deviceType.identifier, phone("iPhone-Duo").identifier);
});

test("unavailable, non-iOS, too-old and tablet-only runtimes cannot select an incompatible phone", () => {
  const valid = runtime("26.5", [phone("iPhone-17"), phone("iPhone-16")]);
  const selected = selectSimulator([
    runtime("27.1", [phone("iPhone-Duo")], false),
    runtime("27.2", [{ productFamily: "iPad", identifier: "tablet" }]),
    { ...runtime("28.0", [phone("iPhone-Duo")]), platform: "tvOS" },
    runtime("17.0", [phone("iPhone-16")]),
    valid,
  ]);
  assert.equal(selected.runtime, valid);
  assert.equal(selected.deviceType.identifier, phone("iPhone-16").identifier);
  assert.throws(
    () => selectSimulator([runtime("27.1", [])]),
    /supported iPhone/,
  );
});
