# Contract source

`customer.yaml` is an exact copy of `openapi/customer.yaml` from the local,
unreleased canonical `SkyPorch/daykeeper-openapi` commit
`f7771f5ce1d48140ddbf38a113aeec60651b8d79`. No release tag exists for this
commit.

- SHA-256: `1072bb8df15e4f96bb9463f8bb77d9b5a7b0b97d762ee25599bee6f81dd55b51`
- Git blob: `7285478b62e6ec33b2c35e7503508a73930433b8`
- License: Apache-2.0; retained verbatim in this directory's `LICENSE`.

The contract adds mutually exclusive positive `before` and `after` message
cursors. The initial read returns the latest 20 customer-visible messages in
ascending order; `before` returns up to 20 older messages; `after` returns up to
20 newer messages. Each response is capped at 768 KiB of UTF-8 JSON: initial and
older pages keep the newest contiguous suffix that fits, while newer pages keep
the oldest prefix. If one message alone exceeds the cap, the gateway returns
`413 message_too_large`. Clients should continue loading older pages until an
empty page, since a short page alone does not prove exhaustion after defensive
filtering.

Swift models are handwritten, not generated. Tests exercise representative wire
shapes and all eight customer operations; decoding is not a full JSON Schema
validator. Extra response fields are ignored for forward compatibility. Service
operations in the source contract are deliberately absent from the customer SDK.

This local snapshot is not a release provenance claim. Before publishing,
replace the local commit reference with an approved immutable contract tag and
its full commit SHA, then rerun package, wire, native and deployed-gateway
checks. A hash match does not certify backend compatibility.
