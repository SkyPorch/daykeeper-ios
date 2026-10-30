const standardPhones = [
  "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
  "com.apple.CoreSimulator.SimDeviceType.iPhone-16",
];

export function selectSimulator(runtimes) {
  const candidates = runtimes
    .filter(
      (runtime) =>
        runtime.isAvailable &&
        runtime.platform === "iOS" &&
        Number(runtime.version.split(".")[0]) >= 18,
    )
    .sort((a, b) =>
      b.version.localeCompare(a.version, undefined, { numeric: true }),
    );
  for (const runtime of candidates) {
    const phones = (runtime.supportedDeviceTypes ?? []).filter(
      (device) => device.productFamily === "iPhone",
    );
    const deviceType = standardPhones
      .map((identifier) =>
        phones.find((device) => device.identifier === identifier),
      )
      .find(Boolean);
    if (deviceType) return { runtime, deviceType };
  }
  throw new Error(
    "Install an iOS 18+ Simulator runtime with a supported standard iPhone 17 or iPhone 16 device type",
  );
}
