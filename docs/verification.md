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

Hosted run `33613300849` confirmed that GitHub's fresh simulator can remain in
first-boot data migration for more than the initial two-minute readiness bound.
The runner stopped before starting the fixture or app and still identity-checked
and deleted its owned simulator. Readiness now has a seven-minute ceiling within
the job's existing 30-minute limit; the SDK request timeout remains unchanged.

The concurrent stacked-PR run `33613781148` then completed simulator readiness
but showed Xcode pausing the first app launch for 36 seconds while attaching UI
automation. That pause again consumed the already-started read deadline; the
other five cases passed and the owned simulator was deleted. The debug-only
example now waits for an explicit test-harness action after automation attaches
before it constructs the synthetic fixture session. This hook is not part of the
SDK or release behavior. Local run `ee3c90dd-cbff-4e55-bf9c-219441c35fcd`
passed all six cases with that ordering and removed its exact simulator. A new
hosted receipt remains required.

No live gateway, production account, customer data, management credential,
published package, release tag or production traffic was used. Hosted CI and the
remaining [release gates](../COMPATIBILITY.md) must pass before shipping. External
source-export AI review CLIs were not run; local review and tests are not an
independent security audit.
