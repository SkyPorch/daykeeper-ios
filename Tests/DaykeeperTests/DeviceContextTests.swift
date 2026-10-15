import XCTest

@testable import Daykeeper

final class DeviceContextTests: XCTestCase {
  private func decode(_ header: String) throws -> [String: String] {
    var base64 = header.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    let data = try XCTUnwrap(Data(base64Encoded: base64))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
  }

  func testBase64URLUsesTheURLAlphabetWithoutPadding() {
    // 0xFB 0xFF encodes to "+/8=" in standard base64.
    XCTAssertEqual(DaykeeperDeviceContext.base64URL(Data([0xFB, 0xFF])), "-_8")
    XCTAssertEqual(DaykeeperDeviceContext.base64URL(Data("a".utf8)), "YQ")
    XCTAssertEqual(DaykeeperDeviceContext.base64URL(Data("ab".utf8)), "YWI")
    XCTAssertEqual(DaykeeperDeviceContext.base64URL(Data("abc".utf8)), "YWJj")
  }

  func testNonASCIIAppNameRoundTripsThroughUTF8() throws {
    let name = "Dagboek — Ünïcödé 日記 😀"
    for padding in 0..<3 {
      // Vary the length so every padding remainder is exercised.
      let context = DaykeeperDeviceContext(
        appName: name + String(repeating: "x", count: padding),
        timeZone: "Europe/Amsterdam")
      let header = try XCTUnwrap(context.headerValue)
      XCTAssertNotNil(header.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression))
      XCTAssertFalse(header.contains("="))
      let decoded = try decode(header)
      XCTAssertEqual(decoded["appName"], name + String(repeating: "x", count: padding))
      XCTAssertEqual(decoded["timeZone"], "Europe/Amsterdam")
    }
  }

  func testEmptyBlankAndOverLongValuesAreOmitted() throws {
    let context = DaykeeperDeviceContext(
      sdk: "ios", sdkVersion: "", platform: "  ", osName: " iOS\n",
      deviceModel: String(repeating: "m", count: 101),
      appName: String(repeating: "n", count: 200),
      appId: String(repeating: "a", count: 101), appVersion: String(repeating: "v", count: 100))
    let decoded = try decode(XCTUnwrap(context.headerValue))
    XCTAssertEqual(
      decoded,
      [
        "sdk": "ios", "osName": "iOS", "appName": String(repeating: "n", count: 200),
        "appVersion": String(repeating: "v", count: 100),
      ])
    XCTAssertNil(
      DaykeeperDeviceContext(appName: String(repeating: "n", count: 201)).payload["appName"])
    // Limits count UTF-16 units, as the gateway does: 50 emoji are 100 units.
    XCTAssertNotNil(
      DaykeeperDeviceContext(osName: String(repeating: "😀", count: 50)).payload["osName"])
    XCTAssertNil(
      DaykeeperDeviceContext(osName: String(repeating: "😀", count: 51)).payload["osName"])
  }

  func testNothingToSayMeansNoHeader() {
    XCTAssertNil(DaykeeperDeviceContext().headerValue)
    XCTAssertNil(DaykeeperDeviceContext(sdk: " ", appName: "").headerValue)
  }

  func testCollectedContextHasNoIdentifiersAndFitsTheGateway() throws {
    let context = DaykeeperDeviceContext.current()
    XCTAssertEqual(context.sdk, "ios")
    XCTAssertEqual(context.platform, "ios")
    XCTAssertEqual(context.deviceBrand, "Apple")
    XCTAssertEqual(context.sdkVersion, DaykeeperClient.sdkVersion)
    XCTAssertEqual(context.timeZone, TimeZone.current.identifier)
    XCTAssertEqual(context.locale, Locale.preferredLanguages.first)
    XCTAssertNotNil(
      context.osVersion?.range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression))
    let header = try XCTUnwrap(DaykeeperDeviceContext.header)
    XCTAssertLessThanOrEqual(header.count, DaykeeperDeviceContext.maximumHeaderLength)
    let decoded = try decode(header)
    let allowed: Set = [
      "sdk", "sdkVersion", "platform", "osName", "osVersion", "deviceBrand", "deviceModel",
      "appName", "appId", "appVersion", "appBuild", "locale", "timeZone",
    ]
    XCTAssertTrue(Set(decoded.keys).isSubset(of: allowed), "\(decoded.keys)")
    XCTAssertEqual(decoded, context.payload)
  }

  func testSimulatorModelComesFromTheSimulatorEnvironment() {
    #if targetEnvironment(simulator)
      XCTAssertEqual(
        DaykeeperDeviceContext.hardwareModel(environment: [
          "SIMULATOR_MODEL_IDENTIFIER": "iPad13,1"
        ]),
        "iPad13,1")
      XCTAssertEqual(DaykeeperDeviceContext.operatingSystemName(model: "iPad13,1"), "iPadOS")
      XCTAssertEqual(DaykeeperDeviceContext.operatingSystemName(model: "iPhone17,1"), "iOS")
    #else
      // Off the simulator the identifier comes from the hardware, never from
      // the environment, and is never a marketing name such as "iPhone 16".
      let model = DaykeeperDeviceContext.hardwareModel(environment: [
        "SIMULATOR_MODEL_IDENTIFIER": "iPad13,1"
      ])
      XCTAssertNotEqual(model, "iPad13,1")
      XCTAssertFalse(model?.contains(" ") ?? false)
    #endif
  }

  /// A release bumps `spec.version` in the podspecs; this keeps the version the
  /// SDK reports to the gateway from silently drifting behind it.
  func testSDKVersionMatchesBothPodspecs() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    for name in ["Daykeeper.podspec", "DaykeeperUI.podspec"] {
      let spec = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
      let versions = spec.split(separator: "\n").compactMap { line -> String? in
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2,
          parts[0].trimmingCharacters(in: .whitespaces) == "spec.version"
        else { return nil }
        return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" \t"))
      }
      XCTAssertEqual(versions, [DaykeeperClient.sdkVersion], name)
    }
  }
}
