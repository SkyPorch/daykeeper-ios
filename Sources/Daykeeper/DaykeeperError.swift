import Foundation

/// A next step the gateway suggested. The vocabulary is deliberately closed:
/// unlike an error code, this is an instruction the app acts on, so a value this
/// release does not know is dropped rather than surfaced.
public enum DaykeeperNextAction: String, Sendable, Equatable, Codable {
  case reviewUsage = "review_usage"
  case reviewSetup = "review_setup"
  case refreshConversation = "refresh_conversation"
}

/// Safe to display or record: never contains a token, URL, body or underlying error.
public struct DaykeeperError: Error, Sendable, Equatable, Codable, CustomStringConvertible,
  LocalizedError
{
  public let code: String
  public let status: Int?
  public let retryable: Bool
  /// A write may have reached the server. Read history before a deliberate retry.
  public let outcomeUnknown: Bool
  /// Present only when the gateway sent one of the three known next actions.
  public let nextAction: DaykeeperNextAction?
  public var description: String { code }
  public var errorDescription: String? { code }

  internal init(
    _ code: String, status: Int? = nil, retryable: Bool = false, outcomeUnknown: Bool = false,
    nextAction: DaykeeperNextAction? = nil
  ) {
    self.code = code
    self.status = status
    self.retryable = retryable && !outcomeUnknown
    self.outcomeUnknown = outcomeUnknown
    self.nextAction = nextAction
  }

  internal func forWrite(dispatched: Bool) -> Self {
    Self(
      code, status: status, retryable: false,
      // A POST may already be accepted before a redirect, even if its Location
      // header is missing. Only an explicit non-timeout 4xx is a definite rejection.
      outcomeUnknown: dispatched && (status.map { !(400..<500).contains($0) || $0 == 408 } ?? true),
      nextAction: nextAction)
  }

  /// Only codes from the reviewed customer-gateway vocabulary may cross the
  /// SDK boundary. Shape alone is insufficient: token-like values such as
  /// `sk_live_123` must never become client-visible error codes. Unknown or
  /// malformed values collapse to `daykeeper_request_failed`; the envelope's
  /// `message` field is never read.
  private static let safeCodes: Set<String> = [
    "missing_bearer_token", "invalid_bearer_token", "invalid_token", "invalid_tenant",
    "unsupported_token", "invalid_signature", "invalid_issuer", "invalid_audience",
    "invalid_subject", "invalid_expiration", "expired_token", "token_lifetime_too_long",
    "unknown_tenant", "insufficient_scope", "erasure_targets_do_not_match_token",
    "unknown_campaign", "widget_token_required", "not_found", "support_upstream_rejected",
    "support_upstream_unavailable", "support_gateway_request_failed", "conversation_not_found",
    "daykeeper_usage_limit_exceeded", "daykeeper_usage_not_enabled",
    "daykeeper_support_not_ready", "daykeeper_resource_conflict",
    "daykeeper_support_unavailable", "rate_limited", "widget_unavailable",
  ]

  internal static func isSafeCode(_ value: String) -> Bool {
    safeCodes.contains(value)
  }
}
