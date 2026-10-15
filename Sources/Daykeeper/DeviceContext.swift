import Foundation

/// What the SDK tells the gateway about the device it runs on, so a support
/// agent sees the app version, OS and hardware on the contact without the host
/// app writing any code. It is sent in the `Daykeeper-Client` header as
/// base64url (no padding) of a UTF-8 JSON object.
///
/// It is presentation context, never authorization: a value the host backend
/// signs into the customer token always wins on the gateway. It never carries
/// an identifier for the device or the person: no `identifierForVendor`,
/// advertising identifier, user-assigned device name, or location.
internal struct DaykeeperDeviceContext: Equatable, Sendable {
  static let headerName = "Daykeeper-Client"
  /// The gateway ignores a longer header, so a longer one is never sent.
  static let maximumHeaderLength = 4096

  var sdk: String?
  var sdkVersion: String?
  var platform: String?
  var osName: String?
  var osVersion: String?
  var deviceBrand: String?
  var deviceModel: String?
  var appName: String?
  var appId: String?
  var appVersion: String?
  var appBuild: String?
  var locale: String?
  var timeZone: String?

  /// Collected once per process, on first use. A Swift global is initialized
  /// lazily and exactly once, so concurrent first requests do not race, and
  /// nothing here touches the main actor or waits on anything.
  static let header: String? = current().headerValue

  /// Each key in wire order with its length limit, counted in UTF-16 units to
  /// match the gateway. Over-long values are dropped, not truncated.
  var fields: [(key: String, value: String?, limit: Int)] {
    [
      ("sdk", sdk, 100), ("sdkVersion", sdkVersion, 100), ("platform", platform, 100),
      ("osName", osName, 100), ("osVersion", osVersion, 100),
      ("deviceBrand", deviceBrand, 100), ("deviceModel", deviceModel, 100),
      ("appName", appName, 200), ("appId", appId, 100), ("appVersion", appVersion, 100),
      ("appBuild", appBuild, 100), ("locale", locale, 100), ("timeZone", timeZone, 100),
    ]
  }

  /// The values that will be sent: trimmed, never empty, never over-long.
  var payload: [String: String] {
    var result: [String: String] = [:]
    for field in fields {
      guard let value = field.value?.trimmingCharacters(in: .whitespacesAndNewlines),
        !value.isEmpty, value.utf16.count <= field.limit
      else { continue }
      result[field.key] = value
    }
    return result
  }

  /// The header value, or nil when there is nothing to say or it cannot be
  /// encoded within the gateway's limit. Never throws: a device that cannot
  /// describe itself still gets support.
  var headerValue: String? {
    let payload = payload
    guard !payload.isEmpty,
      let json = try? JSONSerialization.data(
        withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
    else { return nil }
    let value = Self.base64URL(json)
    return value.count <= Self.maximumHeaderLength ? value : nil
  }

  /// RFC 4648 §5 base64url without padding.
  static func base64URL(_ data: Data) -> String {
    var value = data.base64EncodedString()
    value = value.replacingOccurrences(of: "+", with: "-")
    value = value.replacingOccurrences(of: "/", with: "_")
    while value.hasSuffix("=") { value.removeLast() }
    return value
  }

  /// Reads the context from public, non-isolated platform APIs only. UIKit's
  /// `UIDevice` is main-actor isolated, so it is deliberately not used; the
  /// hardware identifier already distinguishes an iPad from an iPhone.
  static func current(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundle: Bundle = .main
  ) -> DaykeeperDeviceContext {
    let model = hardwareModel(environment: environment)
    let info = { (key: String) in bundle.object(forInfoDictionaryKey: key) as? String }
    return DaykeeperDeviceContext(
      sdk: "ios",
      sdkVersion: DaykeeperClient.sdkVersion,
      platform: "ios",
      osName: operatingSystemName(model: model),
      osVersion: operatingSystemVersion(),
      deviceBrand: "Apple",
      deviceModel: model,
      appName: info("CFBundleDisplayName") ?? info("CFBundleName"),
      appId: bundle.bundleIdentifier,
      appVersion: info("CFBundleShortVersionString"),
      appBuild: info("CFBundleVersion"),
      locale: Locale.preferredLanguages.first,
      timeZone: TimeZone.current.identifier
    )
  }

  /// The hardware identifier (for example `iPhone17,1`), never a marketing name.
  static func hardwareModel(environment: [String: String]) -> String? {
    #if targetEnvironment(simulator)
      return environment["SIMULATOR_MODEL_IDENTIFIER"]
    #elseif os(macOS) || targetEnvironment(macCatalyst)
      return sysctlString("hw.model")
    #else
      #if os(iOS)
        if ProcessInfo.processInfo.isiOSAppOnMac { return sysctlString("hw.model") }
      #endif
      var system = utsname()
      guard uname(&system) == 0 else { return nil }
      return withUnsafeBytes(of: &system.machine) { bytes in
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
      }
    #endif
  }

  static func operatingSystemName(model: String?) -> String {
    #if os(visionOS)
      return "visionOS"
    #elseif os(macOS) || targetEnvironment(macCatalyst)
      return "macOS"
    #elseif os(iOS)
      if ProcessInfo.processInfo.isiOSAppOnMac { return "macOS" }
      return model?.hasPrefix("iPad") == true ? "iPadOS" : "iOS"
    #elseif os(tvOS)
      return "tvOS"
    #elseif os(watchOS)
      return "watchOS"
    #else
      return "unknown"
    #endif
  }

  static func operatingSystemVersion() -> String {
    #if targetEnvironment(macCatalyst)
      // Mac Catalyst reports the iOS version it is compatible with; the Mac's
      // own release is what an agent needs next to "macOS".
      if let version = sysctlString("kern.osproductversion") { return version }
    #elseif os(iOS)
      if ProcessInfo.processInfo.isiOSAppOnMac,
        let version = sysctlString("kern.osproductversion")
      {
        return version
      }
    #endif
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let base = "\(version.majorVersion).\(version.minorVersion)"
    return version.patchVersion > 0 ? "\(base).\(version.patchVersion)" : base
  }

  private static func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size <= 256 else { return nil }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
  }
}
