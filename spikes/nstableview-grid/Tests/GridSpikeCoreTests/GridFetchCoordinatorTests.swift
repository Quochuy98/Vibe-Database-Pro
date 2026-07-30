import XCTest

@testable import GridSpikeCore

private actor SuspensionGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else {
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func open() {
    guard !isOpen else {
      return
    }
    isOpen = true
    let pending = waiters
    waiters.removeAll(keepingCapacity: false)
    for waiter in pending {
      waiter.resume()
    }
  }
}

final class GridFetchCoordinatorTests: XCTestCase {
  func testSuccessfulFetchRequiresTerminalResetBeforeReuse() async throws {
    let coordinator = GridFetchCoordinator<String>()
    let value = try await coordinator.fetch { "page" }
    XCTAssertEqual(value, "page")

    let completedState = await coordinator.state
    XCTAssertEqual(completedState, .completed(requestID: 1))

    do {
      _ = try await coordinator.fetch { "second" }
      XCTFail("Expected terminal reset requirement")
    } catch let error as GridFetchError {
      XCTAssertEqual(error, .terminalResetRequired)
    }

    try await coordinator.reset()
    let second = try await coordinator.fetch { "second" }
    XCTAssertEqual(second, "second")
    let secondState = await coordinator.state
    XCTAssertEqual(secondState, .completed(requestID: 2))
  }

  func testCancellationAcknowledgesBeforeTerminalAndSuppressesLateValue() async throws {
    let coordinator = GridFetchCoordinator<String>()
    let started = SuspensionGate()
    let release = SuspensionGate()

    let fetchTask = Task {
      try await coordinator.fetch {
        await started.open()
        await release.wait()
        // Deliberately return despite cancellation. The coordinator must
        // suppress this late value at its admission boundary.
        return "late page"
      }
    }

    await started.wait()
    let acknowledged = await coordinator.requestCancellation()
    let requestedState = await coordinator.state
    XCTAssertTrue(acknowledged)
    XCTAssertEqual(requestedState, .cancelRequested(requestID: 1))

    await release.open()
    do {
      _ = try await fetchTask.value
      XCTFail("Expected late value to be suppressed")
    } catch is CancellationError {
      // Expected controlled terminal outcome.
    }

    let terminalState = await coordinator.state
    XCTAssertEqual(terminalState, .cancelled(requestID: 1))
  }

  func testSecondConcurrentRequestIsRejected() async throws {
    let coordinator = GridFetchCoordinator<String>()
    let started = SuspensionGate()
    let release = SuspensionGate()
    let firstTask = Task {
      try await coordinator.fetch {
        await started.open()
        await release.wait()
        return "first"
      }
    }

    await started.wait()
    do {
      _ = try await coordinator.fetch { "second" }
      XCTFail("Expected in-flight request rejection")
    } catch let error as GridFetchError {
      XCTAssertEqual(error, .requestAlreadyInFlight)
    }

    await release.open()
    let first = try await firstTask.value
    XCTAssertEqual(first, "first")
  }
}
