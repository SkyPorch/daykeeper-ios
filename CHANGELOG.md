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

No published release yet. See [COMPATIBILITY.md](COMPATIBILITY.md) for exclusions.
