import Daykeeper
import SwiftUI

/// Present as a sheet or embed in your app. No global presenter, tracking,
/// swizzling, web view, cookie jar, credential store or remote asset loading.
public struct DaykeeperMessenger: View {
  @ObservedObject private var session: DaykeeperMessengerSession
  @Environment(\.scenePhase) private var scenePhase
  @State private var discardConfirmation = false
  @State private var creationConfirmation = false
  @FocusState private var isEditing: Bool

  public init(session: DaykeeperMessengerSession) { self.session = session }

  public var body: some View {
    NavigationView {
      Group {
        if session.isSignedOut {
          Text("Sign in to your app to use support.").padding()
        } else if session.isSuspended {
          Text("Support is paused while the app is inactive.").padding()
        } else {
          VStack(spacing: 0) {
            status
            if session.selectedConversationID != nil { thread } else { conversationList }
          }
        }
      }
      .navigationTitle("Support")
      .toolbar {
        #if os(iOS)
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { isEditing = false }.accessibilityIdentifier("daykeeper.done-editing")
          }
        #endif
        ToolbarItemGroup(placement: .automatic) {
          if session.selectedConversationID != nil {
            Button("Conversations") { session.showConversations() }
              .disabled(session.isBusy).accessibilityIdentifier("daykeeper.conversations")
          }
          Button("Refresh") { Task { await session.refresh() } }
            .disabled(session.isBusy || session.isSignedOut || session.isSuspended)
            .accessibilityIdentifier("daykeeper.refresh")
        }
      }
    }
    .daykeeperNavigationStyle()
    .task { await session.resume() }
    .onDisappear { session.suspend() }
    .onChange(of: scenePhase) { phase in
      if phase == .active { Task { await session.resume() } } else { session.suspend() }
    }
    .alert("Discard this draft?", isPresented: $discardConfirmation) {
      Button("Keep draft", role: .cancel) {}
      Button("Discard draft", role: .destructive) { session.discardUncertainDraft() }
    } message: {
      Text(
        "The earlier message may already have been sent. Review the conversation first. Discarding this draft cannot undo a sent message."
      )
    }
    .alert("Finished reviewing conversations?", isPresented: $creationConfirmation) {
      Button("Keep reviewing", role: .cancel) {}
      Button("I have reviewed the list") { session.acknowledgeUncertainCreationAfterReview() }
    } message: {
      Text(
        "The earlier conversation may already exist. This only enables starting a new conversation; it does not repeat or undo the earlier request."
      )
    }
  }

  @ViewBuilder private var status: some View {
    if session.isBusy {
      ProgressView("Updating support…").padding().accessibilityIdentifier("daykeeper.progress")
    }
    if let error = session.error {
      Text(message(for: error))
        .font(.callout).foregroundStyle(.secondary).padding()
        .accessibilityIdentifier("daykeeper.error")
    }
    if session.uncertainCreation {
      Text(
        "We could not confirm the new conversation. Refresh and inspect existing conversations before starting another. No request was automatically repeated."
      )
      .font(.callout).padding()
      Button("Finish reviewing conversations") { creationConfirmation = true }
        .disabled(session.isBusy).padding(.bottom)
    }
  }

  private var conversationList: some View {
    List {
      if session.conversations.isEmpty && !session.isBusy {
        Text("No conversations yet.").foregroundStyle(.secondary)
      }
      ForEach(session.conversations) { conversation in
        Button {
          Task { await session.selectConversation(conversation.id) }
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(conversation.preview ?? "Conversation \(conversation.id)").lineLimit(2)
              .foregroundStyle(.primary)
            Text(
              conversation.unreadForContact > 0
                ? "\(conversation.unreadForContact) unread" : conversation.status
            )
            .font(.caption).foregroundStyle(Color.secondary)
          }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
        }.disabled(session.isBusy)
          .accessibilityIdentifier("daykeeper.conversation.\(conversation.id)")
      }
      Button("New conversation") { Task { await session.createConversation() } }
        .disabled(session.isBusy || session.uncertainCreation)
        .accessibilityIdentifier("daykeeper.new-conversation")
    }
  }

  private var thread: some View {
    VStack(spacing: 0) {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(session.messages) { item in
              VStack(alignment: .leading, spacing: 6) {
                Text(item.messageType == 0 ? "You" : item.sender?.name ?? "Support").font(.caption)
                  .bold()
                Text(item.content ?? "").textSelection(.enabled)
                  .accessibilityIdentifier("daykeeper.message.\(item.id)")
                if !item.attachments.isEmpty {
                  Text(
                    "This message includes \(item.attachments.count) attachment(s). Attachment viewing is not available in this SDK candidate."
                  )
                  .font(.caption).foregroundStyle(.secondary)
                }
              }
              .padding().frame(
                maxWidth: .infinity, alignment: item.messageType == 0 ? .trailing : .leading
              )
              .background(
                item.messageType == 0
                  ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)
              ).cornerRadius(12)
              .id(item.id)
            }
          }.padding()
        }
        .onChange(of: session.messages.last?.id) { id in
          if let id { proxy.scrollTo(id, anchor: .bottom) }
        }
      }
      Divider()
      if let id = session.selectedConversationID, session.uncertainThreads.contains(id) {
        VStack(alignment: .leading) {
          Text(
            "Your message may have been sent. The draft is preserved. Refresh and review history; it will not be sent again automatically."
          ).font(.callout)
          Button("Discard draft after review") { discardConfirmation = true }.disabled(
            session.isBusy)
        }.padding()
      }
      HStack(alignment: .bottom) {
        TextEditor(text: $session.draft)
          .focused($isEditing)
          .frame(minHeight: 48, maxHeight: 120).border(Color.secondary.opacity(0.3))
          .disabled(session.isBusy)
          .accessibilityLabel("Message").accessibilityIdentifier("daykeeper.message")
        Button("Send") {
          isEditing = false
          Task { await session.sendMessage() }
        }
        .disabled(!session.canSend).accessibilityIdentifier("daykeeper.send")
      }.padding()
      Button("Mark conversation read") { Task { await session.markRead() } }.disabled(
        session.isBusy
      ).padding(.bottom).accessibilityIdentifier("daykeeper.mark-read")
    }
  }

  private func message(for error: DaykeeperError) -> String {
    if error.outcomeUnknown {
      return "The result could not be confirmed. Review history before trying another write."
    }
    switch error.code {
    case "daykeeper_usage_limit_exceeded":
      return
        "Support has reached its current allowance. Contact the workspace owner. Existing history remains available."
    case "daykeeper_usage_not_enabled", "daykeeper_support_not_ready":
      return "This support inbox is not ready yet. Contact the workspace owner."
    case "REQUEST_TIMEOUT", "NETWORK_ERROR":
      return "Support could not be reached. Check your connection and refresh."
    case "REQUEST_ABORTED": return "The request was canceled."
    case "TOKEN_PROVIDER_ERROR":
      return "Your app could not confirm your support session. Sign in again."
    default:
      return "Support could not complete that request. Refresh your session before trying again."
    }
  }
}

extension View {
  @ViewBuilder fileprivate func daykeeperNavigationStyle() -> some View {
    #if os(iOS)
      self.navigationViewStyle(.stack)
    #else
      self
    #endif
  }
}
