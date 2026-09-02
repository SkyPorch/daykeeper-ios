# Changelog

## Unreleased — 0.1.0 candidate

- Independent SwiftPM customer API and native SwiftUI messenger products.
- Short-lived customer authentication, bounded isolated networking, safe errors,
  and explicit recovery for uncertain writes.
- Per-customer draft/history lifecycle with reset and late-response fencing.
- Fresh successful history/list reads are required before uncertain-write
  recovery can be confirmed; failed reads and backgrounding invalidate readiness.
- Native example, transport/lifecycle tests, isolated wire/UI runners, contract
  provenance, privacy manifest, and documented release gates.
- Source-based `Daykeeper` and `DaykeeperUI` CocoaPods candidates that preserve
  the SwiftPM module boundary, exact version dependency, and privacy manifest,
  with real local consumer builds in CI.

No published release yet. See [COMPATIBILITY.md](COMPATIBILITY.md) for exclusions.
