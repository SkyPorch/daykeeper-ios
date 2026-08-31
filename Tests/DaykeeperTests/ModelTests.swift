import XCTest

@testable import Daykeeper

final class ModelTests: XCTestCase {
  func testTimestampAndNestedContentAttributesRoundTripWithoutLosingNulls() throws {
    for timestamp in ["null", "123", "\"2026-09-01T00:00:00Z\""] {
      let json = """
        {"id":9,"conversationId":7,"content":null,"contentType":"text",
        "contentAttributes":{"list":[true,null,1.5,{"label":"hello"}]},"messageType":1,
        "createdAt":\(timestamp),"sender":{"name":null,"avatarUrl":null},
        "attachments":[{"id":11,"fileType":null,"dataUrl":null,"thumbUrl":null}],"futureField":"ignored"}
        """
      let value = try JSONDecoder().decode(DaykeeperMessage.self, from: Data(json.utf8))
      XCTAssertEqual(
        value.contentAttributes["list"],
        .array([.bool(true), .null, .number(1.5), .object(["label": .string("hello")])]))
      XCTAssertEqual(value.attachments[0].id, 11)
      XCTAssertEqual(
        value, try JSONDecoder().decode(DaykeeperMessage.self, from: JSONEncoder().encode(value)))
    }
  }

  func testInvalidScalarShapesFailDecoding() throws {
    for json in [
      #"{"status":"open"}"#, #"{"id":"7","status":"open","unreadCount":0,"unreadForContact":0}"#,
    ] {
      XCTAssertThrowsError(
        try JSONDecoder().decode(DaykeeperConversation.self, from: Data(json.utf8)))
    }
    XCTAssertThrowsError(try JSONDecoder().decode(DaykeeperTimestamp.self, from: Data("true".utf8)))
  }
}
