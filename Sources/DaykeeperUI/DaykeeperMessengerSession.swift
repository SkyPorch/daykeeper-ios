import Combine
import Daykeeper
import Foundation

internal protocol CustomerAPI: Sendable {
  func getIdentityWithFreshToken() async throws -> DaykeeperCustomerIdentity
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
  @Published private var reviewedUncertainThreads: Set<Int64> = []
  @Published private var creationReviewed = false

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
  /// Subject and identifier the customer token resolved to the first time this
  /// session read identity. A later read that resolves to anyone else means the
  /// host swapped customers underneath us and nothing loaded here may be shown.
  private var identityBaseline: (subject: String, identifier: String)?
  /// One read-marker recovery per session revision: a thread whose seen marker
  /// keeps being rejected must not ask the host for a token on every tap.
  private var markerRecoveryRevision: Int?

  public convenience init(client: DaykeeperClient) { self.init(customerAPI: client) }
  internal init(customerAPI: any CustomerAPI) { client = customerAPI }

  public var canEditDraft: Bool {
    guard let id = selectedConversationID else { return false }
    return !isBusy && !isSuspended && !isSignedOut && !uncertainThreads.contains(id)
  }

  public var canSend: Bool {
    canEditDraft && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && draft.utf16.count <= 16_000
  }

  public var canDiscardUncertainDraft: Bool {
    guard !isBusy, !isSuspended, !isSignedOut, let id = selectedConversationID else { return false }
    return uncertainThreads.contains(id) && reviewedUncertainThreads.contains(id)
  }

  public var canAcknowledgeUncertainCreation: Bool {
    !isBusy && !isSuspended && !isSignedOut && selectedConversationID == nil
      && uncertainCreation && creationReviewed
  }

  public func refresh() async {
    guard !isBusy, !isSuspended, !isSignedOut else { return }
    let selected = selectedConversationID
    if let selected { reviewedUncertainThreads.remove(selected) }
    creationReviewed = false
    // Ask only for what is new. Re-reading a long thread in full can exceed the
    // transport's response ceiling and make the whole conversation unreadable.
    let cursor = selected == nil ? nil : messages.last?.id
    await perform { api in
      let list = try await api.listConversations()
      let messages = try await selected.mapAsync {
        try await api.listMessages(in: $0, after: cursor).messages
      }
      return (list.conversations, messages)
    } success: { result in
      self.conversations = result.0
      if let messages = result.1 {
        if cursor == nil { self.replaceMessages(messages) } else { self.mergeMessages(messages) }
      }
      if let selected, self.uncertainThreads.contains(selected) {
        self.reviewedUncertainThreads.insert(selected)
      }
      if selected == nil && self.uncertainCreation { self.creationReviewed = true }
    }
  }

  public func selectConversation(_ id: Int64) async {
    guard !isBusy, !isSuspended, !isSignedOut, conversations.contains(where: { $0.id == id }) else {
      return
    }
    saveDraft()
    reviewedUncertainThreads.remove(id)
    await perform {
      try await $0.listMessages(in: id, after: nil)
    } success: { result in
      self.selectedConversationID = id
      self.replaceMessages(result.messages)
      self.draft = self.drafts[id] ?? ""
      if self.uncertainThreads.contains(id) { self.reviewedUncertainThreads.insert(id) }
    }
  }

  public func showConversations() {
    guard !isBusy else { return }
    saveDraft()
    selectedConversationID = nil
    replaceMessages([])
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
        self.replaceMessages([])
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
        self.mergeMessages([result.message])
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
    guard canDiscardUncertainDraft, let id = selectedConversationID else { return }
    draft = ""
    drafts[id] = nil
    uncertainThreads.remove(id)
    reviewedUncertainThreads.remove(id)
    error = nil
  }

  /// Human acknowledgement only, after inspecting the refreshed conversation
  /// list. This does not retry, cancel or undo the earlier create request.
  public func acknowledgeUncertainCreationAfterReview() {
    guard canAcknowledgeUncertainCreation else { return }
    uncertainCreation = false
    creationReviewed = false
    error = nil
  }

  public func suspend() {
    guard !isSignedOut, !isSuspended else { return }
    saveDraft()
    suspendedSelection = selectedConversationID
    invalidate()
    reviewedUncertainThreads = []
    creationReviewed = false
    isSuspended = true
    conversations = []
    replaceMessages([])
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
    replaceMessages([])
    selectedConversationID = nil
    draft = ""
    drafts = [:]
    suspendedSelection = nil
    error = nil
    uncertainCreation = false
    uncertainThreads = []
    reviewedUncertainThreads = []
    creationReviewed = false
    identityBaseline = nil
    markerRecoveryRevision = nil
    isSuspended = false
    isSignedOut = true
  }

  private func saveDraft() { if let id = selectedConversationID { drafts[id] = draft } }

  private func replaceMessages(_ values: [DaykeeperMessage]) {
    messages = values.sorted { $0.id < $1.id }
  }

  /// Pages arrive newest-side first and may overlap after a resend or a seen
  /// marker, so fold by identifier and keep the monotonic order.
  private func mergeMessages(_ values: [DaykeeperMessage]) {
    guard !values.isEmpty else { return }
    var byID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
    for value in values { byID[value.id] = value }
    messages = byID.values.sorted { $0.id < $1.id }
  }
  private func invalidate() {
    recordUncertainty(pendingWrite)
    pendingWrite = nil
    revision += 1
    cancelCurrent?()
    cancelCurrent = nil
    isBusy = false
  }

  /// Exactly one recovery attempt, and it always asks the host for a fresh
  /// token rather than relying on the ordinary 401 retry, which the gateway can
  /// suppress with a `retryable: false` hint. It is a read; nothing is replayed.
  /// The task is registered the same way `perform` registers its own, so
  /// suspend() and reset() cancel it and a stale answer can never be applied.
  ///
  /// A successful read must also resolve to the same customer. The first read
  /// records the baseline; any later read that names a different subject or
  /// identifier means the host swapped identities and the session is dropped.
  private func confirmSessionAfterWriteRejection(ticket: Int) async -> Recovery {
    guard let client else { return .signedOut }
    let task = Task { try await client.getIdentityWithFreshToken() }
    cancelCurrent = { task.cancel() }
    let identity: DaykeeperCustomerIdentity
    do {
      identity = try await task.value
    } catch {
      // Only a rejected credential proves the customer is gone. A timeout, a
      // dropped connection or a 5xx says nothing about it, so the session and
      // everything the customer typed stay exactly as they are.
      let status = (error as? DaykeeperError)?.status
      return status == 401 || status == 403 ? .signedOut : .unavailable
    }
    guard ticket == revision else { return .unavailable }
    guard let baseline = identityBaseline else {
      identityBaseline = (identity.subject, identity.identifier)
      return .signedIn
    }
    return baseline.subject == identity.subject && baseline.identifier == identity.identifier
      ? .signedIn : .signedOut
  }

  private enum Recovery {
    /// A fresh credential works and names the same customer.
    case signedIn
    /// The gateway rejected the fresh credential, or it named someone else.
    case signedOut
    /// The recovery read failed for a reason unrelated to the credential.
    case unavailable
  }

  private func recordUncertainty(_ write: WriteConcern?) {
    switch write {
    case .creation:
      uncertainCreation = true
      creationReviewed = false
    case .message(let id):
      uncertainThreads.insert(id)
      reviewedUncertainThreads.remove(id)
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
        guard let write else {
          // A rejected read means the credential is gone. Revocation must not
          // leave previously loaded customer data visible; the host can
          // establish a fresh session after authenticating again.
          reset()
          return
        }
        var alreadyConfirmed = false
        if case .marker = write, markerRecoveryRevision == ticket { alreadyConfirmed = true }
        if !alreadyConfirmed {
          // A write may have been accepted before the token expired. Do not throw
          // the draft and the history away on the first rejection: ask for one
          // fresh token and prove the same customer is still signed in.
          if case .marker = write { markerRecoveryRevision = ticket }
          switch await confirmSessionAfterWriteRejection(ticket: ticket) {
          case .signedOut:
            reset()
            return
          case .unavailable:
            // Fall through to the ordinary error path: nothing was learned about
            // the credential, so nothing the customer can see is thrown away.
            break
          case .signedIn:
            break
          }
          guard ticket == revision else { return }
        }
        // Never resend the write. A 4xx rejection is a definite refusal: the
        // gateway did not accept it, so the draft stays editable and only the
        // message changes. Uncertainty is reserved for outcomes we cannot know.
        self.error = safe
        if safe?.outcomeUnknown ?? true { recordUncertainty(write) }
        if ticket == revision {
          isBusy = false
          cancelCurrent = nil
          pendingWrite = nil
        }
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
