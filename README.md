# Daykeeper for iOS

Native customer support for iOS, maintained by SkyPorch. Two Swift Package Manager
products, no third-party runtime dependencies:

- `Daykeeper`: typed, async customer APIs for a custom support experience.
- `DaykeeperUI`: a SwiftUI conversation list, message history, and composer.

**Unreleased candidate.** No release tag or production certification yet. Review
[compatibility and release gates](COMPATIBILITY.md) before adopting it. This is
not yet a complete replacement for an existing production messenger.

## Install for evaluation

Check out the reviewed feature revision and add this directory as a local Swift
package in Xcode, or use `.package(path: "../daykeeper-ios")`. Add the `Daykeeper`
and optional `DaykeeperUI` products to your app target. The included native example
uses this same consumer integration, not direct source inclusion.

After an approved release, the package URL will be
`https://github.com/SkyPorch/daykeeper-ios.git`. Pin an immutable SemVer release;
do not depend on a moving development branch in production.

The same reviewed tag is also a candidate for two source-based CocoaPods:

```ruby
pod "Daykeeper", "~> 0.1"
pod "DaykeeperUI", "~> 0.1" # Optional SwiftUI messenger
```

Neither pod is published. To evaluate the local podspecs, point both modules at
this checkout so the UI dependency cannot resolve a different core:

```ruby
pod "Daykeeper", :path => "../daykeeper-ios"
pod "DaykeeperUI", :path => "../daykeeper-ios"
```

There is no binary-framework release in this candidate. CocoaPods and SwiftPM
must resolve the same version and expose the existing `Daykeeper` and
`DaykeeperUI` module names.

The deployment target is iOS 15. Swift tools 5.9 or newer are required; tested
toolchains and runtime limits are recorded in [COMPATIBILITY.md](COMPATIBILITY.md).

## Authenticate through your backend

The app receives short-lived, tenant-bound **customer tokens** from its own
authenticated backend. Tenant administration credentials and signing keys never
belong in the app. The gateway URL must be your configured HTTPS endpoint; there
is no default hosted origin.

```swift
import Daykeeper

func supportClient(
  gatewayURL: URL,
  customerToken: @escaping DaykeeperTokenProvider
) throws -> DaykeeperClient {
  try DaykeeperClient(baseURL: gatewayURL, tokenProvider: customerToken)
}
```

Implement `customerToken` using your app's authenticated backend. It is called
for every request. When `request.forceRefresh` is true, obtain a fresh token
rather than return the expired one. This occurs at most once for an eligible GET
401; it never causes a write to be replayed. Keep the provider tied to one stable
customer. Cancel old headless tasks, or reset the messenger, **before** changing
the signed-in account. Do not use a closure that silently switches identities.

## Present the messenger

```swift
import Daykeeper
import DaykeeperUI
import SwiftUI

@MainActor struct SupportScreen: View {
  @StateObject private var session: DaykeeperMessengerSession

  init(client: DaykeeperClient) {
    _session = StateObject(wrappedValue: DaykeeperMessengerSession(client: client))
  }

  var body: some View {
    DaykeeperMessenger(session: session)
  }
}
```

Own the session alongside your app's authentication state when you need to reset
it from outside the screen. Call `session.reset()` on logout, then construct a
new client and session for another customer. Reset cancels pending work, drops
the token provider, clears drafts/history, and fences late responses. A final
401 or 403 also clears the native messenger. The headless client does not own
your authentication or UI state.

The view refreshes on presentation and foregrounding, hides its customer data
when inactive, and preserves drafts in memory when temporarily suspended. It
does not promise secure-memory erasure or protection from host screenshots. The
host must apply any app-switcher privacy overlay required by its threat model.

## Use the headless API

```swift
let list = try await client.listConversations()
let unread = try await client.getUnread()
// Use unread.unreadCount or conversation.unreadForContact for customer badges.
let thread = try await client.listMessages(in: conversationID, after: nil)
let sent = try await client.sendMessage(in: conversationID, content: "Hello")
```

The other customer operations are `getIdentity`, `createConversation`,
`markConversationSeen`, and `claimAnonymousConversation(widgetToken:)`.
The headless client covers API-only inbox operations (conversation, unread, and
message access). `getIdentity` and `claimAnonymousConversation(widgetToken:)`
are widget operations: they require a widget-enabled tenant gateway and an
anonymous widget possession token for claims. API-only gateways reject both
widget operations with `409` and the safe `widget_unavailable` error before
calling the conversation provider. The native view does not create an
anonymous widget session. Account provisioning, billing, lifecycle campaigns,
and erasure are backend-only operations and are not exposed here.

## Recover without accidental duplicate writes

Errors returned by the SDK expose a safe `code`, optional HTTP `status`,
`retryable`, and `outcomeUnknown`. Raw responses, tokens, URLs, and underlying
errors are not included. Customer message/identity response models are sensitive;
do not log them.

- A GET can refresh its token once after 401, unless the server says
  `retryable: false`. No other automatic request retries are implemented.
- Writes make one SDK attempt, including create, send, seen, and claim. They are
  never automatically replayed after a timeout, cancellation, 401, or 5xx.
- `outcomeUnknown` means a write may have reached the server. Refresh and inspect
  history before a deliberate new action. Cancellation cannot undo server work.
- The messenger preserves an uncertain message draft and disables editing, Send,
  and discard until a fresh history read succeeds. Failed reads and backgrounding
  invalidate that readiness. Uncertain creation similarly requires a successful
  fresh list read before acknowledgement. Neither recovery action resends anything.
- Usage ceilings preserve history and drafts. They do not trigger upgrades,
  billing actions, or automatic retries.

One SDK attempt is **not an exactly-once delivery guarantee**. System networking,
proxies, or a caller can still produce ambiguous outcomes. Server idempotency is
required before promising exactly-once writes.

Requests have a 30-second total deadline by default (configurable from 1–60s),
including credential acquisition and response reading. An uncooperative token
provider can continue its own work after cancellation, but a late result cannot
dispatch the canceled SDK request. Decoded response bodies are capped at 1 MiB.
Redirects, ambient cookies/credentials, and HTTP caching are disabled. HTTPS is
always required in a release build.

Plain `http://` to an exact loopback host (`localhost`, `127.0.0.1`, `::1`) is
accepted only when this SDK itself is compiled with `DEBUG` defined — that is
the SDK target's own build configuration, not your app's. A SwiftPM or
CocoaPods consumer building the package in Debug gets the local-fixture
convenience; a Release build of the SDK refuses every unencrypted base URL, so
it cannot be reached in a shipped app.

Message history is read forward with the contract's `after` cursor. Refreshing
an open thread asks only for messages newer than the last one held, so a long
conversation is not re-read in full each time. The customer contract has no
backward cursor or page-size parameter, so the client cannot request an older
window; a thread whose first page already exceeds the 1 MiB response cap needs a
gateway-side page parameter before it can be opened.

## Privacy and licensing

There is no analytics, advertising, push registration, swizzling, remote asset
loading, or persistent customer storage in this package. Support messages and
customer tokens are transmitted to the configured gateway. The privacy manifest
declares linked support content and customer identifiers, including name/email
when supplied in customer tokens, for app functionality—not tracking. Review
your backend's retention and data use, token contents, consent flows, and App
Store disclosures for your actual integration. See
[Apple's privacy guidance](https://developer.apple.com/app-store/app-privacy-details/).

SDK code is [MIT licensed](LICENSE). The vendored API contract retains its
[Apache-2.0 license](openapi/LICENSE) and [source provenance](openapi/SOURCE.md).

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for unit, real-network, native UI, and
package-consumer checks. Report vulnerabilities privately as described in
[SECURITY.md](SECURITY.md).
