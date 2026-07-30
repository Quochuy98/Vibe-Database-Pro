import Foundation

public enum GridFetchState: Equatable, Sendable {
  case idle
  case fetching(requestID: UInt64)
  case cancelRequested(requestID: UInt64)
  case cancelled(requestID: UInt64)
  case completed(requestID: UInt64)
  case failed(requestID: UInt64)

  public var isTerminal: Bool {
    switch self {
    case .cancelled, .completed, .failed:
      true
    case .idle, .fetching, .cancelRequested:
      false
    }
  }
}

public enum GridFetchError: Error, Equatable, Sendable {
  case requestAlreadyInFlight
  case terminalResetRequired
}

/// Owns exactly one synthetic page-fetch task and suppresses values after a
/// cancellation request, even when the supplied operation ignores task
/// cancellation and returns later. This is a grid-side contract only.
public actor GridFetchCoordinator<Value: Sendable> {
  private var nextRequestID: UInt64 = 0
  private var inFlightTask: Task<Value, Error>?
  private var inFlightRequestID: UInt64?
  public private(set) var state: GridFetchState = .idle

  public init() {}

  public func fetch(
    operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    guard inFlightTask == nil else {
      throw GridFetchError.requestAlreadyInFlight
    }
    if state.isTerminal {
      throw GridFetchError.terminalResetRequired
    }

    nextRequestID &+= 1
    let requestID = nextRequestID
    let task = Task { try await operation() }
    inFlightTask = task
    inFlightRequestID = requestID
    state = .fetching(requestID: requestID)

    do {
      let value = try await task.value
      guard inFlightRequestID == requestID else {
        throw CancellationError()
      }
      guard state == .fetching(requestID: requestID) else {
        state = .cancelled(requestID: requestID)
        clearInFlight(requestID: requestID)
        throw CancellationError()
      }
      state = .completed(requestID: requestID)
      clearInFlight(requestID: requestID)
      return value
    } catch is CancellationError {
      if inFlightRequestID == requestID {
        state = .cancelled(requestID: requestID)
        clearInFlight(requestID: requestID)
      }
      throw CancellationError()
    } catch {
      if inFlightRequestID == requestID {
        state = .failed(requestID: requestID)
        clearInFlight(requestID: requestID)
      }
      throw error
    }
  }

  /// Returns after the actor has made `cancelRequested` observable and sent
  /// cancellation to its owned task. Terminal cancellation is reported later.
  @discardableResult
  public func requestCancellation() -> Bool {
    guard let requestID = inFlightRequestID, let task = inFlightTask else {
      return false
    }
    guard state == .fetching(requestID: requestID) else {
      return state == .cancelRequested(requestID: requestID)
    }
    state = .cancelRequested(requestID: requestID)
    task.cancel()
    return true
  }

  public func reset() throws {
    guard inFlightTask == nil else {
      throw GridFetchError.requestAlreadyInFlight
    }
    guard state.isTerminal || state == .idle else {
      throw GridFetchError.terminalResetRequired
    }
    state = .idle
  }

  private func clearInFlight(requestID: UInt64) {
    guard inFlightRequestID == requestID else {
      return
    }
    inFlightTask = nil
    inFlightRequestID = nil
  }
}
