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
- Keep the draft and loaded history when a token expires mid-send. One recovery
  read decides what happened: a definite 401 or 403 leaves the draft editable and
  sendable, a rejected recovery read or one naming a different customer signs the
  session out, and any other failure is an ordinary error. The write is never
  replayed, and read-marker recoveries are bounded to one per session generation.
- Add `DaykeeperClient.getIdentityWithFreshToken()`, an identity read that always
  asks the token provider for a new credential first, so a `retryable: false`
  hint cannot suppress the recovery read.
- Read message history with the forward `after` cursor: refreshing an open thread
  asks only for messages newer than the last one held. The customer contract has
  no backward cursor or page-size parameter, so a thread whose first page already
  exceeds the 1 MiB response cap still needs a gateway-side page parameter.
- Refuse plain HTTP in release builds of the SDK, including loopback.
- Use `NavigationStack` where it exists, keeping the iOS 15 `NavigationView`
  fallback, and move every user-facing string into the package's English
  `Localizable.strings` and `Localizable.stringsdict`, shipped to CocoaPods
  consumers as a `DaykeeperUI` resource bundle.
- `swift test` now starts the loopback wire harness itself when node is present
  and otherwise skips with a pointer to `Scripts/check-wire.mjs`.
- Project only the reviewed customer-gateway error vocabulary. Unknown,
  token-like, free-form, and non-string values collapse to
  `daykeeper_request_failed`; the envelope's `message` is never read.
- Expose `DaykeeperError.nextAction` as `DaykeeperNextAction`, decoded from the
  envelope through a closed three-value allowlist (`review_usage`,
  `review_setup`, `refresh_conversation`); anything else is dropped.
- Document API-only inbox gateways and safely surface their non-retryable
  `widget_unavailable` refusals for widget identity and anonymous claims.

No published release yet. See [COMPATIBILITY.md](COMPATIBILITY.md) for exclusions.
