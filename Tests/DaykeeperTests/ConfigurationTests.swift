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
}
