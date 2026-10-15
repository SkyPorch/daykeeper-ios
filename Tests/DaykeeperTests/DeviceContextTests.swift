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
      appId: String(repeating: "a", count: 201), appVersion: String(repeating: "v", count: 100))
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

  /// A throwaway bundle with exactly these Info.plist keys. Each one gets its
  /// own directory because Foundation caches bundles by path.
  private func fixtureBundle(_ info: [String: String]) throws -> Bundle {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("daykeeper-\(UUID().uuidString).bundle")
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    #if os(macOS)
      let directory = root.appendingPathComponent("Contents")
    #else
      let directory = root
    #endif
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: directory.appendingPathComponent("Info.plist"))
    return try XCTUnwrap(Bundle(url: root))
  }

  func testCurrentReadsTheAppFromItsBundle() throws {
    let named = try fixtureBundle([
      "CFBundleIdentifier": "com.example.journal", "CFBundleName": "Journal",
      "CFBundleShortVersionString": "4.2.1", "CFBundleVersion": "20261015.3",
    ])
    let context = DaykeeperDeviceContext.current(environment: [:], bundle: named)
    // No display name, so the bundle name stands in for it.
    XCTAssertEqual(context.appName, "Journal")
    XCTAssertEqual(context.appId, "com.example.journal")
    XCTAssertEqual(context.appVersion, "4.2.1")
    XCTAssertEqual(context.appBuild, "20261015.3")
    let payload = context.payload
    XCTAssertEqual(payload["appName"], "Journal")
    XCTAssertEqual(payload["appId"], "com.example.journal")
    XCTAssertEqual(payload["appVersion"], "4.2.1")
    XCTAssertEqual(payload["appBuild"], "20261015.3")

    let displayed = try fixtureBundle([
      "CFBundleIdentifier": "com.example.journal", "CFBundleName": "Journal",
      "CFBundleDisplayName": "Dagboek",
    ])
    XCTAssertEqual(
      DaykeeperDeviceContext.current(environment: [:], bundle: displayed).appName, "Dagboek")
  }

  func testBundleIdentifiersUpToTheGatewayLimitAreKept() throws {
    // App Store bundle identifiers can be 155 characters long.
    let longest = "com." + String(repeating: "a", count: 151)
    XCTAssertEqual(longest.count, 155)
    let kept = try fixtureBundle(["CFBundleIdentifier": longest])
    XCTAssertEqual(
      DaykeeperDeviceContext.current(environment: [:], bundle: kept).payload["appId"], longest)
    let tooLong = "com." + String(repeating: "a", count: 197)
    XCTAssertEqual(tooLong.count, 201)
    let dropped = try fixtureBundle(["CFBundleIdentifier": tooLong])
    let context = DaykeeperDeviceContext.current(environment: [:], bundle: dropped)
    XCTAssertEqual(context.appId, tooLong)
    XCTAssertNil(context.payload["appId"])
    XCTAssertNotNil(context.headerValue)
  }

  func testIPadHardwareReportsIPadOSAndEverythingElseIOS() {
    XCTAssertEqual(DaykeeperDeviceContext.mobileSystemName(model: "iPad13,1"), "iPadOS")
    XCTAssertEqual(DaykeeperDeviceContext.mobileSystemName(model: "iPad14,9"), "iPadOS")
    XCTAssertEqual(DaykeeperDeviceContext.mobileSystemName(model: "iPhone17,1"), "iOS")
    XCTAssertEqual(DaykeeperDeviceContext.mobileSystemName(model: nil), "iOS")
    XCTAssertNil(DaykeeperDeviceContext(sdk: "ios", deviceModel: nil).payload["deviceModel"])
    #if targetEnvironment(simulator)
      // A simulator that does not name its model: iOS, and no model at all.
      let context = DaykeeperDeviceContext.current(environment: [:])
      XCTAssertNil(context.deviceModel)
      XCTAssertNil(context.payload["deviceModel"])
      XCTAssertEqual(context.osName, "iOS")
      let iPad = DaykeeperDeviceContext.current(environment: [
        "SIMULATOR_MODEL_IDENTIFIER": "iPad13,1"
      ])
      XCTAssertEqual(iPad.deviceModel, "iPad13,1")
      XCTAssertEqual(iPad.osName, "iPadOS")
      let iPhone = DaykeeperDeviceContext.current(environment: [
        "SIMULATOR_MODEL_IDENTIFIER": "iPhone17,1"
      ])
      XCTAssertEqual(iPhone.deviceModel, "iPhone17,1")
      XCTAssertEqual(iPhone.osName, "iOS")
    #endif
  }

  func testAHeaderOverTheGatewayLimitIsNotSent() {
    // Every field at its limit in three-byte UTF-8 characters encodes to far
    // more than 4096 characters, so the gateway would ignore it anyway.
    let full = { (count: Int) in String(repeating: "日", count: count) }
    let context = DaykeeperDeviceContext(
      sdk: full(100), sdkVersion: full(100), platform: full(100), osName: full(100),
      osVersion: full(100), deviceBrand: full(100), deviceModel: full(100),
      appName: full(200), appId: full(200), appVersion: full(100), appBuild: full(100),
      locale: full(100), timeZone: full(100))
    XCTAssertEqual(context.payload.count, 13)
    XCTAssertNil(context.headerValue)
  }

  func testTheLargestRealisticContextFitsUnderTheCap() throws {
    let bundle = try fixtureBundle([
      "CFBundleIdentifier": "com." + String(repeating: "a", count: 151),
      "CFBundleDisplayName": String(repeating: "日", count: 200),
      "CFBundleShortVersionString": String(repeating: "9", count: 100),
      "CFBundleVersion": String(repeating: "9", count: 100),
    ])
    let context = DaykeeperDeviceContext.current(
      environment: ["SIMULATOR_MODEL_IDENTIFIER": "iPad16,6"], bundle: bundle)
    XCTAssertEqual(context.payload["appName"], String(repeating: "日", count: 200))
    XCTAssertNotNil(context.payload["appId"])
    let header = try XCTUnwrap(context.headerValue)
    XCTAssertLessThanOrEqual(header.count, DaykeeperDeviceContext.maximumHeaderLength)
    XCTAssertEqual(try decode(header), context.payload)
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
