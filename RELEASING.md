# Releasing the Daykeeper Apple SDK

This is an unreleased Swift Package Manager and CocoaPods candidate. No public
package tag, pod or GitHub Release exists yet. Successful local or hosted
verification does not authorize publication.

## Distribution model

Swift Package Manager resolves this repository directly. For the intended
source-based distribution, the immutable `vMAJOR.MINOR.PATCH` Git tag is the
published package version; there is no separate package registry upload.

Daykeeper currently ships the `Daykeeper` and `DaykeeperUI` library products
from one Swift package. CocoaPods uses two source specs from the same immutable
tag so both products retain their existing module names. `DaykeeperUI` depends on
the exact same `Daykeeper` version. Binary frameworks and Carthage remain outside
the initial release scope.

CocoaPods trunk is scheduled to become read-only on December 2, 2026. If
CocoaPods parity remains a launch requirement, complete the separately approved
bootstrap release before that date; do not weaken review or publish an unverified
pod merely to meet the deadline.

## Repository bootstrap

1. Approve public repository visibility and verify that public history contains
   no customer data, credentials, internal hostnames, or private product names.
2. Protect the default branch and `v*` tags. Only reviewed commits on the
   default branch may become releases.
3. Configure a protected `daykeeper-apple-production` environment with a
   non-author reviewer for any future release-note or provenance automation.
   That environment must not be reachable from pull-request or fork jobs.
4. Keep tag creation manual. Merging a pull request must never create or move a
   version tag, publish a pod or GitHub Release, or change repository visibility.
5. Register and verify the intended SkyPorch CocoaPods trunk owner through an
   operator terminal. Keep the trunk session token out of CI, source, logs and
   command arguments. Confirm that both `Daykeeper` and `DaykeeperUI` names remain
   available immediately before the first approved publication.

## Release gate

1. Choose one exact SemVer version and update `CHANGELOG.md`, compatibility
   evidence, and the customer API contract snapshot in the same release PR.
2. Run the full hosted package job from the exact release commit, including
   strict formatting, strict-concurrency tests, wire tests, the generic simulator
   build, both local CocoaPods source consumers, the independent SwiftPM consumer,
   and all native UI checks.
3. Run messenger and recovery scenarios on authorized physical iPhone and iPad
   devices. Simulator results are not physical-device evidence.
4. Run accessibility checks, the declared minimum iOS and macOS versions, and
   the supported Xcode/Swift compatibility matrix.
5. Run `gitleaks git . --no-banner --redact` and review dependency licenses,
   privacy manifests, public API documentation, examples, screenshots, notices,
   and generated package contents.
6. Verify a clean external consumer can resolve the exact candidate commit by
   URL and build both SwiftPM products without relying on a sibling checkout.
7. After approval, tag the reviewed default-branch commit exactly
   `vMAJOR.MINOR.PATCH`. Then verify fresh external consumers can resolve that
   exact public tag through SwiftPM and both podspec source definitions before
   creating matching GitHub release notes.

## CocoaPods bootstrap

Pod publication is a separate, irreversible registry action after the reviewed
tag exists. It is never performed by pull-request CI:

1. Confirm both podspec versions equal the tag without the leading `v`, their
   source tags equal that exact tag, and the working tree is clean.
2. Run `pod spec lint Daykeeper.podspec --platforms=ios --skip-tests` against the
   public tag. Run the `DaykeeperUI` lint with
   `--include-podspecs=Daykeeper.podspec` before either registry write.
3. With explicit publication approval, run `pod trunk push Daykeeper.podspec`.
   Wait for the exact version to resolve from the public CDN and build it in a
   clean consumer.
4. Run `pod spec lint DaykeeperUI.podspec --platforms=ios --skip-tests` against
   the now-public exact core dependency. Only after it passes and receives its
   own approval, run `pod trunk push DaykeeperUI.podspec`.
5. Resolve both exact public pod versions in a fresh app, build imports for both
   modules, verify the privacy manifest is packaged once, and attach that evidence
   to the GitHub Release.

A partial release of the headless core remains valid and must not be overwritten
or deleted if the optional UI publication fails. Fix any defect in a new SemVer
version and tag.

Swift package tags are immutable release inputs. Never force-move or reuse a
version tag. CocoaPods versions are immutable registry inputs too. If a release is
wrong, correct it in a new version.
