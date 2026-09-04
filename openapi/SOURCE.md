# Contract source

`customer.yaml` is the unchanged customer contract from
[`SkyPorch/daykeeper-openapi`](https://github.com/SkyPorch/daykeeper-openapi/tree/4a2b82c9b23503073dc26fdeb5163e8869d007b8),
commit `4a2b82c9b23503073dc26fdeb5163e8869d007b8` (unreleased; head of branch
`codex/daykeeper-agent-credentials`, pull request SkyPorch/daykeeper-openapi#13).

- SHA-256: `ae75711072950c786d69401301292659ece7f37461cf0621ae4f8a58836b82bd`
- Git blob: `9cdf5423e73ad8008fc62adeb8c66e3c018c357d`
- License: Apache-2.0; retained verbatim in this directory's `LICENSE`.

Change from the previous snapshot: `CustomerError` is now an open envelope
(`additionalProperties: true`). The gateway may add fields to an error body, and
`message`, `retryable` and `nextAction` are optional. This client already ignores
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
