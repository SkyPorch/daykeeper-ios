import XCTest

@testable import Daykeeper

/// Requires the dedicated loopback fixture. CI runs these separately with its
/// exact fresh port. A plain `swift test` starts the same node harness itself
/// when node is available, and otherwise skips with a pointer to the script;
/// nothing here ever contacts a remote gateway.
final class WireTests: XCTestCase {
  private actor Gate {
    var started = false
    var finished = false
    var continuation: CheckedContinuation<String, Never>?
    func token() async -> String {
      started = true
      let value = await withCheckedContinuation { continuation = $0 }
      finished = true
      return value
    }
    func release() {
      continuation?.resume(returning: "fixture-a")
      continuation = nil
    }
  }
  private struct Receipt: Decodable {
    let hits: Int
    let sinkHits: Int
    let cookies: [Bool]
    let methods: [String]
  }
  override class func tearDown() {
    WireFixture.stop()
    super.tearDown()
  }
  private func origin() throws -> URL { try WireFixture.origin() }
  private func caseURL(_ mode: String) throws -> (URL, String) {
    let key = "\(mode)-\(UUID().uuidString.lowercased())"
    return (try origin().appendingPathComponent("cases/\(key)"), key)
  }
  private func receipt(_ key: String) async throws -> Receipt {
    var components = URLComponents(
      url: try origin().appendingPathComponent("fixture/receipt"), resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "case", value: key)]
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    let (data, _) = try await session.data(from: components.url!)
    return try JSONDecoder().decode(Receipt.self, from: data)
  }
  func testForcedRefreshIdentityReadIgnoresANonRetryableExpiredTokenHint() async throws {
    let (url, _) = try caseURL("freshonly")
    let client = try DaykeeperClient(baseURL: url) { request in
      request.forceRefresh ? "fixture-refreshed" : "fixture-a"
    }
    // The ordinary read obeys the gateway and does not refresh: the hint said no.
    do {
      _ = try await client.getIdentity()
      XCTFail("Expected the suppressed retry to surface the rejection")
    } catch {
      XCTAssertEqual((error as? DaykeeperError)?.status, 401)
    }
    // The recovery read asks for a fresh credential whatever the hint said, which
    // is what lets the messenger tell an expired token from a revoked customer.
    let identity = try await client.getIdentityWithFreshToken()
    XCTAssertEqual(identity.subject, "customer-a")
    XCTAssertEqual(identity.identifier, "customer-a")
  }

  func testMessageCursorReachesTheGatewayAndReturnsOnlyNewerMessages() async throws {
    let (url, _) = try caseURL("cursor")
    let client = try DaykeeperClient(baseURL: url) { _ in "fixture-a" }
    let first = try await client.listMessages(in: 7)
    XCTAssertEqual(first.messages.map(\.id), [9])
    let sent = try await client.sendMessage(in: 7, content: "Second")
    let newer = try await client.listMessages(in: 7, after: 9)
    XCTAssertEqual(newer.messages.map(\.id), [sent.message.id])
    let repeated = try await client.listMessages(in: 7, after: sent.message.id)
    XCTAssertTrue(repeated.messages.isEmpty, "A caught-up cursor must return nothing")
    let full = try await client.listMessages(in: 7)
    XCTAssertEqual(full.messages.count, 2)
  }

  func testRedirectTargetsAreNeverReachedIncluding307And308() async throws {
    for status in [301, 302, 303, 307, 308] {
      let (url, key) = try caseURL("redirect\(status)")
      let client = try DaykeeperClient(baseURL: url) { _ in "fixture-a" }
      do {
        _ = try await client.listConversations()
        XCTFail("Expected redirect rejection")
      } catch let error as DaykeeperError { XCTAssertEqual(error.code, "REDIRECT_REJECTED") }
      let before = try await receipt(key)
      XCTAssertEqual(before.hits, 1)
      XCTAssertEqual(before.sinkHits, 0)
      // Positive control: the same target is reachable and the default private
      // URLSession really follows this redirect. No shared/system session used.
      let control = URLSession(configuration: .ephemeral)
      defer { control.invalidateAndCancel() }
      _ = try await control.data(from: url.appendingPathComponent("v1/conversations"))
      let after = try await receipt(key)
      XCTAssertEqual(after.sinkHits, 1)
    }
  }
  func testSetCookieDoesNotCarryAcrossSDKCalls() async throws {
    let (url, key) = try caseURL("cookie")
    let client = try DaykeeperClient(baseURL: url) { _ in "fixture-a" }
    _ = try await client.listConversations()
    _ = try await client.listConversations()
    let sdk = try await receipt(key)
    XCTAssertEqual(sdk.cookies, [false, false])
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieAcceptPolicy = .always
    let control = URLSession(configuration: config)
    defer { control.invalidateAndCancel() }
    _ = try await control.data(from: url.appendingPathComponent("v1/conversations"))
    _ = try await control.data(from: url.appendingPathComponent("v1/conversations"))
    let after = try await receipt(key)
    XCTAssertEqual(Array(after.cookies.suffix(2)), [false, true])
  }
  func testCacheCannotCrossCustomerClientsWithPositiveCacheControl() async throws {
    let (url, key) = try caseURL("cache")
    let a = try DaykeeperClient(baseURL: url) { _ in "fixture-a" }
    let b = try DaykeeperClient(baseURL: url) { _ in "fixture-b" }
    let first = try await a.listConversations()
    let second = try await b.listConversations()
    XCTAssertTrue(first.conversations[0].preview!.hasSuffix("a"))
    XCTAssertTrue(second.conversations[0].preview!.hasSuffix("b"))
    let sdk = try await receipt(key)
    XCTAssertEqual(sdk.hits, 2)
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = URLCache(memoryCapacity: 1_048_576, diskCapacity: 0, diskPath: nil)
    let control = URLSession(configuration: config)
    defer { control.invalidateAndCancel() }
    _ = try await control.data(from: url.appendingPathComponent("v1/conversations"))
    _ = try await control.data(from: url.appendingPathComponent("v1/conversations"))
    let after = try await receipt(key)
    XCTAssertEqual(after.hits, 3, "Positive control must actually use its private HTTP cache")
  }
  func testReadsRefreshOnceButWritesDoNotReplay() async throws {
    let (url, key) = try caseURL("read401")
    let client = try DaykeeperClient(baseURL: url) { _ in "fixture-a" }
    _ = try await client.listConversations()
    let reads = try await receipt(key)
    XCTAssertEqual(reads.hits, 2)
    for mode in ["deny401", "write401", "write500"] {
      let (url, key) = try caseURL(mode)
      let client = try DaykeeperClient(baseURL: url) { _ in "fixture-a" }
      do {
        if mode == "deny401" {
          _ = try await client.listConversations()
        } else {
          _ = try await client.createConversation()
        }
        XCTFail("Expected failure")
      } catch let error as DaykeeperError {
        XCTAssertFalse(error.retryable)
        XCTAssertEqual(error.outcomeUnknown, mode == "write500")
      }
      let result = try await receipt(key)
      XCTAssertEqual(result.hits, 1)
    }
  }
  func testStreamLimitsAndStallsAreBounded() async throws {
    for mode in ["large", "stallheaders", "stallbody"] {
      let (url, key) = try caseURL(mode)
      let client = try DaykeeperClient(baseURL: url, timeout: 1) { _ in "fixture-a" }
      let began = Date()
      do {
        _ = try await client.createConversation()
        XCTFail("Expected boundary failure")
      } catch let error as DaykeeperError {
        XCTAssertTrue(error.outcomeUnknown)
        XCTAssertFalse(error.retryable)
        XCTAssertEqual(error.code, mode == "large" ? "RESPONSE_TOO_LARGE" : "REQUEST_TIMEOUT")
      }
      XCTAssertLessThan(Date().timeIntervalSince(began), 3)
      let result = try await receipt(key)
      XCTAssertEqual(result.hits, 1)
    }
  }

  func testLateCredentialAfterCancellationNeverReachesTheWire() async throws {
    let (url, key) = try caseURL("cancelcredential")
    let gate = Gate()
    let client = try DaykeeperClient(baseURL: url) { _ in await gate.token() }
    let task = Task { try await client.createConversation() }
    for _ in 0..<200 {
      if await gate.started { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let started = await gate.started
    XCTAssertTrue(started)
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch let error as DaykeeperError {
      XCTAssertEqual(error.code, "REQUEST_ABORTED")
      XCTAssertFalse(error.outcomeUnknown)
    }
    await gate.release()
    for _ in 0..<200 {
      if await gate.finished { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let finished = await gate.finished
    XCTAssertTrue(finished)
    try await Task.sleep(nanoseconds: 100_000_000)
    let result = try await receipt(key)
    XCTAssertEqual(result.hits, 0)
  }

  func testCancellationAfterDispatchKeepsWriteOutcomeUnknown() async throws {
    let (url, key) = try caseURL("stallbody")
    let client = try DaykeeperClient(baseURL: url) { _ in "fixture-a" }
    let task = Task { try await client.sendMessage(in: 7, content: "Synthetic message") }
    for _ in 0..<200 {
      if try await receipt(key).hits == 1 { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let dispatched = try await receipt(key)
    XCTAssertEqual(dispatched.hits, 1)
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch let error as DaykeeperError {
      XCTAssertEqual(error.code, "REQUEST_ABORTED")
      XCTAssertTrue(error.outcomeUnknown)
      XCTAssertFalse(error.retryable)
    }
    let result = try await receipt(key)
    XCTAssertEqual(result.hits, 1)
  }

  func testAllFourWriteOperationsRefuseRefreshAndReplay() async throws {
    for method in ["create", "send", "seen", "claim"] {
      let (url, key) = try caseURL("write401")
      let client = try DaykeeperClient(baseURL: url) { hint in
        XCTAssertFalse(hint.forceRefresh)
        return "fixture-a"
      }
      do {
        switch method {
        case "create": _ = try await client.createConversation()
        case "send": _ = try await client.sendMessage(in: 7, content: "Synthetic message")
        case "seen": _ = try await client.markConversationSeen(7)
        default: _ = try await client.claimAnonymousConversation(widgetToken: "fixture-widget")
        }
        XCTFail("Expected rejection")
      } catch let error as DaykeeperError {
        XCTAssertEqual(error.status, 401)
        XCTAssertFalse(error.retryable)
      }
      let result = try await receipt(key)
      XCTAssertEqual(result.hits, 1)
      XCTAssertEqual(result.methods, ["POST"])
    }
  }
}

/// `swift test` on its own still exercises the real URLSession stack: if the
/// node harness is present the loopback fixture is started here, and if it is
/// not the wire tests skip with an explicit pointer to Scripts/check-wire.mjs.
/// CI keeps passing DAYKEEPER_TEST_ORIGIN, which always wins.
internal enum WireFixture {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var process: Process?
  nonisolated(unsafe) private static var resolved: Result<URL, Error>?

  static func origin() throws -> URL {
    if let value = ProcessInfo.processInfo.environment["DAYKEEPER_TEST_ORIGIN"] {
      return try validate(value)
    }
    lock.lock()
    defer { lock.unlock() }
    if let resolved { return try resolved.get() }
    let outcome: Result<URL, Error>
    do { outcome = .success(try launch()) } catch { outcome = .failure(error) }
    resolved = outcome
    return try outcome.get()
  }

  static func stop() {
    lock.lock()
    defer { lock.unlock() }
    if let process, process.isRunning { process.terminate() }
    process = nil
    resolved = nil
  }

  private static func validate(_ value: String) throws -> URL {
    guard let url = URL(string: value), url.scheme == "http", url.host == "127.0.0.1",
      url.port != nil,
      url.path.isEmpty, url.query == nil, url.fragment == nil, url.user == nil, url.password == nil
    else {
      throw NSError(domain: "Invalid isolated fixture", code: 1)
    }
    return url
  }

  private static func launch() throws -> URL {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let harness = root.appendingPathComponent("Tests/Fixtures/server.mjs")
    guard FileManager.default.fileExists(atPath: harness.path) else {
      throw XCTSkip(
        "Wire tests need Tests/Fixtures/server.mjs; run node Scripts/check-wire.mjs instead")
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = ["node", harness.path]
    task.currentDirectoryURL = root
    let pipe = Pipe()
    task.standardOutput = pipe
    do {
      try task.run()
    } catch {
      throw XCTSkip(
        "Wire tests need node on PATH to start Tests/Fixtures/server.mjs; "
          + "run node Scripts/check-wire.mjs instead")
    }
    process = task
    var buffer = Data()
    let deadline = Date().addingTimeInterval(60)
    while !buffer.contains(UInt8(ascii: "\n")), Date() < deadline {
      let chunk = pipe.fileHandleForReading.availableData
      if chunk.isEmpty { break }
      buffer.append(chunk)
    }
    guard let newline = buffer.firstIndex(of: UInt8(ascii: "\n")),
      let line = String(data: buffer[..<newline], encoding: .utf8),
      let payload = try? JSONDecoder().decode([String: String].self, from: Data(line.utf8)),
      let value = payload["origin"]
    else {
      if task.isRunning { task.terminate() }
      process = nil
      throw XCTSkip(
        "Tests/Fixtures/server.mjs did not report a loopback origin; "
          + "run node Scripts/check-wire.mjs instead")
    }
    return try validate(value)
  }
}
