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
simulators were not used or modified. Hosted PR 3 revision
`09b4af6177a61cd6a930e67beed1826f968276bb` also passed the package, wire,
generic-build and native gates in run `33608243470`. Neither fixture result is
live-gateway or physical-device certification.

The documentation-only current-head run `33611109503` then exposed a separate
cold-runner boundary: Xcode began the first app launch before its newly created
simulator had completed startup, the intentionally three-second SDK read timed
out, and the UI rendered its generic unreachable state. The retained xcresult
showed no other customer's content and no repeated write. The runner now boots
and waits for the exact identity-checked simulator before starting the fixture
and app. Local run `826b97d4-c0e5-4ab0-ac6c-8d2f525e3cf7` observed 47 seconds of
first-boot migration before readiness and then passed all six UI cases without
changing the production request timeout. The new revision still requires a
green hosted rerun.

No live gateway, production account, customer data, management credential,
published package, release tag or production traffic was used. Hosted CI and the
remaining [release gates](../COMPATIBILITY.md) must pass before shipping. External
source-export AI review CLIs were not run; local review and tests are not an
independent security audit.
