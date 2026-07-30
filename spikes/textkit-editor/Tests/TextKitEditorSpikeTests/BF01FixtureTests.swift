import Foundation
import XCTest

@testable import TextKitEditorSpike

final class BF01FixtureTests: XCTestCase {
  func testTenMiBFixtureIsExactDeterministicAndRepresentative() throws {
    let first = try BF01FixtureGenerator.make(size: .tenMiB)
    let second = try BF01FixtureGenerator.make(size: .tenMiB)

    XCTAssertEqual(first.byteCount, 10 * 1_024 * 1_024)
    XCTAssertEqual(first.text.utf8.count, first.byteCount)
    XCTAssertEqual(first.utf16UnitCount, (first.text as NSString).length)
    XCTAssertGreaterThan(first.lineCount, first.statementCount)
    XCTAssertEqual(first.statementCount, 100_000)
    XCTAssertEqual(BF01Fixture.generatorRevision, 1)
    XCTAssertEqual(first.fingerprint.count, 64)
    XCTAssertEqual(
      first.fingerprint,
      "b31912ef23f60bfbfa002626cbd17410d7923b1765e8f1907c0a86c2a8488e56"
    )
    XCTAssertEqual(first.fingerprint, second.fingerprint)
    XCTAssertEqual(first.findNeedleSpan, second.findNeedleSpan)
    XCTAssertEqual(first.nearEndNeedleSpan, second.nearEndNeedleSpan)
    XCTAssertEqual(
      (first.text as NSString).substring(with: first.findNeedleSpan.nsRange),
      BF01Fixture.findNeedle
    )
    XCTAssertEqual(
      (first.text as NSString).substring(with: first.nearEndNeedleSpan.nsRange),
      BF01Fixture.nearEndNeedle
    )
    XCTAssertLessThan(first.findNeedleSpan.location, first.nearEndNeedleSpan.location)
    XCTAssertLessThan(first.utf16UnitCount - first.nearEndNeedleSpan.location, 8_192)
    XCTAssertTrue(first.text.contains("`mysql_table`"))
    XCTAssertTrue(first.text.contains("DO $bf$"))
    XCTAssertTrue(first.text.contains("intentional syntax error"))
    XCTAssertTrue(first.text.contains("東京"))
    XCTAssertTrue(first.text.contains(String(repeating: "x", count: 4_096)))
  }

  func testFixtureRejectsTargetTooSmallForRequiredStatements() {
    XCTAssertThrowsError(try BF01FixtureGenerator.make(targetBytes: 1_024)) { error in
      guard case EditorSpikeError.fixtureCannotFit = error else {
        return XCTFail("Expected fixtureCannotFit, received \(error)")
      }
    }
  }

  func testFixtureRejectsUnboundedTargetBeforeAllocation() {
    XCTAssertThrowsError(
      try BF01FixtureGenerator.make(
        targetBytes: BF01FixtureGenerator.maximumTargetBytes + 1
      )
    ) { error in
      XCTAssertEqual(
        error as? EditorSpikeError,
        .documentLimitExceeded(
          actualBytes: BF01FixtureGenerator.maximumTargetBytes + 1,
          maximumBytes: BF01FixtureGenerator.maximumTargetBytes
        )
      )
    }
  }
}
