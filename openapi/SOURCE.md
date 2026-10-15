# Contract source

`customer.yaml` is an exact copy from the immutable `v1.11.0` release of
[`SkyPorch/daykeeper-openapi`](https://github.com/SkyPorch/daykeeper-openapi/releases/tag/v1.11.0),
commit `4683bfa2eef41c0948a4ea1507ceb4c8e95f1bff`.

- SHA-256: `bc77cb02b877856d2b52ce948fcda4b3b357a7885cd5f5405c3b6394d3b96251`
- Git blob: `dc1ac7a6d3191e28f296996729c9744c6b92efbb`
- License: Apache-2.0; retained verbatim in this directory's `LICENSE`.

Snapshot `v1.11.0` (customer contract 0.2.0) adds only the optional
`Daykeeper-Client` request header on every customer-session operation, which
this client already sends by default. Earlier snapshot changes include an open `CustomerError` envelope
(`additionalProperties: true`) and an explicit API-only gateway restriction:
`getIdentity` and `claimAnonymousConversation` return the stable
`API_ONLY_WIDGET_OPERATION` 409 response there. This client already ignores
unknown fields, so an added field must never be treated as a decode failure.

Swift models are handwritten, not generated. Tests exercise representative wire
shapes and all eight customer operations; decoding is not a full JSON Schema
validator. Extra response fields are ignored for forward compatibility. Service
operations in the source contract are deliberately absent from the customer SDK.

The message list exposes only a forward `after` cursor. There is no `before` or
page-size parameter. The client can therefore page forward from a message it
already holds, but it cannot ask the gateway for an older window, and it has no
way to bound the size of the default window. A conversation whose default
response exceeds the transport's 1 MiB ceiling stays unreadable until the
gateway gains a page-size or backward-cursor parameter; no client-side change
can fix it. Do not add a "load earlier" affordance that simply re-requests the
same default window — it repeats the request that already failed.

Before release, bind this snapshot to an approved immutable contract tag, review
model/operation changes, and rerun package, wire, native, and deployed-gateway
checks. A hash match does not certify backend compatibility.
