import Daykeeper
import XCTest

@testable import DaykeeperUI

private actor CustomerFixture: CustomerAPI {
  static let conversationJSON =
    #"{"id":7,"status":"open","createdAt":null,"updatedAt":123,"unreadCount":0,"unreadForContact":1,"lastSeenAt":null,"preview":"Hello"}"#
  static let messageJSON =
    #"{"id":9,"conversationId":7,"content":"Hello","contentType":"text","contentAttributes":{},"messageType":0,"createdAt":123,"sender":null,"attachments":[]}"#
  private(set) var sends = 0
  private(set) var creates = 0
  private var rejected = false
  private var sendContinuation: CheckedContinuation<DaykeeperMessageResult, Never>?
  private var createContinuation: CheckedContinuation<DaykeeperConversationResult, Never>?
  func listConversations() async throws -> DaykeeperConversationList {
    if rejected {
      let error: DaykeeperError = try decode(
        #"{"code":"daykeeper_request_failed","status":403,"retryable":false,"outcomeUnknown":false}"#
      )
      throw error
    }
    return try decode(
      "{\"conversations\":[\(Self.conversationJSON)],\"widgetConversationId\":null}")
  }
  func revoke() { rejected = true }
  func listMessages(in conversationID: Int64, after: Int64?) async throws -> DaykeeperMessageList {
    try decode("{\"messages\":[]}")
  }
  func createConversation() async throws -> DaykeeperConversationResult {
    creates += 1
    return await withCheckedContinuation { createContinuation = $0 }
  }
  func sendMessage(in conversationID: Int64, content: String) async throws -> DaykeeperMessageResult
  {
    sends += 1
    return await withCheckedContinuation { sendContinuation = $0 }
  }
  func markConversationSeen(_ conversationID: Int64) async throws -> DaykeeperSeenResult {
    try decode(#"{"conversationId":7,"seen":true,"seenAt":123}"#)
  }
  func finishSend() throws {
    sendContinuation?.resume(returning: try decode("{\"message\":\(Self.messageJSON)}"))
    sendContinuation = nil
  }
  func finishCreate() throws {
    createContinuation?.resume(returning: try decode("{\"conversation\":\(Self.conversationJSON)}"))
    createContinuation = nil
  }
  private func decode<T: Decodable>(_ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
  }
}

final class SessionTests: XCTestCase {
  @MainActor func testResetDropsClientAndCustomerPresentation() throws {
    let client = try DaykeeperClient(baseURL: URL(string: "https://example.test")!) { _ in
      "synthetic-token"
    }
    let session = DaykeeperMessengerSession(client: client)
    session.draft = "private draft"
    session.reset()
    XCTAssertTrue(session.isSignedOut)
    XCTAssertTrue(session.draft.isEmpty)
    XCTAssertTrue(session.messages.isEmpty)
    XCTAssertFalse(session.canSend)
  }

  @MainActor func testAcceptedLateSendCannotRestoreIdentityAfterReset() async throws {
    let api = CustomerFixture()
    let active = DaykeeperMessengerSession(customerAPI: api)
    await active.refresh()
    await active.selectConversation(7)
    active.draft = "private pending message"
    let sending = Task { await active.sendMessage() }
    for _ in 0..<100 {
      if await api.sends == 1 { break }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    let sends = await api.sends
    XCTAssertEqual(sends, 1)
    active.reset()
    try await api.finishSend()
    await sending.value
    XCTAssertTrue(active.isSignedOut)
    XCTAssertTrue(active.messages.isEmpty)
    XCTAssertTrue(active.draft.isEmpty)
  }

  @MainActor func testBackgroundingPendingSendPreservesDraftAndRequiresExplicitRecovery()
    async throws
  {
    let api = CustomerFixture()
    let active = DaykeeperMessengerSession(customerAPI: api)
    await active.refresh()
    await active.selectConversation(7)
    active.draft = "preserved message"
    let sending = Task { await active.sendMessage() }
    for _ in 0..<100 {
      if await api.sends == 1 { break }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    active.suspend()
    active.suspend()
    XCTAssertTrue(active.messages.isEmpty)
    XCTAssertTrue(active.draft.isEmpty)
    try await api.finishSend()
    await sending.value
    await active.resume()
    XCTAssertEqual(active.draft, "preserved message")
    XCTAssertFalse(active.canSend)
    await active.sendMessage()
    let sends = await api.sends
    XCTAssertEqual(sends, 1)
    active.discardUncertainDraft()
    XCTAssertTrue(active.draft.isEmpty)
    XCTAssertFalse(active.uncertainThreads.contains(7))
  }

  @MainActor func testDoubleCreateAndBackgroundRecoveryCannotCreateDuplicate() async throws {
    let api = CustomerFixture()
    let active = DaykeeperMessengerSession(customerAPI: api)
    let creating = Task { await active.createConversation() }
    for _ in 0..<100 {
      if await api.creates == 1 { break }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    await active.createConversation()
    active.suspend()
    try await api.finishCreate()
    await creating.value
    await active.resume()
    await active.createConversation()
    let creates = await api.creates
    XCTAssertEqual(creates, 1)
    XCTAssertTrue(active.uncertainCreation)
    active.acknowledgeUncertainCreationAfterReview()
    XCTAssertFalse(active.uncertainCreation)
    let afterReview = await api.creates
    XCTAssertEqual(afterReview, 1, "Acknowledgement must not perform a write")
  }

  @MainActor func testAuthenticationRejectionClearsLoadedCustomerData() async throws {
    let api = CustomerFixture()
    let active = DaykeeperMessengerSession(customerAPI: api)
    await active.refresh()
    await active.selectConversation(7)
    active.draft = "Private draft"
    await api.revoke()
    await active.refresh()
    XCTAssertTrue(active.isSignedOut)
    XCTAssertTrue(active.conversations.isEmpty)
    XCTAssertTrue(active.messages.isEmpty)
    XCTAssertTrue(active.draft.isEmpty)
    XCTAssertNil(active.selectedConversationID)
  }
}
