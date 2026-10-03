# Contract source

`customer.yaml` is an exact copy of `openapi/customer.yaml` from the local,
unreleased canonical `SkyPorch/daykeeper-openapi` commit
`325c9496ab40fbb7da60f2fc75d57c9d5e1c2b39`. No release tag exists for this
commit.

- SHA-256: `6a72fea574acd85dfb678b3b63c927bb3ea6506814baa6f0e774842947c64b83`
- Git blob: `77d27d4603c5bfd16b97fb3fd517e429078113e2`
- License: Apache-2.0; retained verbatim in this directory's `LICENSE`.

The contract supports two response profiles. Requests without `pagination=cursor`
retain the legacy envelope and identifier behavior. Cursor mode is explicitly
opted into with `pagination=cursor` on every initial, `after`, and `before`
request; those responses require a top-level `pagination: "cursor"` marker.
Initial and `before` pages return up to 20 customer-visible messages, keeping
the newest contiguous suffix that fits a 768 KiB UTF-8 JSON envelope; `after`
pages return up to 20, keeping the oldest prefix. Cursor-mode message IDs must
be positive safe integers. A single message that exceeds the envelope returns
`413 message_too_large`; an unsafe provider identifier returns
`502 message_id_out_of_range`. Clients continue loading older pages until an
empty page, since a short page alone does not prove exhaustion after filtering.

Swift models are handwritten, not generated. Tests exercise representative wire
shapes and all eight customer operations; decoding is not a full JSON Schema
validator. Extra response fields are ignored for forward compatibility. Service
operations in the source contract are deliberately absent from the customer SDK.

This local snapshot is not a release provenance claim. Before publishing,
replace the local commit reference with an approved immutable contract tag and
its full commit SHA, then rerun package, wire, native and deployed-gateway
checks. A hash match does not certify backend compatibility.
