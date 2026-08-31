import Foundation

/// Safe to display or record: never contains a token, URL, body or underlying error.
public struct DaykeeperError: Error, Sendable, Equatable, Codable, CustomStringConvertible,
  LocalizedError
{
  public let code: String
  public let status: Int?
  public let retryable: Bool
  /// A write may have reached the server. Read history before a deliberate retry.
  public let outcomeUnknown: Bool
  public var description: String { code }
  public var errorDescription: String? { code }

  internal init(
    _ code: String, status: Int? = nil, retryable: Bool = false, outcomeUnknown: Bool = false
  ) {
    self.code = code
    self.status = status
    self.retryable = retryable && !outcomeUnknown
    self.outcomeUnknown = outcomeUnknown
  }

  internal func forWrite(dispatched: Bool) -> Self {
    Self(
      code, status: status, retryable: false,
      outcomeUnknown: status.map { $0 == 408 || $0 >= 500 } ?? dispatched)
  }

  internal static let safeAPICodes: Set<String> = [
    "missing_bearer_token", "invalid_bearer_token", "invalid_token", "unsupported_token",
    "invalid_signature", "invalid_tenant", "unknown_tenant", "invalid_issuer", "invalid_audience",
    "invalid_subject", "invalid_expiration", "expired_token", "token_lifetime_too_long",
    "insufficient_scope", "not_found", "rate_limited", "support_upstream_rejected",
    "support_upstream_unavailable", "daykeeper_usage_limit_exceeded", "daykeeper_usage_not_enabled",
    "daykeeper_support_not_ready", "daykeeper_resource_conflict", "daykeeper_support_unavailable",
  ]
}
