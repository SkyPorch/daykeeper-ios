# Candidate verification

Recorded September 1, 2026, before publication. These results apply to the
candidate source and local fixtures, not production traffic.

| Check | Result |
| --- | --- |
| Strict-concurrency unit tests | 24 passed, including 9 messenger-session cases |
| Isolated loopback wire tests | 8 passed through the production URLSession transport |
| Current-head native UI run | 6 cases passed on a newly created iOS 26.5 iPhone 16 simulator |
| Source formatting and whitespace | Passed |

The current recovery guards require a successful fresh conversation/history read
before a preserved uncertain write can be acknowledged or discarded. Unit tests
cover failed rereads, foreground recovery, explicit human confirmation and the
absence of repeated writes. The current-head XCUITest run verifies that each
recovery control is disabled before refresh, enabled afterward, and confirmed
through the exact bounded alert action without repeating either write.

The complete run used a newly created isolated simulator and a loopback fixture.
All six native cases passed, the result bundle was retained locally, and the
runner identity-checked and removed only its owned simulator. Existing user
simulators were not used or modified. The hosted PR 3 head still must rerun green;
the local result is not a portable hosted receipt.

No live gateway, production account, customer data, management credential,
published package, release tag or production traffic was used. Hosted CI and the
remaining [release gates](../COMPATIBILITY.md) must pass before shipping. External
source-export AI review CLIs were not run; local review and tests are not an
independent security audit.
