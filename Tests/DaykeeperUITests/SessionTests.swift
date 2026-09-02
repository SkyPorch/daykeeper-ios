import Daykeeper
import XCTest

@testable import DaykeeperUI

private actor CustomerFixture: CustomerAPI {
  static let conversationJSON =
    #"{"id":7,"status":"open","createdAt":null,"updatedAt":123,"unreadCount":0,"unreadForContact":1,"lastSeenAt":null,"preview":"Hello"}"#
  static let messageJSON =
    #"{"id":9,"conversationId":7,"content":"Hello","contentType":"text","contentAttributes":{},"messageType":0,"createdAt":123,"sender":null,"attachments":[]}"#
  static let identityJSON =
    #"{"baseUrl":"https://example.test","websiteToken":"synthetic","subject":"synthetic","identifier":"synthetic","identifierHash":"synthetic","email":null,"name":"Synthetic"}"#
  private(set) var sends = 0
  private(set) var creates = 0
  private(set) var identityReads = 0
  private(set) var cursors: [Int64?] = []
  private var identityRejected = false
  private var writeAuthStatus: Int?
  private var history: [Int64] = []
  private var baseListTooLarge = false
  private var rejected = false
  private var seen = false
  private let unreadAfterSeen: Int
  private let uncertainWrites: Bool
  private var listFailure = false
  private var historyFailure = false
  init(unreadAfterSeen: Int = 0, uncertainWrites: Bool = false) {
    self.unreadAfterSeen = unreadAfterSeen
    self.uncertainWrites = uncertainWrites
  }
  private var sendContinuation: CheckedContinuation<DaykeeperMessageResult, Never>?
  private var createContinuation: CheckedContinuation<DaykeeperConversationResult, Never>?
  func listConversations() async throws -> DaykeeperConversationList {
    if listFailure { throw try failure() }
    if rejected {
      let error: DaykeeperError = try decode(
        #"{"code":"daykeeper_request_failed","status":403,"retryable":false,"outcomeUnknown":false}"#
      )
      throw error
    }
    let conversation =
      seen
      ? Self.conversationJSON.replacingOccurrences(
        of: "\"unreadForContact\":1", with: "\"unreadForContact\":\(unreadAfterSeen)")
      : Self.conversationJSON
    return try decode("{\"conversations\":[\(conversation)],\"widgetConversationId\":null}")
  }
  func revoke() { rejected = true }
  /// Reject every write with an authorization status without touching reads.
  func rejectWrites(status: Int) { writeAuthStatus = status }
  /// Make the recovery read fail too, i.e. the customer really is signed out.
  func rejectIdentity() { identityRejected = true }
  /// Seed the thread the gateway will serve for an uncursored read.
  func seedHistory(_ ids: [Int64]) { history = ids }
  /// Simulate a thread whose full body no longer fits the transport ceiling.
  func failUncursoredHistory() { baseListTooLarge = true }
  func getIdentity() async throws -> DaykeeperCustomerIdentity {
    identityReads += 1
    if identityRejected || rejected { throw try authFailure(401) }
    return try decode(Self.identityJSON)
  }
  private func authFailure(_ status: Int) throws -> DaykeeperError {
    try decode(
      "{\"code\":\"expired_token\",\"status\":\(status),\"retryable\":false,\"outcomeUnknown\":false}"
    )
  }
  private func tooLarge() throws -> DaykeeperError {
    try decode(#"{"code":"RESPONSE_TOO_LARGE","retryable":false,"outcomeUnknown":false}"#)
  }
  private static func messageJSON(_ id: Int64) -> String {
    """
    {"id":\(id),"conversationId":7,"content":"Message \(id)","contentType":"text",    "contentAttributes":{},"messageType":1,"createdAt":123,"sender":null,"attachments":[]}
    """
  }
  func failReads(list: Bool, history: Bool) {
    listFailure = list
    historyFailure = history
  }
  private func failure() throws -> DaykeeperError {
    try decode(
      #"{"code":"support_upstream_unavailable","status":503,"retryable":false,"outcomeUnknown":true}"#
    )
  }
  func listMessages(in conversationID: Int64, after: Int64?) async throws -> DaykeeperMessageList {
    cursors.append(after)
    if historyFailure { throw try failure() }
    if after == nil && baseListTooLarge { throw try tooLarge() }
    let visible = history.filter { id in after.map { id > $0 } ?? true }
    return try decode("{\"messages\":[\(visible.map(Self.messageJSON).joined(separator: ","))]}")
  }
  func createConversation() async throws -> DaykeeperConversationResult {
    creates += 1
    if let writeAuthStatus { throw try authFailure(writeAuthStatus) }
    if uncertainWrites { throw try failure() }
    return await withCheckedContinuation { createContinuation = $0 }
  }
  func sendMessage(in conversationID: Int64, content: String) async throws -> DaykeeperMessageResult
  {
    sends += 1
    if let writeAuthStatus { throw try authFailure(writeAuthStatus) }
    if uncertainWrites { throw try failure() }
    return await withCheckedContinuation { sendContinuation = $0 }
  }
  func markConversationSeen(_ conversationID: Int64) async throws -> DaykeeperSeenResult {
    seen = true
    return try decode(#"{"conversationId":7,"seen":true,"seenAt":123}"#)
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
  @MainActor func testUncertainDraftRequiresSuccessfulFreshHistoryAndExplicitReview() async throws {
    let api = CustomerFixture(uncertainWrites: true)
    let active = DaykeeperMessengerSession(customerAPI: api)
    await active.refresh()
    await active.selectConversation(7)
    active.draft = "Preserve this uncertain message"
    await active.sendMessage()
    XCTAssertFalse(active.canDiscardUncertainDraft)
    XCTAssertFalse(active.canEditDraft)
    active.discardUncertainDraft()
    XCTAssertEqual(active.draft, "Preserve this uncertain message")
    await api.failReads(list: false, history: true)
    await active.refresh()
    XCTAssertFalse(active.canDiscardUncertainDraft)
    await api.failReads(list: false, history: false)
    await active.refresh()
    XCTAssertTrue(active.canDiscardUncertainDraft)
    XCTAssertFalse(active.canEditDraft)
    await api.failReads(list: true, history: false)
    await active.refresh()
    XCTAssertFalse(active.canDiscardUncertainDraft)
    await api.failReads(list: false, history: false)
    await active.refresh()
    active.discardUncertainDraft()
    XCTAssertEqual(active.draft, "")
    XCTAssertTrue(active.canEditDraft)
    let sends = await api.sends
    XCTAssertEqual(sends, 1)
    active.reset()
  }

  @MainActor func testUncertainCreationRequiresFreshListAndDoesNotRepeatWrite() async throws {
    let api = CustomerFixture(uncertainWrites: true)
    let active = DaykeeperMessengerSession(customerAPI: api)
    await active.createConversation()
    active.acknowledgeUncertainCreationAfterReview()
    XCTAssertTrue(active.uncertainCreation)
    XCTAssertFalse(active.canAcknowledgeUncertainCreation)
    await api.failReads(list: true, history: false)
    await active.refresh()
    active.acknowledgeUncertainCreationAfterReview()
    XCTAssertTrue(active.uncertainCreation)
    await api.failReads(list: false, history: false)
    await active.refresh()
    XCTAssertTrue(active.canAcknowledgeUncertainCreation)
    active.acknowledgeUncertainCreationAfterReview()
    XCTAssertFalse(active.uncertainCreation)
    let creates = await api.creates
    XCTAssertEqual(creates, 1)
    active.reset()
  }

  @MainActor func testBackgroundInvalidatesPriorRecoveryReadiness() async throws {
    let api = CustomerFixture(uncertainWrites: true)
    let active = DaykeeperMessengerSession(customerAPI: api)
    await active.refresh()
    await active.selectConversation(7)
    active.draft = "Preserved"
    await active.sendMessage()
    await active.refresh()
    XCTAssertTrue(active.canDiscardUncertainDraft)
    active.suspend()
    await api.failReads(list: true, history: false)
    await active.resume()
    XCTAssertFalse(active.canDiscardUncertainDraft)
    active.discardUncertainDraft()
    XCTAssertEqual(active.draft, "Preserved")
    active.reset()
  }

  @MainActor func testConfirmedReadMarkerRefreshesUnreadSummaryWithoutDroppingDraft() async throws {
    for unreadAfterSeen in [0, 2] {
      let api = CustomerFixture(unreadAfterSeen: unreadAfterSeen)
      let active = DaykeeperMessengerSession(customerAPI: api)
      await active.refresh()
      await active.selectConversation(7)
      active.draft = "Preserved while reading"
      XCTAssertEqual(active.conversations.first?.unreadForContact, 1)
      await active.markRead()
      XCTAssertEqual(active.conversations.first?.unreadForContact, unreadAfterSeen)
      XCTAssertEqual(active.draft, "Preserved while reading")
      XCTAssertEqual(active.selectedConversationID, 7)
    }
  }
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

  @MainActor func testExpiredTokenOnWriteKeepsDraftAndHistoryAndMarksItForReview() async throws {
    let api = CustomerFixture()
    await api.seedHistory([1, 2])
    let active = DaykeeperMessengerSession(customerAPI: api)
    await active.refresh()
    await active.selectConversation(7)
    XCTAssertEqual(active.messages.map(\.id), [1, 2])
    active.draft = "Please keep this"
    await api.rejectWrites(status: 401)
    await active.sendMessage()
    XCTAssertFalse(active.isSignedOut, "One expired token must not sign the customer out")
    XCTAssertEqual(active.draft, "Please keep this")
    XCTAssertEqual(active.messages.map(\.id), [1, 2], "History must survive the rejection")
    XCTAssertTrue(active.uncertainThreads.contains(7), "The send needs review, not a resend")
    XCTAssertFalse(active.canEditDraft)
    let identityReads = await api.identityReads
    XCTAssertEqual(identityReads, 1, "Exactly one recovery read")
    let sends = await api.sends
    XCTAssertEqual(sends, 1, "The write is never replayed")
  }

  @MainActor func testExpiredTokenOnWriteSignsOutOnlyWhenTheRefreshedReadAlsoFails() async throws {
    let api = CustomerFixture()
    await api.seedHistory([1])
    let active = DaykeeperMessengerSession(customerAPI: api)
    await active.refresh()
    await active.selectConversation(7)
    active.draft = "Gone with the session"
    await api.rejectWrites(status: 401)
    await api.rejectIdentity()
    await active.sendMessage()
    XCTAssertTrue(active.isSignedOut)
    XCTAssertTrue(active.messages.isEmpty)
    XCTAssertTrue(active.draft.isEmpty)
    let identityReads = await api.identityReads
    XCTAssertEqual(identityReads, 1)
    let sends = await api.sends
    XCTAssertEqual(sends, 1)
  }

  @MainActor func testRefreshPagesFromTheLastMessageSoAnOversizedThreadStaysReadable() async throws
  {
    let api = CustomerFixture()
    await api.seedHistory([1, 2])
    let active = DaykeeperMessengerSession(customerAPI: api)
    await active.refresh()
    await active.selectConversation(7)
    XCTAssertEqual(active.messages.map(\.id), [1, 2])
    // The thread has grown past the transport ceiling: an uncursored read of the
    // whole conversation would now fail outright.
    await api.failUncursoredHistory()
    await api.seedHistory([1, 2, 3])
    await active.refresh()
    XCTAssertNil(active.error, "A cursored refresh must not hit the response ceiling")
    XCTAssertEqual(active.messages.map(\.id), [1, 2, 3])
    let cursors = await api.cursors
    XCTAssertEqual(cursors, [nil, 2], "Refresh asks only for messages after the last one held")
  }

  @MainActor func testLoadEarlierMessagesMergesWithoutDroppingWhatIsAlreadyLoaded() async throws {
    let api = CustomerFixture()
    await api.seedHistory([5])
    let active = DaykeeperMessengerSession(customerAPI: api)
    await active.refresh()
    await active.selectConversation(7)
    XCTAssertTrue(active.canLoadEarlierMessages)
    await api.seedHistory([3, 4, 5])
    await active.loadEarlierMessages()
    XCTAssertEqual(active.messages.map(\.id), [3, 4, 5])
    let cursors = await api.cursors
    XCTAssertEqual(cursors.last, Int64?.none)
    let sends = await api.sends
    XCTAssertEqual(sends, 0, "Reading history is never a write")
  }
}
