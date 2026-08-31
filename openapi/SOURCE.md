# Contract source

`customer.yaml` is the unchanged customer contract from
[`SkyPorch/daykeeper-openapi`](https://github.com/SkyPorch/daykeeper-openapi/tree/f2ae208de7c2c0422482d3f8b16c8c6f7542c347),
commit `f2ae208de7c2c0422482d3f8b16c8c6f7542c347` (unreleased).

- SHA-256: `b62dd386a87380f3fe94f968ff8fedf703ca6079199ea74057d32e31f91e1fec`
- Git blob: `2f1b48fedaddfb7335389f75640e5e3b301575fb`
- License: Apache-2.0; retained verbatim in this directory's `LICENSE`.

Swift models are handwritten, not generated. Tests exercise representative wire
shapes and all eight customer operations; decoding is not a full JSON Schema
validator. Extra response fields are ignored for forward compatibility. Service
operations in the source contract are deliberately absent from the customer SDK.

Before release, bind this snapshot to an approved immutable contract tag, review
model/operation changes, and rerun package, wire, native, and deployed-gateway
checks. A hash match does not certify backend compatibility.
