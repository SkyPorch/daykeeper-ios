import Foundation

internal struct HTTPPayload: Sendable {
  let status: Int
  let data: Data
}

/// One ephemeral session per attempt. No shared cookie, credential or cache
/// store; delegate callbacks bound decoded body size before buffering it.
internal final class HTTPTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  static let maximumBytes = 1_048_576
  private let lock = NSLock()
  private var continuation: CheckedContinuation<HTTPPayload, Error>?
  private var terminal: Result<HTTPPayload, Error>?
  private var session: URLSession?
  private var task: URLSessionDataTask?
  private var response: HTTPURLResponse?
  private var data = Data()

  func perform(
    _ request: URLRequest, dispatch: RequestDispatch,
    protocolClasses: [AnyClass]? = nil
  ) async throws -> HTTPPayload {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        start(
          request, dispatch: dispatch, protocolClasses: protocolClasses, continuation: continuation)
      }
    } onCancel: {
      self.finish(.failure(DaykeeperError("REQUEST_ABORTED")))
    }
  }

  private func start(
    _ request: URLRequest, dispatch: RequestDispatch, protocolClasses: [AnyClass]?,
    continuation: CheckedContinuation<HTTPPayload, Error>
  ) {
    lock.lock()
    if let terminal {
      lock.unlock()
      continuation.resume(with: terminal)
      return
    }
    self.continuation = continuation
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.httpShouldSetCookies = false
    config.urlCredentialStorage = nil
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    config.timeoutIntervalForRequest = request.timeoutInterval
    config.timeoutIntervalForResource = request.timeoutInterval
    config.waitsForConnectivity = false
    config.httpShouldUsePipelining = false
    if let protocolClasses { config.protocolClasses = protocolClasses }
    let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    let task = session.dataTask(with: request)
    self.session = session
    self.task = task
    dispatch.mark()
    task.resume()
    lock.unlock()
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    guard let http = response as? HTTPURLResponse else {
      completionHandler(.cancel)
      finish(.failure(DaykeeperError("INVALID_RESPONSE")))
      return
    }
    guard response.expectedContentLength <= Self.maximumBytes else {
      completionHandler(.cancel)
      finish(.failure(DaykeeperError("RESPONSE_TOO_LARGE")))
      return
    }
    lock.lock()
    self.response = http
    let stopped = terminal != nil
    lock.unlock()
    completionHandler(stopped ? .cancel : .allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data) {
    lock.lock()
    guard terminal == nil else {
      lock.unlock()
      return
    }
    guard bytes.count <= Self.maximumBytes - data.count else {
      lock.unlock()
      finish(.failure(DaykeeperError("RESPONSE_TOO_LARGE")))
      return
    }
    data.append(bytes)
    lock.unlock()
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    lock.lock()
    let payload = response.map { HTTPPayload(status: $0.statusCode, data: data) }
    lock.unlock()
    if let error {
      let code: String
      switch (error as? URLError)?.code {
      case .timedOut: code = "REQUEST_TIMEOUT"
      case .cancelled: code = "REQUEST_ABORTED"
      default: code = "NETWORK_ERROR"
      }
      finish(.failure(DaykeeperError(code, retryable: code != "REQUEST_ABORTED")))
    } else if let payload {
      finish(.success(payload))
    } else {
      finish(.failure(DaykeeperError("INVALID_RESPONSE", retryable: true)))
    }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
    finish(.failure(DaykeeperError("REDIRECT_REJECTED")))
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask,
    willCacheResponse proposedResponse: CachedURLResponse,
    completionHandler: @escaping @Sendable (CachedURLResponse?) -> Void
  ) {
    completionHandler(nil)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    // System certificate validation only. Never satisfy HTTP/NTLM/client-
    // certificate challenges using ambient credentials or weaken TLS trust.
    completionHandler(
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
        ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
  }

  private func finish(_ result: Result<HTTPPayload, Error>) {
    lock.lock()
    guard terminal == nil else {
      lock.unlock()
      return
    }
    terminal = result
    let continuation = self.continuation
    let session = self.session
    self.continuation = nil
    self.session = nil
    self.task = nil
    self.response = nil
    self.data = Data()
    lock.unlock()
    session?.invalidateAndCancel()
    continuation?.resume(with: result)
  }
}
