# Compatibility and release gates

This is the first **unreleased** iOS candidate, targeting `0.1.0`. No tag,
CocoaPods publication, binary artifact, App Store approval, or live-gateway
certification is implied by the source or CI checks.

## Implemented and tested separately

| Surface | Candidate coverage | Remaining boundary |
| --- | --- | --- |
| SwiftPM | Headless and SwiftUI products; native example imports the package | Approved tag and external clean tagged-install receipt |
| Customer API | Eight operations, typed decoding, safe errors, prefix routing | Deployed tenant/gateway contract parity |
| Transport | Real URLSession redirect, cookie/cache isolation, token refresh, stream/deadline/cancellation and write-attempt tests | TLS chain, proxy/load-balancer and physical-network matrix |
| Native messenger | List/history/plain-text send/seen, drafts, logout, account switching and fresh-read recovery guards | Full support feature parity and current-head native rerun |
| Lifecycle | Background masking, draft preservation, late-result fencing | Physical-device/app-switcher privacy verification |
| UI | iPhone simulator; light/dark and one accessibility text size | iPad, landscape, small-screen and full VoiceOver/Dynamic Type matrix |
| Deployment | iOS 15 declared; generic simulator build | iOS 15 minimum-runtime and older compiler certification |

Local baseline: Xcode 26.6, Swift 6.3.3, 24 macOS-hosted strict-concurrency unit
tests and 8 isolated loopback wire tests. A prior candidate revision passed the
six iOS 26.5 simulator UI cases. The fresh-read recovery revision still requires
a completed native rerun: its first isolated run was interrupted by host disk
pressure after three cases passed, and a retry could not create a simulator while
CoreSimulatorService was unavailable. This is an environment failure, not a test
assertion, but it is not passing evidence. The minimum Swift tools version is
a package declaration, not a claim that Swift 5.9 has been runtime-certified.
The macOS 12 target supports development/testing; this candidate is not marketed
as a certified macOS messenger. Swift 6 language mode is not yet certified.

The native example is designed to use a fresh loopback fixture and a new simulator per run.
It never uses an existing device, real customer token, live inbox, or production
database. Fixture success is not a live-provider or complete multi-tenant audit.
Inspect the exact CI run and result bundle for the revision under review.

## Still needed before production adoption

1. Review and merge the API/platform prerequisites, approve an immutable contract
   tag, and test the SDK against the exact deployed gateway version.
2. Verify real customer token issuance, renewal/revocation, cross-tenant denial,
   non-customer scopes, rate/usage limits, and anonymous-claim isolation end to end.
3. Test approved non-customer fixtures on the intended droplet, including real
   agent reply, unread/seen state, ambiguous writes, errors, and rollback. Keep
   existing consumers unchanged until parity and cutover approval are recorded.
4. Run minimum OS, older Swift/Xcode, physical device, unreliable network, iPad,
   accessibility and keyboard-layout checks. Review aggregated app privacy data
   and notices for the actual backend deployment.
5. Approve repository visibility, immutable SemVer tag, release notes and consumer
   install verification. No automatic publishing or deployment workflow exists.

## Not implemented in this candidate

- APNs registration/delivery, notification taps or background notifications.
- Attachment upload/view/download, audio, image previews, or rich/HTML messages.
- Realtime delivery, automatic polling, typing/presence or delivery/read receipts.
- Native anonymous session creation, help center, search, campaigns or outbound UI.
- Full localization (current UI is English), branding/theme configuration, and
  callbacks for custom navigation/analytics. No analytics is sent by default.
- CocoaPods distribution, signed XCFrameworks, Objective-C wrappers, or release
  tags. SwiftUI can be hosted by a UIKit app using `UIHostingController`.

Read markers are explicit; opening a conversation does not silently mark it read.
A confirmed marker refreshes server summaries, preserving drafts and newer unread
messages without repeating the write. Attachment metadata is returned but never
opened by the view. Unknown content is rendered as plain text. The host may build additional
UI using the headless API while retaining these security boundaries.

These gates apply to this repository only. Android, web, React Native, Cordova,
human self-serve activation, agent delegation, billing, and public marketing have
their own implementation and certification work; this PR does not complete them.
