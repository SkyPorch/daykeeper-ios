import Daykeeper
import DaykeeperUI
import SwiftUI

// A debug-only synthetic fixture host, not an authentication implementation.
// Release builds and missing configuration fail closed with no network calls.
@main struct DaykeeperExampleApp: App {
  @StateObject private var host = ExampleHost()
  var body: some Scene {
    WindowGroup {
      VStack(spacing: 0) {
        HStack {
          Text("Example · customer \(host.customer)").font(.caption)
          Spacer()
          Button("Switch customer") { host.switchCustomer() }
            .accessibilityIdentifier("example.switch")
          Button("Sign out") { host.session?.reset() }
            .accessibilityIdentifier("example.sign-out")
        }.padding()
        if let session = host.session {
          DaykeeperMessenger(session: session).id(host.customer)
        } else if host.manualTestStart {
          Button("Start isolated fixture") { host.startTestFixture() }
            .accessibilityIdentifier("example.start-fixture")
        } else {
          Text("Configure the isolated debug fixture to open support.").padding()
        }
      }
      .preferredColorScheme(host.dark ? .dark : .light)
      .dynamicTypeSize(host.largeText ? .accessibility1 : .large)
    }
  }
}

@MainActor private final class ExampleHost: ObservableObject {
  @Published var session: DaykeeperMessengerSession?
  @Published var customer = "a"
  let dark = ProcessInfo.processInfo.environment["DAYKEEPER_EXAMPLE_DARK"] == "1"
  let largeText = ProcessInfo.processInfo.environment["DAYKEEPER_EXAMPLE_LARGE_TEXT"] == "1"
  #if DEBUG
    let manualTestStart =
      ProcessInfo.processInfo.environment["DAYKEEPER_EXAMPLE_MANUAL_START"] == "1"
  #else
    let manualTestStart = false
  #endif
  init() {
    if !manualTestStart { configure() }
  }
  func startTestFixture() {
    guard manualTestStart, session == nil else { return }
    configure()
  }
  func switchCustomer() {
    session?.reset()  // Clear the old identity before constructing a new one.
    session = nil
    customer = customer == "a" ? "b" : "a"
    configure()
  }
  private func configure() {
    #if DEBUG
      guard let value = ProcessInfo.processInfo.environment["DAYKEEPER_EXAMPLE_URL"],
        let url = URL(string: value), url.scheme == "http", url.host == "127.0.0.1",
        url.port != nil, url.path.hasPrefix("/cases/"), url.user == nil,
        url.password == nil, url.query == nil, url.fragment == nil
      else { return }
      let token = "fixture-\(customer)"
      guard
        let client = try? DaykeeperClient(baseURL: url, timeout: 3, tokenProvider: { _ in token })
      else { return }
      session = DaykeeperMessengerSession(client: client)
    #endif
  }
}
