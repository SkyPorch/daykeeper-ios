# Security

Do not put credentials, customer messages, tokens, or private gateway URLs in
public issues, logs, screenshots, or crash reports. SDK error values are sanitized;
successful response models are not safe telemetry payloads.

Use GitHub private vulnerability reporting when enabled. Otherwise contact a
repository maintainer privately through your existing SkyPorch support channel.
Do not open a public exploit report containing customer data.

The SDK requires a trusted HTTPS gateway and a token provider bound to a stable
customer. The backend, not the SDK, authorizes tenant/customer ownership. Reset
the native session before switching users; cancel and fence headless requests in
your own app. No management token or signing key belongs in a client bundle.

This candidate is unreleased. No supported-version or security-response SLA is
claimed yet. Review [release gates](COMPATIBILITY.md) before production adoption.
