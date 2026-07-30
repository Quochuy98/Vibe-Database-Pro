import XCTest

@testable import GridSpikeCore

final class PendingEditOverlayTests: XCTestCase {
  private struct Value: Equatable, Sendable {
    let text: String
  }

  func testAdmissionReplacementStaleAndRollback() async throws {
    let limits = try PendingEditLimits(maximumCells: 2, maximumBytes: 100)
    let overlay = PendingEditOverlay<String, Value>(limits: limits) { edit in
      edit.originalValue.text.utf8.count + edit.proposedValue.text.utf8.count
    }
    let first = PendingEdit(
      originalValue: Value(text: "old"),
      proposedValue: Value(text: "new"),
      sourceVersion: 7
    )
    try await overlay.set(first, for: "row-1/column-1")

    let replacement = PendingEdit(
      originalValue: Value(text: "old"),
      proposedValue: Value(text: "newer"),
      sourceVersion: 7
    )
    try await overlay.set(replacement, for: "row-1/column-1")
    var inventory = await overlay.inventory()
    XCTAssertEqual(inventory.cellCount, 1)

    let markedStale = await overlay.markStale("row-1/column-1")
    XCTAssertTrue(markedStale)
    let stale = await overlay.edit(for: "row-1/column-1")
    XCTAssertEqual(stale?.state, .stale)

    let rolledBack = await overlay.rollback("row-1/column-1")
    XCTAssertEqual(rolledBack?.proposedValue.text, "newer")
    inventory = await overlay.inventory()
    XCTAssertEqual(inventory.cellCount, 0)
    XCTAssertEqual(inventory.byteCount, 0)
  }

  func testOverCapacityRejectsNewEditWithoutDiscardingExistingEdit() async throws {
    let limits = try PendingEditLimits(maximumCells: 1, maximumBytes: 10)
    let overlay = PendingEditOverlay<String, Value>(limits: limits) { edit in
      edit.originalValue.text.utf8.count + edit.proposedValue.text.utf8.count
    }
    let retained = PendingEdit(
      originalValue: Value(text: "a"),
      proposedValue: Value(text: "b"),
      sourceVersion: 1
    )
    try await overlay.set(retained, for: "retained")

    do {
      try await overlay.set(retained, for: "rejected")
      XCTFail("Expected cell ceiling rejection")
    } catch let error as PendingEditError {
      XCTAssertEqual(
        error,
        .capacityExceeded(
          attemptedCells: 2,
          maximumCells: 1,
          attemptedBytes: 4,
          maximumBytes: 10
        )
      )
    }

    let retainedAfterFailure = await overlay.edit(for: "retained")
    let rejectedAfterFailure = await overlay.edit(for: "rejected")
    let inventory = await overlay.inventory()
    XCTAssertEqual(retainedAfterFailure?.proposedValue.text, "b")
    XCTAssertNil(rejectedAfterFailure)
    XCTAssertEqual(inventory.rejectedAdmissionCount, 1)
  }

  func testOversizedReplacementPreservesPreviousValue() async throws {
    let limits = try PendingEditLimits(maximumCells: 1, maximumBytes: 8)
    let overlay = PendingEditOverlay<String, Value>(limits: limits) { edit in
      edit.originalValue.text.utf8.count + edit.proposedValue.text.utf8.count
    }
    let retained = PendingEdit(
      originalValue: Value(text: "a"),
      proposedValue: Value(text: "b"),
      sourceVersion: 1
    )
    try await overlay.set(retained, for: "cell")

    let tooLarge = PendingEdit(
      originalValue: Value(text: "original"),
      proposedValue: Value(text: "replacement"),
      sourceVersion: 1
    )
    do {
      try await overlay.set(tooLarge, for: "cell")
      XCTFail("Expected byte ceiling rejection")
    } catch let error as PendingEditError {
      XCTAssertEqual(
        error,
        .capacityExceeded(
          attemptedCells: 1,
          maximumCells: 1,
          attemptedBytes: 19,
          maximumBytes: 8
        )
      )
    }

    let valueAfterFailure = await overlay.edit(for: "cell")
    XCTAssertEqual(valueAfterFailure?.proposedValue.text, "b")
  }
}
