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
}
