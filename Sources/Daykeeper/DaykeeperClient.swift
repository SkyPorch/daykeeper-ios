import Foundation

public struct DaykeeperTokenRequest: Sendable {
  /// True only for one eligible GET 401. Writes never refresh and replay.
  public let forceRefresh: Bool
}
public typealias DaykeeperTokenProvider = @Sendable (DaykeeperTokenRequest) async throws -> String

/// Customer APIs only. Supply short-lived customer tokens from your own backend,
/// never a management credential. Cancel the task on logout/account changes.
public final class DaykeeperClient: @unchecked Sendable {
  private let baseURL: String
  private let tokenProvider: DaykeeperTokenProvider
  private let timeout: TimeInterval
  // Internal-only fixture hook; consumers cannot replace the security policy.
  private let protocolClasses: [AnyClass]?

  public convenience init(
    baseURL: URL, timeout: TimeInterval = 30, tokenProvider: @escaping DaykeeperTokenProvider
  ) throws {
    try self.init(
      baseURL: baseURL, timeout: timeout, tokenProvider: tokenProvider, protocolClasses: nil)
  }

  internal init(
    baseURL: URL, timeout: TimeInterval = 30, tokenProvider: @escaping DaykeeperTokenProvider,
    protocolClasses: [AnyClass]?
  ) throws {
    guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
      let scheme = components.scheme, let host = components.host, !host.isEmpty,
      components.user == nil, components.password == nil, components.query == nil,
      components.fragment == nil,
      scheme == "https" || Self.isDebugLoopback(scheme: scheme, host: host),
      timeout.isFinite, (1...60).contains(timeout)
    else { throw DaykeeperError("INVALID_CONFIGURATION") }
    var normalized = baseURL.absoluteString
    while normalized.hasSuffix("/") { normalized.removeLast() }
    self.baseURL = normalized
    self.timeout = timeout
    self.tokenProvider = tokenProvider
    self.protocolClasses = protocolClasses
  }

  public func getIdentity() async throws -> DaykeeperCustomerIdentity {
    try await request("/v1/identity")
  }
  /// Identity read that always asks the token provider for a fresh credential
  /// before the request, whatever the previous response advised. It exists so a
  /// caller can tell an expired token apart from a revoked customer without
  /// depending on the ordinary 401 retry, which a `retryable: false` hint
  /// suppresses. It is a read: nothing is ever replayed.
  public func getIdentityWithFreshToken() async throws -> DaykeeperCustomerIdentity {
    try await request("/v1/identity", forceRefresh: true)
  }
  public func listConversations() async throws -> DaykeeperConversationList {
    try await request("/v1/conversations") {
      try Self.validate($0.conversations)
      guard $0.widgetConversationId.map(Self.isSafeID) ?? true else {
        throw DaykeeperError("INVALID_RESPONSE")
      }
    }
  }
  public func createConversation() async throws -> DaykeeperConversationResult {
    try await request("/v1/conversations", write: true) { try Self.validate([$0.conversation]) }
  }
  public func getUnread() async throws -> DaykeeperUnreadSummary {
    try await request("/v1/unread") {
      guard $0.unreadCount >= 0 else { throw DaykeeperError("INVALID_RESPONSE") }
      try Self.validate($0.conversations)
      if let conversation = $0.conversation { try Self.validate([conversation]) }
    }
  }
  public func markConversationSeen(_ conversationID: Int64) async throws -> DaykeeperSeenResult {
    try Self.positive(conversationID)
    return try await request("/v1/conversations/\(conversationID)/seen", write: true) {
      guard $0.conversationId == conversationID, $0.seen, $0.seenAt >= 0,
        $0.seenMessageId.map(Self.isSafeID) ?? true
      else { throw DaykeeperError("INVALID_RESPONSE") }
    }
  }
  public func listMessages(in conversationID: Int64, after: Int64? = nil) async throws
    -> DaykeeperMessageList
  {
    try Self.positive(conversationID)
    if let after { try Self.positive(after) }
    let query = after.map { "?after=\($0)" } ?? ""
    return try await request("/v1/conversations/\(conversationID)/messages\(query)") {
      try Self.validate($0.messages, conversationID: conversationID)
    }
  }
  public func sendMessage(in conversationID: Int64, content: String) async throws
    -> DaykeeperMessageResult
  {
    try Self.positive(conversationID)
    let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty, content.utf16.count <= 16_000 else {
      throw DaykeeperError("INVALID_CONFIGURATION")
    }
    return try await request(
      "/v1/conversations/\(conversationID)/messages", write: true,
      body: try JSONEncoder().encode(["content": content])
    ) {
      try Self.validate([$0.message], conversationID: conversationID)
    }
  }
  public func claimAnonymousConversation(widgetToken: String) async throws
    -> DaykeeperClaimConversationResult
  {
    guard !widgetToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      widgetToken.utf16.count <= 16_384
    else { throw DaykeeperError("INVALID_CONFIGURATION") }
    return try await request(
      "/v1/anonymous-conversations/claim", write: true,
      body: try JSONEncoder().encode([
        "widgetToken": widgetToken.trimmingCharacters(in: .whitespacesAndNewlines)
      ])
    ) {
      guard $0.conversations >= 0 else { throw DaykeeperError("INVALID_RESPONSE") }
    }
  }

  private func request<Value: Decodable & Sendable>(
    _ path: String, write: Bool = false, body: Data? = nil, forceRefresh: Bool = false,
    validate: @escaping @Sendable (Value) throws -> Void = { _ in }
  ) async throws -> Value {
    let dispatch = RequestDispatch()
    do {
      return try await RequestLifetime<Value>.run(seconds: timeout) { [self] in
        // A forced-refresh read already carries a new credential, so it gets one
        // attempt like a write rather than a refresh-and-retry pair.
        for attempt in 0..<((write || forceRefresh) ? 1 : 2) {
          try Task.checkCancellation()
          let token: String
          do {
            token = try await tokenProvider(
              DaykeeperTokenRequest(forceRefresh: forceRefresh || attempt == 1))
          } catch {
            try Task.checkCancellation()
            throw DaykeeperError("TOKEN_PROVIDER_ERROR")
          }
          try Task.checkCancellation()
          guard !token.isEmpty, token.utf16.count <= 16_384,
            token.unicodeScalars.allSatisfy({ (33...126).contains($0.value) })
          else {
            throw DaykeeperError("INVALID_CONFIGURATION")
          }
          guard let url = URL(string: baseURL + path) else {
            throw DaykeeperError("INVALID_CONFIGURATION")
          }
          var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
          request.httpMethod = write ? "POST" : "GET"
          request.httpShouldHandleCookies = false
          request.setValue("application/json", forHTTPHeaderField: "Accept")
          request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
          request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
          if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          }
          let response = try await HTTPTransport().perform(
            request, dispatch: dispatch, protocolClasses: protocolClasses)
          try Task.checkCancellation()
          let hint = try? JSONDecoder().decode(APIHint.self, from: response.data)
          if !write, attempt == 0, response.status == 401, hint?.retryable != false { continue }
          guard (200..<300).contains(response.status) else {
            let code =
              hint?.error.flatMap { DaykeeperError.safeAPICodes.contains($0) ? $0 : nil }
              ?? "daykeeper_request_failed"
            throw DaykeeperError(
              code, status: response.status,
              retryable: !write
                && (hint?.retryable
                  ?? (response.status == 408 || response.status == 429 || response.status >= 500))
            )
          }
          let result: Value
          do { result = try JSONDecoder().decode(Value.self, from: response.data) } catch {
            throw DaykeeperError("INVALID_RESPONSE", retryable: true)
          }
          try validate(result)
          return result
        }
        throw DaykeeperError("INVALID_RESPONSE")
      }
    } catch {
      let safe: DaykeeperError
      if let error = error as? DaykeeperError {
        safe = error
      } else if error is CancellationError {
        safe = DaykeeperError("REQUEST_ABORTED")
      } else {
        safe = DaykeeperError("NETWORK_ERROR", retryable: true)
      }
      throw write ? safe.forWrite(dispatched: dispatch.occurred) : safe
    }
  }

  private struct APIHint: Decodable {
    let error: String?
    let retryable: Bool?
    enum CodingKeys: CodingKey { case error, retryable }
    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      error = try? values.decode(String.self, forKey: .error)
      retryable = try? values.decode(Bool.self, forKey: .retryable)
    }
  }
  /// Plain HTTP is a debug-only convenience for a developer's own loopback
  /// fixture. A release build never accepts an unencrypted base URL.
  private static func isDebugLoopback(scheme: String, host: String) -> Bool {
    #if DEBUG
      return scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)
    #else
      return false
    #endif
  }
  private static func positive(_ value: Int64) throws {
    guard isSafeID(value) else {
      throw DaykeeperError("INVALID_CONFIGURATION")
    }
  }
  private static func isSafeID(_ value: Int64) -> Bool {
    value > 0 && value <= 9_007_199_254_740_991
  }
  private static func validate(_ values: [DaykeeperConversation]) throws {
    guard Set(values.map(\.id)).count == values.count,
      values.allSatisfy({ isSafeID($0.id) && $0.unreadCount >= 0 && $0.unreadForContact >= 0 })
    else {
      throw DaykeeperError("INVALID_RESPONSE")
    }
  }
  private static func validate(_ values: [DaykeeperMessage], conversationID: Int64) throws {
    guard Set(values.map(\.id)).count == values.count,
      values.allSatisfy({
        isSafeID($0.id) && $0.conversationId == conversationID
          && $0.attachments.allSatisfy({ isSafeID($0.id) })
      })
    else {
      throw DaykeeperError("INVALID_RESPONSE")
    }
  }
}
