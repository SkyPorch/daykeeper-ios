import XCTest

@testable import Daykeeper

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Bool] = []
  func record(_ value: Bool) {
    lock.lock()
    values.append(value)
    lock.unlock()
  }
  var all: [Bool] {
    lock.lock()
    defer { lock.unlock() }
    return values
  }
}

private final class Stub: @unchecked Sendable {
  enum Reply {
    case response(Int, Data, [String: String] = [:])
    case stall
  }
  private let lock = NSLock()
  private var recorded: [URLRequest] = []
  private var replies: [Reply]
  let host = "test-\(UUID().uuidString.lowercased()).example.test"
  init(_ replies: [Reply]) {
    self.replies = replies
    StubProtocol.register(self)
  }
  func next(_ request: URLRequest) -> Reply {
    lock.lock()
    defer { lock.unlock() }
    recorded.append(request)
    return replies.isEmpty ? .response(500, Data()) : replies.removeFirst()
  }
  var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }
  func client(
    timeout: TimeInterval = 30, token: @escaping DaykeeperTokenProvider = { _ in "synthetic-token" }
  ) throws -> DaykeeperClient {
    try DaykeeperClient(
      baseURL: URL(string: "https://\(host)/support-api")!, timeout: timeout,
      tokenProvider: token, protocolClasses: [StubProtocol.self])
  }
}

extension Stub.Reply {
  fileprivate static func json(_ status: Int, _ value: Any) -> Self {
    .response(status, try! JSONSerialization.data(withJSONObject: value))
  }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
  private final class Registry: @unchecked Sendable {
    let lock = NSLock()
    var stubs: [String: Stub] = [:]
  }
  private static let registry = Registry()
  static func register(_ stub: Stub) {
    registry.lock.lock()
    registry.stubs[stub.host] = stub
    registry.lock.unlock()
  }
  private static func find(_ request: URLRequest) -> Stub? {
    registry.lock.lock()
    defer { registry.lock.unlock() }
    return registry.stubs[request.url?.host ?? ""]
  }
  override class func canInit(with request: URLRequest) -> Bool { find(request) != nil }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let stub = Self.find(request) else { return }
    switch stub.next(request) {
    case .stall: break
    case .response(let status, let data, let headers):
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    }
  }
  override func stopLoading() {}
}

final class TransportTests: XCTestCase {
  private let conversation: [String: Any] = [
    "id": 7, "status": "open", "createdAt": NSNull(), "updatedAt": 123,
    "unreadCount": 8, "unreadForContact": 2, "lastSeenAt": NSNull(), "preview": "Hello",
  ]
  private var message: [String: Any] {
    [
      "id": 9, "conversationId": 7, "content": "Hello", "contentType": "text",
      "contentAttributes": [:], "messageType": 0, "createdAt": 123, "sender": NSNull(),
      "attachments": [],
    ]
  }
  private let emptyList: [String: Any] = ["conversations": [], "widgetConversationId": NSNull()]

  func testAllEightCustomerMethodsUseExactPrefixAndMethods() async throws {
    let identity: [String: Any] = [
      "baseUrl": "https://widget.example.test", "websiteToken": "public-id", "subject": "customer",
      "identifier": "customer", "identifierHash": "synthetic", "email": NSNull(),
      "name": "Customer",
    ]
    let stub = Stub([
      .json(200, identity), .json(200, emptyList), .json(201, ["conversation": conversation]),
      .json(
        200, ["unreadCount": 2, "conversation": conversation, "conversations": [conversation]]),
      .json(200, ["conversationId": 7, "seen": true, "seenAt": 123]),
      .json(200, ["messages": [message]]),
      .json(201, ["message": message]), .json(200, ["status": "merged", "conversations": 1]),
    ])
    let client = try stub.client()
    let result = try await client.getIdentity()
    XCTAssertEqual(result.subject, "customer")
    _ = try await client.listConversations()
    _ = try await client.createConversation()
    _ = try await client.getUnread()
    _ = try await client.markConversationSeen(7)
    _ = try await client.listMessages(in: 7, after: 3)
    _ = try await client.sendMessage(in: 7, content: " Hello ")
    _ = try await client.claimAnonymousConversation(widgetToken: " anonymous ")
    XCTAssertEqual(
      stub.requests.map {
        $0.url!.absoluteString.replacingOccurrences(of: "https://\(stub.host)", with: "")
      },
      [
        "/support-api/v1/identity", "/support-api/v1/conversations",
        "/support-api/v1/conversations", "/support-api/v1/unread",
        "/support-api/v1/conversations/7/seen", "/support-api/v1/conversations/7/messages?after=3",
        "/support-api/v1/conversations/7/messages", "/support-api/v1/anonymous-conversations/claim",
      ])
    XCTAssertEqual(
      stub.requests.map(\.httpMethod), ["GET", "GET", "POST", "GET", "POST", "GET", "POST", "POST"])
    for request in stub.requests {
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache, no-store")
      XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
      XCTAssertFalse(request.httpShouldHandleCookies)
      XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
    }
  }

  func testRead401RefreshIsBoundedAndWritesNeverReplay() async throws {
    let calls = Counter()
    let stub = Stub([.json(401, ["error": "expired_token"]), .json(200, emptyList)])
    let client = try stub.client { request in
      calls.record(request.forceRefresh)
      return "synthetic-token"
    }
    _ = try await client.listConversations()
    XCTAssertEqual(calls.all, [false, true])
    XCTAssertEqual(stub.requests.count, 2)
    for status in [401, 408, 429, 500] {
      let calls = Counter()
      let stub = Stub([.json(status, ["error": "expired_token", "retryable": true])])
      let client = try stub.client { request in
        calls.record(request.forceRefresh)
        return "synthetic-token"
      }
      do {
        _ = try await client.createConversation()
        XCTFail("Expected rejection")
      } catch let error as DaykeeperError {
        XCTAssertEqual(error.status, status)
        XCTAssertFalse(error.retryable)
        XCTAssertEqual(error.outcomeUnknown, status == 408 || status >= 500)
      }
      XCTAssertEqual(calls.all, [false])
      XCTAssertEqual(stub.requests.count, 1)
    }
  }

  func testRedirectStatusesWithoutLocationKeepWriteOutcomeUncertain() async throws {
    for status in [300, 301, 302, 303, 304, 305, 307, 308] {
      let stub = Stub([.json(status, [:])])
      let client = try stub.client { _ in "synthetic-token" }
      do {
        _ = try await client.createConversation()
        XCTFail("Expected redirect rejection")
      } catch let error as DaykeeperError {
        XCTAssertEqual(error.status, status)
        XCTAssertTrue(error.outcomeUnknown)
        XCTAssertFalse(error.retryable)
      }
      XCTAssertEqual(stub.requests.count, 1)
    }
  }

  func testAPIOnlyWidgetRefusalsAreSafeAndNeverRetried() async throws {
    let calls = Counter()
    let identityStub = Stub([
      .json(
        409,
        [
          "error": "widget_unavailable", "message": "provider-secret", "retryable": true,
        ])
    ])
    let identityClient = try identityStub.client { request in
      calls.record(request.forceRefresh)
      return "synthetic-token"
    }
    do {
      _ = try await identityClient.getIdentity()
      XCTFail("Expected API-only widget refusal")
    } catch let error as DaykeeperError {
      XCTAssertEqual(error.code, "widget_unavailable")
      XCTAssertEqual(error.status, 409)
      XCTAssertFalse(error.retryable)
      XCTAssertFalse(error.outcomeUnknown)
      XCTAssertFalse(String(describing: error).contains("provider-secret"))
      XCTAssertFalse(
        String(data: try JSONEncoder().encode(error), encoding: .utf8)!.contains("provider-secret"))
    }
    XCTAssertEqual(calls.all, [false])
    XCTAssertEqual(identityStub.requests.count, 1)

    let claimStub = Stub([
      .json(
        409,
        [
          "error": "widget_unavailable", "message": "provider-secret", "retryable": true,
        ])
    ])
    let claimClient = try claimStub.client { request in
      calls.record(request.forceRefresh)
      return "synthetic-token"
    }
    do {
      _ = try await claimClient.claimAnonymousConversation(widgetToken: "widget-token")
      XCTFail("Expected API-only widget refusal")
    } catch let error as DaykeeperError {
      XCTAssertEqual(error.code, "widget_unavailable")
      XCTAssertEqual(error.status, 409)
      XCTAssertFalse(error.retryable)
      XCTAssertFalse(error.outcomeUnknown)
      XCTAssertFalse(String(describing: error).contains("provider-secret"))
      XCTAssertFalse(
        String(data: try JSONEncoder().encode(error), encoding: .utf8)!.contains("provider-secret"))
    }
    XCTAssertEqual(calls.all, [false, false])
    XCTAssertEqual(claimStub.requests.count, 1)
  }

  func testExplicitReadDenialSurvivesMalformedErrorCodeAndRedactsRemoteText() async throws {
    for code: Any in ["private-server-secret", ["private": "server-secret"]] {
      let stub = Stub([
        .json(401, ["error": code, "retryable": false, "message": "private-server-secret"])
      ])
      do {
        _ = try await stub.client().listConversations()
        XCTFail("Expected rejection")
      } catch let error as DaykeeperError {
        XCTAssertEqual(error.code, "daykeeper_request_failed")
        XCTAssertFalse(error.retryable)
        XCTAssertFalse(String(describing: error).contains("private"))
        XCTAssertFalse(
          String(data: try JSONEncoder().encode(error), encoding: .utf8)!.contains("private"))
      }
      XCTAssertEqual(stub.requests.count, 1)
    }
  }

  func testCompletedLegacy401MayRefreshButBodyFailureCannot() async throws {
    let legacy = Stub([.response(401, Data("not-json".utf8)), .json(200, emptyList)])
    _ = try await legacy.client().listConversations()
    XCTAssertEqual(legacy.requests.count, 2)
    let large = Stub([.response(401, Data(repeating: 32, count: HTTPTransport.maximumBytes + 1))])
    do {
      _ = try await large.client().listConversations()
      XCTFail("Expected size rejection")
    } catch let error as DaykeeperError { XCTAssertEqual(error.code, "RESPONSE_TOO_LARGE") }
    XCTAssertEqual(large.requests.count, 1)
  }

  func testSuccessShapeAndConversationBindingAreCheckedAfterWrites() async throws {
    var foreign = message
    foreign["conversationId"] = 8
    for response in [
      Stub.Reply.json(201, ["message": foreign]), .response(201, Data("not-json".utf8)),
    ] {
      let stub = Stub([response])
      do {
        _ = try await stub.client().sendMessage(in: 7, content: "Hello")
        XCTFail("Expected invalid response")
      } catch let error as DaykeeperError {
        XCTAssertEqual(error.code, "INVALID_RESPONSE")
        XCTAssertTrue(error.outcomeUnknown)
        XCTAssertFalse(error.retryable)
      }
      XCTAssertEqual(stub.requests.count, 1)
    }
  }

  func testInvalidInputsAndTokensFailBeforeDispatch() async throws {
    let stub = Stub([])
    let client = try stub.client()
    for id in [Int64(0), -1, 9_007_199_254_740_992] {
      do {
        _ = try await client.listMessages(in: id)
        XCTFail("Expected invalid ID")
      } catch let error as DaykeeperError { XCTAssertEqual(error.code, "INVALID_CONFIGURATION") }
    }
    for content in [" \n", String(repeating: "😀", count: 8001)] {
      do {
        _ = try await client.sendMessage(in: 7, content: content)
        XCTFail("Expected invalid input")
      } catch let error as DaykeeperError { XCTAssertFalse(error.outcomeUnknown) }
    }
    for token in ["", "unsafe\r\nheader", "contains space", String(repeating: "x", count: 16385)] {
      let client = try stub.client { _ in token }
      do {
        _ = try await client.listConversations()
        XCTFail("Expected invalid token")
      } catch let error as DaykeeperError { XCTAssertEqual(error.code, "INVALID_CONFIGURATION") }
    }
    XCTAssertTrue(stub.requests.isEmpty)
  }

  func testProviderFailureIsSanitizedAndNotDispatched() async throws {
    struct PrivateFailure: Error {}
    let stub = Stub([])
    let client = try stub.client { _ in throw PrivateFailure() }
    do {
      _ = try await client.createConversation()
      XCTFail("Expected token failure")
    } catch let error as DaykeeperError {
      XCTAssertEqual(error.code, "TOKEN_PROVIDER_ERROR")
      XCTAssertFalse(error.outcomeUnknown)
      XCTAssertFalse(error.retryable)
    }
    XCTAssertTrue(stub.requests.isEmpty)
  }

  func testStalledWriteHasOneDeadlineAndUncertainOutcome() async throws {
    let stub = Stub([.stall])
    let client = try stub.client(timeout: 1)
    let start = Date()
    do {
      _ = try await client.createConversation()
      XCTFail("Expected timeout")
    } catch let error as DaykeeperError {
      XCTAssertEqual(error.code, "REQUEST_TIMEOUT")
      XCTAssertTrue(error.outcomeUnknown)
      XCTAssertFalse(error.retryable)
    }
    XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    XCTAssertEqual(stub.requests.count, 1)
  }

  /// Every error code the Daykeeper support gateway can put in the customer
  /// `{ "error": ... }` envelope, copied from `test/errorCodes.test.ts` in
  /// SkyPorch/daykeeper-react-native#14 so the three SDKs agree on exactly one
  /// projection rule. Consuming apps switch on these, so every one must arrive
  /// unchanged.
  private static let gatewayErrorCodes = [
    // auth.mjs — SupportAuthError, 401 unless noted
    "missing_bearer_token", "invalid_bearer_token", "invalid_token", "invalid_tenant",
    "unsupported_token", "invalid_signature", "invalid_issuer", "invalid_audience",
    "invalid_subject", "invalid_expiration", "expired_token", "token_lifetime_too_long",
    // server.mjs
    "unknown_tenant", "insufficient_scope", "erasure_targets_do_not_match_token",
    "unknown_campaign", "widget_token_required", "not_found", "support_upstream_rejected",
    "support_upstream_unavailable",
    // Codes the customer app still switches on from the pre-gateway support
    // stack and from services in front of the gateway.
    "support_gateway_request_failed", "conversation_not_found",
    "daykeeper_usage_limit_exceeded", "daykeeper_usage_not_enabled",
    "daykeeper_support_not_ready", "daykeeper_resource_conflict",
    "daykeeper_support_unavailable", "rate_limited", "widget_unavailable",
  ]

  func testEveryGatewayErrorCodeReachesTheCallerUnchanged() async throws {
    XCTAssertEqual(Self.gatewayErrorCodes.count, 29)
    XCTAssertEqual(Set(Self.gatewayErrorCodes).count, Self.gatewayErrorCodes.count)
    for code in Self.gatewayErrorCodes {
      let stub = Stub([.json(403, ["error": code])])
      do {
        _ = try await stub.client().getUnread()
        XCTFail("Expected \(code) to surface")
      } catch {
        XCTAssertEqual((error as? DaykeeperError)?.code, code)
      }
      XCTAssertTrue(DaykeeperError.isSafeCode(code), code)
    }
  }

  func testKnownSafeCodeSetRejectsTokenLikeAndUnknownValues() throws {
    for value in ["not_found", "widget_unavailable", "support_upstream_rejected"] {
      XCTAssertTrue(DaykeeperError.isSafeCode(value), value)
    }
    for value in [
      "abc", "ab", String(repeating: "a", count: 65), "", "Not_Found", "not-found", "not found",
      "sk_live_123", "support_brand_new_condition", "future_unknown_code", "not_found\n",
      "nöt_found",
    ] {
      XCTAssertFalse(DaykeeperError.isSafeCode(value), value)
    }
  }

  func testUnknownAndTokenLikeRemoteCodesCollapseWithoutLeakage() async throws {
    for code in ["support_brand_new_condition", "future_unknown_code", "sk_live_123"] {
      let stub = Stub([.json(400, ["error": code])])
      do {
        _ = try await stub.client().getUnread()
        XCTFail("Expected \(code) to be rejected")
      } catch {
        XCTAssertEqual((error as? DaykeeperError)?.code, "daykeeper_request_failed")
        XCTAssertFalse(String(describing: error).contains(code))
      }
    }
  }

  func testProseAndNonStringErrorValuesCollapse() async throws {
    // server.mjs answers some 4xx failures with `error: <Error.message>` rather
    // than a code. Those are English sentences and never reach the caller, and
    // neither does a value that is not a JSON string at all.
    let values: [Any] = [
      "Payload too large", "Invalid JSON", "At least one erasure target is required",
      "At most 100 erasure targets are allowed", "Each erasure target needs a userId or email",
      "Message content is required", "Conversation not found",
      ["support_upstream_rejected"], ["code": "support_upstream_rejected"], 42, true,
      NSNull(),
    ]
    for value in values {
      let stub = Stub([.json(400, ["error": value])])
      do {
        _ = try await stub.client().getUnread()
        XCTFail("Expected a rejection")
      } catch {
        XCTAssertEqual((error as? DaykeeperError)?.code, "daykeeper_request_failed")
      }
    }
  }

  func testTheContractMessageFieldNeverBecomesTheErrorMessage() async throws {
    let prose = "You have used your included conversations for August."
    let stub = Stub([
      .json(
        429,
        [
          "error": "daykeeper_usage_limit_exceeded", "message": prose, "retryable": false,
          "nextAction": "review_usage",
        ])
    ])
    do {
      _ = try await stub.client().getUnread()
      XCTFail("Expected a rejection")
    } catch {
      let safe = try XCTUnwrap(error as? DaykeeperError)
      XCTAssertEqual(safe.code, "daykeeper_usage_limit_exceeded")
      XCTAssertEqual(safe.description, "daykeeper_usage_limit_exceeded")
      // Honor an explicit server veto: a 429 is not automatically retryable
      // when the server says not to replay it.
      XCTAssertFalse(safe.retryable)
      XCTAssertEqual(safe.nextAction, .reviewUsage)
      let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(safe), encoding: .utf8))
      XCTAssertFalse(encoded.contains("August"))
    }
  }

  func testNextActionIsProjectedThroughAClosedAllowlist() async throws {
    for (raw, expected) in [
      ("review_usage", DaykeeperNextAction.reviewUsage),
      ("review_setup", .reviewSetup),
      ("refresh_conversation", .refreshConversation),
    ] {
      let stub = Stub([.json(429, ["error": "daykeeper_usage_limit_exceeded", "nextAction": raw])])
      do {
        _ = try await stub.client().getUnread()
        XCTFail("Expected a rejection")
      } catch {
        XCTAssertEqual((error as? DaykeeperError)?.nextAction, expected)
      }
    }
  }

  func testAnUnrecognizedOrAbsentNextActionIsDropped() async throws {
    // Unlike a code, a next action is an instruction the app acts on, so the
    // vocabulary stays closed: an unknown hint is dropped, not surfaced.
    let values: [Any] = [
      "review_billing", "contact_support", "Review_Usage", "review usage", "",
      ["review_usage"], 42, true, NSNull(),
    ]
    for value in values {
      let stub = Stub([
        .json(429, ["error": "daykeeper_usage_limit_exceeded", "nextAction": value])
      ])
      do {
        _ = try await stub.client().getUnread()
        XCTFail("Expected a rejection")
      } catch {
        let safe = try XCTUnwrap(error as? DaykeeperError)
        XCTAssertNil(safe.nextAction)
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(safe), encoding: .utf8))
        XCTAssertFalse(encoded.contains("nextAction"))
        XCTAssertFalse(encoded.contains("review_billing"))
      }
    }
    let absent = Stub([.json(404, ["error": "not_found"])])
    do {
      _ = try await absent.client().getUnread()
      XCTFail("Expected a rejection")
    } catch {
      let safe = try XCTUnwrap(error as? DaykeeperError)
      XCTAssertNil(safe.nextAction)
      let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(safe), encoding: .utf8))
      XCTAssertFalse(encoded.contains("nextAction"))
    }
  }
}
