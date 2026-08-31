import Foundation

/// Wire timestamps may be epoch integers, ISO strings or null. No local-time inference.
public enum DaykeeperTimestamp: Codable, Sendable, Equatable {
  case epoch(Int64)
  case text(String)
  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if let number = try? value.decode(Int64.self) {
      self = .epoch(number)
    } else {
      self = .text(try value.decode(String.self))
    }
  }
  public func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .epoch(let number): try value.encode(number)
    case .text(let text): try value.encode(text)
    }
  }
}

public enum DaykeeperJSONValue: Codable, Sendable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: Self])
  case array([Self])
  case null
  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() {
      self = .null
    } else if let item = try? value.decode(Bool.self) {
      self = .bool(item)
    } else if let item = try? value.decode(String.self) {
      self = .string(item)
    } else if let item = try? value.decode(Double.self) {
      self = .number(item)
    } else if let item = try? value.decode([String: Self].self) {
      self = .object(item)
    } else {
      self = .array(try value.decode([Self].self))
    }
  }
  public func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .string(let item): try value.encode(item)
    case .number(let item): try value.encode(item)
    case .bool(let item): try value.encode(item)
    case .object(let item): try value.encode(item)
    case .array(let item): try value.encode(item)
    case .null: try value.encodeNil()
    }
  }
}

public struct DaykeeperConversation: Codable, Sendable, Equatable, Identifiable {
  public let id: Int64
  public let status: String
  public let createdAt: DaykeeperTimestamp?
  public let updatedAt: DaykeeperTimestamp?
  /// Agent-side provider count; use unreadForContact for a customer badge.
  public let unreadCount: Int
  public let unreadForContact: Int
  public let lastSeenAt: Int64?
  public let preview: String?
}

public struct DaykeeperAttachment: Codable, Sendable, Equatable, Identifiable {
  public let id: Int64
  public let fileType: String?
  public let dataUrl: String?
  public let thumbUrl: String?
}

public struct DaykeeperMessageSender: Codable, Sendable, Equatable {
  public let name: String?
  public let avatarUrl: String?
}

public struct DaykeeperMessage: Codable, Sendable, Equatable, Identifiable {
  public let id: Int64
  public let conversationId: Int64
  public let content: String?
  public let contentType: String
  public let contentAttributes: [String: DaykeeperJSONValue]
  public let messageType: Int
  public let createdAt: DaykeeperTimestamp?
  public let sender: DaykeeperMessageSender?
  public let attachments: [DaykeeperAttachment]
}

public struct DaykeeperCustomerIdentity: Codable, Sendable, Equatable {
  public let baseUrl: String
  public let websiteToken: String
  public let subject: String
  public let identifier: String
  public let identifierHash: String
  public let email: String?
  public let name: String
}

public struct DaykeeperConversationList: Codable, Sendable, Equatable {
  public let conversations: [DaykeeperConversation]
  public let widgetConversationId: Int64?
}
public struct DaykeeperConversationResult: Codable, Sendable, Equatable {
  public let conversation: DaykeeperConversation
}
public struct DaykeeperUnreadSummary: Codable, Sendable, Equatable {
  public let unreadCount: Int
  public let conversation: DaykeeperConversation?
  public let conversations: [DaykeeperConversation]
}
public struct DaykeeperSeenResult: Codable, Sendable, Equatable {
  public let conversationId: Int64
  public let seen: Bool
  public let seenAt: Int64
  public let seenMessageId: Int64?
}
public struct DaykeeperMessageList: Codable, Sendable, Equatable {
  public let messages: [DaykeeperMessage]
}
public struct DaykeeperMessageResult: Codable, Sendable, Equatable {
  public let message: DaykeeperMessage
}
public struct DaykeeperClaimConversationResult: Codable, Sendable, Equatable {
  public let status: String
  public let conversations: Int
}
