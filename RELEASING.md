# Releasing the Daykeeper Apple SDK

This is an unreleased Swift Package Manager candidate. No public package tag or
GitHub Release exists yet. Successful local or hosted verification does not
authorize publication.

## Distribution model

Swift Package Manager resolves this repository directly. For the intended
source-based distribution, the immutable `vMAJOR.MINOR.PATCH` Git tag is the
published package version; there is no separate package registry upload.

Daykeeper currently ships the `Daykeeper` and `DaykeeperUI` library products
from one package. Binary frameworks, CocoaPods, and Carthage are outside the
initial release scope.

## Repository bootstrap

1. Approve public repository visibility and verify that public history contains
   no customer data, credentials, internal hostnames, or private product names.
2. Protect the default branch and `v*` tags. Only reviewed commits on the
   default branch may become releases.
3. Configure a protected `daykeeper-apple-production` environment with a
   non-author reviewer for any future release-note or provenance automation.
   That environment must not be reachable from pull-request or fork jobs.
4. Keep tag creation manual. Merging a pull request must never create or move a
   version tag, publish a GitHub Release, or change repository visibility.

## Release gate

1. Choose one exact SemVer version and update `CHANGELOG.md`, compatibility
   evidence, and the customer API contract snapshot in the same release PR.
2. Run the full hosted package job from the exact release commit, including
   strict formatting, strict-concurrency tests, wire tests, the generic simulator
   build, the independent SwiftPM consumer, and all native UI checks.
3. Run messenger and recovery scenarios on authorized physical iPhone and iPad
   devices. Simulator results are not physical-device evidence.
4. Run accessibility checks, the declared minimum iOS and macOS versions, and
   the supported Xcode/Swift compatibility matrix.
5. Run `gitleaks git . --no-banner --redact` and review dependency licenses,
   privacy manifests, public API documentation, examples, screenshots, notices,
   and generated package contents.
6. Verify a clean external consumer can resolve the exact candidate commit by
   URL and build both products without relying on a sibling checkout.
7. After approval, tag the reviewed default-branch commit exactly
   `vMAJOR.MINOR.PATCH`. Then verify a fresh external consumer can resolve that
   exact public tag before creating matching GitHub release notes.

Swift package tags are immutable release inputs. Never force-move or reuse a
version tag. If a release is wrong, correct it in a new version.
