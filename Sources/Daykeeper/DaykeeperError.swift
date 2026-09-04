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

  /// The gateway's error vocabulary is open: it gains codes without an SDK
  /// release, and a consuming app switches on them, so the SDK checks the shape
  /// of a code rather than matching it against a list it would have to chase.
  /// The rule is `^[a-z][a-z0-9_]{2,63}$`. Anything else — a free-form English
  /// sentence, an upper-case or hyphenated token, a value that is not a JSON
  /// string at all — is not a code and collapses to `daykeeper_request_failed`,
  /// which is what keeps server prose out of a client-visible error. The
  /// envelope's `message` field is never read for the same reason.
  internal static func isSafeCode(_ value: String) -> Bool {
    let scalars = value.unicodeScalars
    guard (3...64).contains(scalars.count), let first = scalars.first,
      ("a"..."z").contains(first)
    else { return false }
    return scalars.dropFirst().allSatisfy {
      ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_"
    }
  }
}
