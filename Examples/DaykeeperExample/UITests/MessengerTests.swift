import XCTest

final class MessengerTests: XCTestCase {
  private var app: XCUIApplication!
  private var key = ""
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor private func launch(_ mode: String, dark: Bool = false, large: Bool = false) throws {
    let origin = try XCTUnwrap(ProcessInfo.processInfo.environment["DAYKEEPER_TEST_ORIGIN"])
    let url = try XCTUnwrap(URL(string: origin))
    XCTAssertEqual(url.host, "127.0.0.1")
    XCTAssertEqual(url.scheme, "http")
    key = "\(mode)-\(UUID().uuidString.lowercased())"
    app = XCUIApplication()
    app.launchEnvironment = [
      "DAYKEEPER_EXAMPLE_URL": "\(origin)/cases/\(key)",
      "DAYKEEPER_EXAMPLE_DARK": dark ? "1" : "0",
      "DAYKEEPER_EXAMPLE_LARGE_TEXT": large ? "1" : "0",
      "DAYKEEPER_EXAMPLE_MANUAL_START": "1",
    ]
    app.launch()
    let start = app.buttons["example.start-fixture"]
    XCTAssertTrue(start.waitForExistence(timeout: 15))
    start.tap()
    let readyID = mode.hasPrefix("new") ? "daykeeper.new-conversation" : "daykeeper.conversation.7"
    XCTAssertTrue(app.buttons[readyID].waitForExistence(timeout: 15))
  }

  @MainActor private func openConversation() {
    app.buttons["daykeeper.conversation.7"].tap()
    XCTAssertTrue(app.textViews["daykeeper.message"].waitForExistence(timeout: 10))
  }

  @MainActor private func snapshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor private func enterMessage(_ content: String) {
    let input = app.textViews["daykeeper.message"]
    input.tap()
    // A newly created simulator may show the system keyboard introduction.
    if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
    input.typeText(content)
  }

  @MainActor private func confirmAlert(_ title: String, action: String) {
    let alert = app.alerts[title]
    XCTAssertTrue(alert.waitForExistence(timeout: 10))
    let button = alert.buttons[action]
    XCTAssertTrue(button.waitForExistence(timeout: 5))
    button.tap()
  }

  @MainActor private func counters() async throws -> [String: Int] {
    let origin = try XCTUnwrap(ProcessInfo.processInfo.environment["DAYKEEPER_TEST_ORIGIN"])
    let url = try XCTUnwrap(URL(string: "\(origin)/fixture/receipt?case=\(key)"))
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    let (data, _) = try await session.data(from: url)
    let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    return result.compactMapValues { $0 as? Int }
  }

  @MainActor func testFirstExchangeRefreshAndSignOut() async throws {
    try launch("ui")
    defer { app.terminate() }
    snapshot("conversations-light")
    openConversation()
    XCTAssertTrue(app.staticTexts["Hello from support for customer a"].exists)
    app.buttons["daykeeper.mark-read"].tap()
    app.buttons["daykeeper.conversations"].tap()
    XCTAssertTrue(app.buttons["daykeeper.conversation.7"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["1 unread"].exists)
    XCTAssertTrue(app.staticTexts["open"].exists)
    snapshot("after-seen-light")
    openConversation()
    enterMessage("Can you help with my account?")
    app.buttons["daykeeper.send"].tap()
    XCTAssertTrue(app.staticTexts["Can you help with my account?"].waitForExistence(timeout: 10))
    app.buttons["daykeeper.refresh"].tap()
    XCTAssertTrue(app.staticTexts["Can you help with my account?"].waitForExistence(timeout: 10))
    snapshot("conversation-light")
    let receipt = try await counters()
    XCTAssertEqual(receipt["sends"], 1)
    XCTAssertEqual(receipt["seen"], 1)
    app.buttons["example.sign-out"].tap()
    XCTAssertTrue(
      app.staticTexts["Sign in to your app to use support."].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Can you help with my account?"].exists)
  }

  @MainActor func testQuotaPreservesDraftAndHistoryInDarkMode() async throws {
    try launch("quota", dark: true)
    defer { app.terminate() }
    openConversation()
    let input = app.textViews["daykeeper.message"]
    enterMessage("Keep this draft")
    app.buttons["daykeeper.send"].tap()
    XCTAssertTrue(app.staticTexts["daykeeper.error"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["daykeeper.error"].label.contains("current allowance"))
    XCTAssertEqual(input.value as? String, "Keep this draft")
    XCTAssertTrue(app.staticTexts["Hello from support for customer a"].exists)
    snapshot("quota-dark")
    let receipt = try await counters()
    XCTAssertEqual(receipt["sends"], 1)
  }

  @MainActor func testUncertainAcceptedWriteRequiresReviewWithoutResend() async throws {
    try launch("accepted500")
    defer { app.terminate() }
    openConversation()
    let input = app.textViews["daykeeper.message"]
    enterMessage("Confirm this once")
    app.buttons["daykeeper.send"].tap()
    XCTAssertTrue(app.buttons["Discard draft after review"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["daykeeper.send"].isEnabled)
    XCTAssertFalse(app.buttons["Discard draft after review"].isEnabled)
    snapshot("uncertain-message-before-refresh")
    app.buttons["daykeeper.refresh"].tap()
    XCTAssertTrue(app.staticTexts["Confirm this once"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["Discard draft after review"].isEnabled)
    snapshot("uncertain-message-after-refresh")
    app.buttons["Discard draft after review"].tap()
    confirmAlert("Discard this draft?", action: "Discard draft")
    XCTAssertEqual(input.value as? String, "")
    XCTAssertFalse(app.buttons["daykeeper.send"].isEnabled)
    let receipt = try await counters()
    XCTAssertEqual(receipt["sends"], 1)
  }

  @MainActor func testBackgroundAndCustomerSwitchDoNotRestoreOtherCustomerData() throws {
    try launch("ui", dark: true, large: true)
    defer { app.terminate() }
    openConversation()
    let input = app.textViews["daykeeper.message"]
    enterMessage("Private draft for a")
    // This test runner is bound to its newly created simulator, never a user's device.
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(input.waitForExistence(timeout: 10))
    XCTAssertEqual(input.value as? String, "Private draft for a")
    snapshot("large-text-dark")
    app.buttons["example.switch"].tap()
    XCTAssertTrue(app.buttons["daykeeper.conversation.7"].waitForExistence(timeout: 10))
    openConversation()
    XCTAssertTrue(app.staticTexts["Hello from support for customer b"].exists)
    XCTAssertFalse(app.staticTexts["Hello from support for customer a"].exists)
    XCTAssertEqual(app.textViews["daykeeper.message"].value as? String, "")
  }

  @MainActor func testCreateFirstConversationAndSend() async throws {
    try launch("newui")
    defer { app.terminate() }
    XCTAssertTrue(app.staticTexts["No conversations yet."].waitForExistence(timeout: 10))
    app.buttons["daykeeper.new-conversation"].tap()
    XCTAssertTrue(app.textViews["daykeeper.message"].waitForExistence(timeout: 10))
    enterMessage("My first support message")
    app.buttons["daykeeper.send"].tap()
    XCTAssertTrue(app.staticTexts["My first support message"].waitForExistence(timeout: 10))
    app.buttons["daykeeper.refresh"].tap()
    XCTAssertTrue(app.staticTexts["My first support message"].waitForExistence(timeout: 10))
    let receipt = try await counters()
    XCTAssertEqual(receipt["creates"], 1)
    XCTAssertEqual(receipt["sends"], 1)
  }

  @MainActor func testUncertainCreationCanBeReviewedWithoutRepeatingIt() async throws {
    try launch("newcreation500")
    defer { app.terminate() }
    XCTAssertTrue(app.staticTexts["No conversations yet."].waitForExistence(timeout: 10))
    app.buttons["daykeeper.new-conversation"].tap()
    XCTAssertTrue(app.buttons["Finish reviewing conversations"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["daykeeper.new-conversation"].isEnabled)
    XCTAssertFalse(app.buttons["Finish reviewing conversations"].isEnabled)
    snapshot("uncertain-creation-before-refresh")
    app.buttons["daykeeper.refresh"].tap()
    XCTAssertTrue(app.buttons["daykeeper.conversation.7"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["Finish reviewing conversations"].isEnabled)
    snapshot("uncertain-creation-after-refresh")
    app.buttons["Finish reviewing conversations"].tap()
    confirmAlert("Finished reviewing conversations?", action: "I have reviewed the list")
    XCTAssertTrue(app.buttons["daykeeper.new-conversation"].isEnabled)
    let receipt = try await counters()
    XCTAssertEqual(receipt["creates"], 1)
  }
}
