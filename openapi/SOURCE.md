# Contract source

`customer.yaml` is an exact copy from the immutable `v1.1.0` release of
[`SkyPorch/daykeeper-openapi`](https://github.com/SkyPorch/daykeeper-openapi/releases/tag/v1.1.0),
commit `c9a0175d0053f1a2d57c9329f6d3a36ec6acdb71`.

- SHA-256: `322158cd5fa5c54a054d701ff64a9c8b07cad477414d7df83ba5a3aa7ee06cc3`
- Git blob: `bf566c97a541ac5e4e1f04670fb3b65475b635a6`
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
