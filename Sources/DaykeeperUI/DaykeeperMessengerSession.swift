import Combine
import Daykeeper
import Foundation

internal protocol CustomerAPI: Sendable {
  func listConversations() async throws -> DaykeeperConversationList
  func createConversation() async throws -> DaykeeperConversationResult
  func listMessages(in conversationID: Int64, after: Int64?) async throws -> DaykeeperMessageList
  func sendMessage(in conversationID: Int64, content: String) async throws -> DaykeeperMessageResult
  func markConversationSeen(_ conversationID: Int64) async throws -> DaykeeperSeenResult
}
extension DaykeeperClient: CustomerAPI {}

/// One instance per signed-in customer. Call reset() before changing identities;
/// it cancels pending tasks and drops the client/provider and all customer data.
@MainActor public final class DaykeeperMessengerSession: ObservableObject {
  @Published public private(set) var conversations: [DaykeeperConversation] = []
  @Published public private(set) var messages: [DaykeeperMessage] = []
  @Published public private(set) var selectedConversationID: Int64?
  @Published public private(set) var isBusy = false
  @Published public private(set) var isSuspended = false
  @Published public private(set) var isSignedOut = false
  @Published public private(set) var error: DaykeeperError?
  @Published public private(set) var uncertainCreation = false
  @Published public private(set) var uncertainThreads: Set<Int64> = []
  @Published public var draft = ""

  private var client: (any CustomerAPI)?
  private var revision = 0
  private var cancelCurrent: (() -> Void)?
  private var drafts: [Int64: String] = [:]
  private var suspendedSelection: Int64?
  private enum WriteConcern {
    case creation
    case message(Int64)
    case marker
  }
  private var pendingWrite: WriteConcern?

  public convenience init(client: DaykeeperClient) { self.init(customerAPI: client) }
  internal init(customerAPI: any CustomerAPI) { client = customerAPI }

  public var canSend: Bool {
    guard let id = selectedConversationID else { return false }
    return !isBusy && !isSuspended && !isSignedOut && !uncertainThreads.contains(id)
      && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && draft.utf16.count <= 16_000
  }

  public func refresh() async {
    let selected = selectedConversationID
    await perform { api in
      let list = try await api.listConversations()
      let messages = try await selected.mapAsync {
        try await api.listMessages(in: $0, after: nil).messages
      }
      return (list.conversations, messages)
    } success: { result in
      self.conversations = result.0
      if let messages = result.1 { self.messages = messages }
    }
  }

  public func selectConversation(_ id: Int64) async {
    guard conversations.contains(where: { $0.id == id }) else { return }
    saveDraft()
    await perform {
      try await $0.listMessages(in: id, after: nil)
    } success: { result in
      self.selectedConversationID = id
      self.messages = result.messages
      self.draft = self.drafts[id] ?? ""
    }
  }

  public func showConversations() {
    guard !isBusy else { return }
    saveDraft()
    selectedConversationID = nil
    messages = []
    draft = ""
    error = nil
  }

  public func createConversation() async {
    guard !uncertainCreation else { return }
    saveDraft()
    await perform(
      write: .creation, action: { try await $0.createConversation() },
      success: { result in
        self.conversations.insert(result.conversation, at: 0)
        self.selectedConversationID = result.conversation.id
        self.messages = []
        self.draft = ""
      })
  }

  public func sendMessage() async {
    guard canSend, let id = selectedConversationID else { return }
    let content = draft
    saveDraft()
    await perform(
      write: .message(id), action: { try await $0.sendMessage(in: id, content: content) },
      success: { result in
        if !self.messages.contains(where: { $0.id == result.message.id }) {
          self.messages.append(result.message)
        }
        self.draft = ""
        self.drafts[id] = nil
      })
  }

  public func markRead() async {
    guard let id = selectedConversationID else { return }
    // A read marker is still a write: it is never retried automatically.
    var confirmed = false
    await perform(
      write: .marker, action: { try await $0.markConversationSeen(id) },
      success: { _ in confirmed = true })
    // Read server truth rather than blindly clearing a count that may already
    // include a newer incoming message. This cannot repeat the write.
    if confirmed { await refresh() }
  }

  /// Explicitly discard a preserved draft only after the human reviews history.
  /// This does not cancel or reverse any previously accepted server write.
  public func discardUncertainDraft() {
    guard !isBusy, let id = selectedConversationID, uncertainThreads.contains(id) else { return }
    draft = ""
    drafts[id] = nil
    uncertainThreads.remove(id)
    error = nil
  }

  /// Human acknowledgement only, after inspecting the refreshed conversation
  /// list. This does not retry, cancel or undo the earlier create request.
  public func acknowledgeUncertainCreationAfterReview() {
    guard !isBusy, !isSuspended, !isSignedOut else { return }
    uncertainCreation = false
    error = nil
  }

  public func suspend() {
    guard !isSignedOut, !isSuspended else { return }
    saveDraft()
    suspendedSelection = selectedConversationID
    invalidate()
    isSuspended = true
    conversations = []
    messages = []
    selectedConversationID = nil
    draft = ""
    error = nil
  }

  public func resume() async {
    guard !isSignedOut else { return }
    if isSuspended {
      isSuspended = false
      selectedConversationID = suspendedSelection
      suspendedSelection = nil
      draft = selectedConversationID.flatMap { drafts[$0] } ?? ""
    }
    await refresh()
  }

  public func reset() {
    invalidate()
    client = nil
    conversations = []
    messages = []
    selectedConversationID = nil
    draft = ""
    drafts = [:]
    suspendedSelection = nil
    error = nil
    uncertainCreation = false
    uncertainThreads = []
    isSuspended = false
    isSignedOut = true
  }

  private func saveDraft() { if let id = selectedConversationID { drafts[id] = draft } }
  private func invalidate() {
    recordUncertainty(pendingWrite)
    pendingWrite = nil
    revision += 1
    cancelCurrent?()
    cancelCurrent = nil
    isBusy = false
  }

  private func recordUncertainty(_ write: WriteConcern?) {
    switch write {
    case .creation: uncertainCreation = true
    case .message(let id): uncertainThreads.insert(id)
    case .marker, .none: break
    }
  }

  private func perform<Value: Sendable>(
    write: WriteConcern? = nil,
    action: @escaping @Sendable (any CustomerAPI) async throws -> Value,
    success: (Value) -> Void
  ) async {
    guard !isBusy, !isSuspended, let client else { return }
    isBusy = true
    error = nil
    pendingWrite = write
    let ticket = revision
    let task = Task { try await action(client) }
    cancelCurrent = { task.cancel() }
    do {
      let result = try await task.value
      guard ticket == revision else { return }
      success(result)
    } catch {
      guard ticket == revision else { return }
      let safe = error as? DaykeeperError
      if safe?.status == 401 || safe?.status == 403 {
        // Revocation must not leave previously loaded customer data visible.
        // The host can establish a fresh session after authenticating again.
        reset()
        return
      }
      self.error = safe
      // Conservatively block retry if an injected test/host implementation
      // fails without the transport's structured outcome classification.
      if safe?.outcomeUnknown ?? true { recordUncertainty(write) }
    }
    if ticket == revision {
      isBusy = false
      cancelCurrent = nil
      pendingWrite = nil
    }
  }
}

extension Optional where Wrapped == Int64 {
  fileprivate func mapAsync<Value>(_ operation: (Int64) async throws -> Value) async rethrows
    -> Value?
  {
    guard let id = self else { return nil }
    return try await operation(id)
  }
}
