import XCTest

@testable import Daykeeper

private actor TokenGate {
  private var continuation: CheckedContinuation<String, Never>?
  private(set) var started = false
  func wait() async -> String {
    started = true
    return await withCheckedContinuation { continuation = $0 }
  }
  func release() {
    continuation?.resume(returning: "synthetic-token")
    continuation = nil
  }
}

final class CancellationTests: XCTestCase {
  func testDeadlineDoesNotWaitForUncooperativeCredentialProvider() async throws {
    let gate = TokenGate()
    let client = try DaykeeperClient(
      baseURL: URL(string: "https://never-dispatch.example.test")!, timeout: 1
    ) { _ in await gate.wait() }
    let began = Date()
    do {
      _ = try await client.createConversation()
      XCTFail("Expected timeout")
    } catch let error as DaykeeperError {
      XCTAssertEqual(error.code, "REQUEST_TIMEOUT")
      XCTAssertFalse(error.outcomeUnknown)
    }
    XCTAssertLessThan(Date().timeIntervalSince(began), 3)
    await gate.release()
  }

  func testCancellationDoesNotWaitForLateCredentialAndPreservesNoDispatch() async throws {
    let gate = TokenGate()
    let client = try DaykeeperClient(baseURL: URL(string: "https://never-dispatch.example.test")!) {
      _ in await gate.wait()
    }
    let task = Task { try await client.createConversation() }
    for _ in 0..<100 {
      if await gate.started { break }
      try await Task.sleep(nanoseconds: 1_000_000)
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
  }

  func testAlreadyCancelledLifetimeDoesNotInvokeWork() async throws {
    let gate = TokenGate()
    let task = Task {
      _ = await gate.wait()
      return try await RequestLifetime<Int>.run(seconds: 1) {
        XCTFail("Canceled request must not start work")
        return 42
      }
    }
    for _ in 0..<100 {
      if await gate.started { break }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    task.cancel()
    await gate.release()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch let error as DaykeeperError { XCTAssertEqual(error.code, "REQUEST_ABORTED") }
  }
}
