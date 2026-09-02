import XCTest

@testable import Daykeeper

final class ConfigurationTests: XCTestCase {
  func testRejectsUnsafeEndpointsAndTimeouts() throws {
    for value in [
      "http://example.test", "https://user:secret@example.test",
      "https://example.test?token=secret", "https://example.test#token",
    ] {
      XCTAssertThrowsError(try DaykeeperClient(baseURL: URL(string: value)!) { _ in "token" })
    }
    for timeout in [0, 0.5, 61, .infinity, .nan] {
      XCTAssertThrowsError(
        try DaykeeperClient(baseURL: URL(string: "https://example.test")!, timeout: timeout) { _ in
          "token"
        })
    }
    _ = try DaykeeperClient(baseURL: URL(string: "https://example.test/support-api")!) { _ in
      "token"
    }
  }

  /// Plain HTTP to a developer's own loopback fixture is a debug convenience.
  /// A release build must refuse it like any other unencrypted base URL.
  func testPlainLoopbackIsAcceptedOnlyInDebugBuilds() throws {
    for value in ["http://127.0.0.1:8080", "http://localhost:8080", "http://[::1]:8080"] {
      let url = URL(string: value)!
      #if DEBUG
        _ = try DaykeeperClient(baseURL: url) { _ in "token" }
      #else
        XCTAssertThrowsError(try DaykeeperClient(baseURL: url) { _ in "token" })
      #endif
    }
    // Never allowed in any configuration: plain HTTP to a routable host.
    XCTAssertThrowsError(
      try DaykeeperClient(baseURL: URL(string: "http://127.0.0.2:8080")!) { _ in "token" })
  }
}
