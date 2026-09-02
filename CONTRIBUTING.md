# Contributing

Keep customer SDKs independent of the server and consuming applications. Use
Intercom's native support conventions as the UX reference and Resend's explicit
developer lifecycle as the API reference. Do not add administrative authority,
hidden retries, device tracking, or provider-specific implementation details.

## Checks

On a Mac with Xcode and Node 22:

```sh
node Scripts/check-contract.mjs
swift format lint --strict --recursive Package.swift Sources Tests Examples
swift test --skip WireTests -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
node Scripts/check-wire.mjs
node Scripts/check-cocoapods.mjs
node Scripts/check-ios.mjs
```

The wire runner starts and stops its own loopback fixture. Native UI checks
always create, test, and delete a **new** iPhone simulator, using an installed
iOS 18+ runtime. They never accept an existing device destination. Logs name the
exact created device; screenshots and test receipts remain in `TestResults/`.
Fixtures contain synthetic customers and are not authentication templates.

The native example is an external SwiftPM consumer of both products. Open
`Examples/DaykeeperExample/DaykeeperExample.xcodeproj` to inspect it. Debug fixture
configuration is supplied by its tests. A normal unconfigured or Release launch
fails closed without connecting anywhere. Regenerate the checked-in project with
`xcodegen generate --spec Examples/DaykeeperExample/project.yml` after changing
the project specification; review generated changes for local paths.

The CocoaPods check requires the CocoaPods 1.16.2 gem and invokes that version
explicitly with RubyGems' version selector. It parses both podspecs,
rejects metadata drift or release scripts, then uses `pod lib lint` to compile a
clean core consumer and a separate UI consumer with the exact local core spec.
It never pushes a pod or uses a trunk token.

## Review and releases

Stage changes before running `swift format format --in-place`. Keep the vendored
contract byte-for-byte intact; its checksum and source record are reviewed
together. Models are handwritten, so a checksum check does not replace model or
backend compatibility tests. Use normal ready-for-review pull requests and
include screenshots for rendered changes.

Do not merge, tag, publish, deploy, or change repository visibility without
maintainer approval. Document incompatible API changes in the changelog. Before
1.0, a breaking change increments the minor version; afterwards it increments
the major version. A release must reference an immutable contract tag and pass
all gates in [COMPATIBILITY.md](COMPATIBILITY.md). Never retarget a published tag.
