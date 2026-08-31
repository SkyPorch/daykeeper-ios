import Foundation

/// Unlike a task group, this does not wait for an uncooperative token provider
/// after cancellation. The losing work is canceled; late results cannot win.
internal final class RequestLifetime<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var result: Result<Value, Error>?
  private var continuation: CheckedContinuation<Value, Error>?
  private var work: Task<Void, Never>?
  private var timer: Task<Void, Never>?

  static func run(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> Value)
    async throws -> Value
  {
    let lifetime = RequestLifetime()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        lifetime.start(continuation, seconds: seconds, operation: operation)
      }
    } onCancel: {
      lifetime.finish(.failure(DaykeeperError("REQUEST_ABORTED")))
    }
  }

  private func start(
    _ continuation: CheckedContinuation<Value, Error>, seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> Value
  ) {
    lock.lock()
    if let result {
      lock.unlock()
      continuation.resume(with: result)
      return
    }
    self.continuation = continuation
    work = Task {
      do {
        try Task.checkCancellation()
        self.finish(.success(try await operation()))
      } catch { self.finish(.failure(error)) }
    }
    timer = Task {
      do {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        self.finish(.failure(DaykeeperError("REQUEST_TIMEOUT", retryable: true)))
      } catch {
        // Cancellation is the successful cleanup path.
      }
    }
    lock.unlock()
  }

  private func finish(_ result: Result<Value, Error>) {
    lock.lock()
    guard self.result == nil else {
      lock.unlock()
      return
    }
    self.result = result
    let continuation = self.continuation
    let work = self.work
    let timer = self.timer
    self.continuation = nil
    self.work = nil
    self.timer = nil
    lock.unlock()
    work?.cancel()
    timer?.cancel()
    continuation?.resume(with: result)
  }
}

internal final class RequestDispatch: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  var occurred: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
  func mark() {
    lock.lock()
    value = true
    lock.unlock()
  }
}
