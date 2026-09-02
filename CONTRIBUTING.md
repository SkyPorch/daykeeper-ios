# Contributing

Customer API changes start in `SkyPorch/daykeeper-openapi`. Update the vendored
tagged contract before changing SDK surface, and keep public types a thin
mapping over stable OpenAPI operation identifiers.

The SDK takes only short-lived, tenant-bound end-user tokens. It must never
accept administrative credentials. Add tests for retries, timeouts,
cancellation, and error mapping alongside any new operation.

Examples, fixtures, and documentation must stay synthetic: no real tenant
names, customer data, bundle identifiers, hostnames, or downstream product
names.

Run the repository's checks before requesting review.
