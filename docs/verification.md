# Candidate verification

Recorded September 1, 2026, before publication. These results apply to the
candidate source and local fixtures, not production traffic.

| Check | Result |
| --- | --- |
| Strict-concurrency unit tests | 24 passed, including 9 messenger-session cases |
| Isolated loopback wire tests | 8 passed through the production URLSession transport |
| Current-head native UI run | Incomplete; 3 cases passed before host disk pressure interrupted the fourth |
| Prior-revision native UI run | 6 cases passed on a newly created iOS 26.5 iPhone 16 simulator |
| Source formatting and whitespace | Passed |

The current recovery guards require a successful fresh conversation/history read
before a preserved uncertain write can be acknowledged or discarded. Unit tests
cover failed rereads, foreground recovery, explicit human confirmation and the
absence of repeated writes. XCUITest source also checks the recovery control is
disabled before refresh and enabled afterward, but those new native assertions
are not certified until a complete current-head simulator run passes.

The interrupted native run used a newly created isolated simulator. Three cases
passed before Xcode stopped while writing its result bundle; no assertion failure
was reported. The runner removed that simulator. A retry stopped before creating
a device because CoreSimulatorService was unavailable. Existing user simulators
were not used or modified.

No live gateway, production account, customer data, management credential,
published package, release tag or production traffic was used. Hosted CI and the
remaining [release gates](../COMPATIBILITY.md) must pass before shipping. External
source-export AI review CLIs were not run; local review and tests are not an
independent security audit.
