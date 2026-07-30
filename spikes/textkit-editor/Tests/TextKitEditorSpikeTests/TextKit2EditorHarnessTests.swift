import AppKit
import Foundation
import XCTest

@testable import TextKitEditorSpike

final class TextKit2EditorHarnessTests: XCTestCase {
  func testBF01TenAndHundredMiBEditorMatrix() async throws {
    for size in BF01Size.allCases {
      let fixture = try BF01FixtureGenerator.make(size: size)
      try await Self.exerciseEditor(fixture: fixture, expectedSize: size)
    }
  }

  func testStaleVisibleAnalysisCannotDecorateNewRevision() async throws {
    let fixture = try BF01FixtureGenerator.make(size: .tenMiB)
    let analyzer = BoundedSQLAnalyzer()
    let harness = try await MainActor.run {
      try TextKit2EditorHarness()
    }
    let snapshot = try await MainActor.run {
      try harness.load(fixture)
      let span = try harness.visibleSpan(around: fixture.findNeedleSpan.location)
      return try harness.analysisSnapshot(for: span)
    }
    let result = try await analyzer.analyze(snapshot)

    try await MainActor.run {
      _ = try harness.insert("-- edit\n", at: .start)
      XCTAssertThrowsError(try harness.applyHighlights(result)) { error in
        guard case EditorSpikeError.staleAnalysis = error else {
          return XCTFail("Expected staleAnalysis, received \(error)")
        }
      }
    }
  }

  func testEditorRejectsOversizedDocumentReplacementAndRange() async throws {
    let text = "SELECT 1;"
    let fixture = BF01Fixture(
      text: text,
      byteCount: text.utf8.count,
      utf16UnitCount: (text as NSString).length,
      lineCount: 1,
      statementCount: 1,
      findNeedleSpan: TextSpan(location: 0, length: 0),
      nearEndNeedleSpan: TextSpan(location: 0, length: 0),
      fingerprint: "synthetic-test-only"
    )
    try await MainActor.run {
      let harness = try TextKit2EditorHarness()
      let oversizedFixture = BF01Fixture(
        text: text,
        byteCount: TextKit2EditorHarness.maximumDocumentBytes + 1,
        utf16UnitCount: (text as NSString).length,
        lineCount: 1,
        statementCount: 1,
        findNeedleSpan: TextSpan(location: 0, length: 0),
        nearEndNeedleSpan: TextSpan(location: 0, length: 0),
        fingerprint: "synthetic-test-only"
      )
      XCTAssertThrowsError(try harness.load(oversizedFixture))
      try harness.load(fixture)
      XCTAssertThrowsError(
        try harness.insert(
          String(repeating: "x", count: TextKit2EditorHarness.maximumReplacementBytes + 1),
          at: .start
        )
      )
      XCTAssertThrowsError(
        try harness.analysisSnapshot(for: TextSpan(location: 0, length: text.count + 1))
      )
    }
  }

  @MainActor
  private static func exerciseEditor(fixture: BF01Fixture, expectedSize: BF01Size) async throws {
    let harness = try TextKit2EditorHarness()
    let analyzer = BoundedSQLAnalyzer()
    let finder = IncrementalFindService()

    try harness.load(fixture)
    switch expectedSize {
    case .tenMiB:
      XCTAssertEqual(fixture.byteCount, 10_485_760)
      XCTAssertEqual(fixture.utf16UnitCount, 10_210_760)
      XCTAssertEqual(fixture.lineCount, 101_045)
      XCTAssertEqual(
        fixture.fingerprint,
        "b31912ef23f60bfbfa002626cbd17410d7923b1765e8f1907c0a86c2a8488e56"
      )
    case .oneHundredMiB:
      XCTAssertEqual(fixture.byteCount, 104_857_600)
      XCTAssertEqual(fixture.utf16UnitCount, 104_582_600)
      XCTAssertEqual(fixture.lineCount, 123_889)
      XCTAssertEqual(
        fixture.fingerprint,
        "f21ca93f425d02f5526b44b36ac2e9048bd1bf2e200d5a9b18665d50fdf88ffb"
      )
    }
    XCTAssertTrue(harness.usesTextKit2)
    XCTAssertEqual(harness.textKit1FallbackCount, 0)
    XCTAssertEqual(harness.documentUTF16Length, fixture.utf16UnitCount)
    XCTAssertEqual(
      harness.featurePolicy.mode,
      expectedSize == .oneHundredMiB ? .largeFile : .standard
    )
    if expectedSize == .oneHundredMiB {
      XCTAssertFalse(harness.featurePolicy.foldingEnabled)
      XCTAssertFalse(harness.featurePolicy.semanticCompletionEnabled)
      XCTAssertEqual(
        harness.featurePolicy.accessibilityStatus,
        TextKit2EditorHarness.largeFileAccessibilityStatus
      )
    }

    let accessibility = harness.accessibilitySnapshot()
    XCTAssertEqual(accessibility.label, TextKit2EditorHarness.accessibilityLabel)
    XCTAssertEqual(accessibility.role, NSAccessibility.Role.textArea.rawValue)
    XCTAssertTrue(accessibility.help.contains(harness.featurePolicy.accessibilityStatus))
    XCTAssertTrue(accessibility.isEditable)
    XCTAssertTrue(accessibility.isFocused)
    XCTAssertEqual(accessibility.selectedSpan, TextSpan(location: 0, length: 0))
    XCTAssertEqual(accessibility.selectedText, "")

    let baselineLength = harness.documentUTF16Length
    for position in EditPosition.allCases {
      _ = try harness.prepareViewport(for: position)
      let marker = "/* BF01_\(position.rawValue)_EDIT */"
      let inserted = try harness.insert(marker, at: position)
      XCTAssertEqual(try harness.text(in: inserted), marker)
      XCTAssertEqual(
        harness.documentUTF16Length,
        baselineLength + (marker as NSString).length
      )

      let visible = try harness.visibleSpan(around: inserted.location, requestedLength: 32_768)
      let snapshot = try harness.analysisSnapshot(for: visible)
      let result = try await analyzer.analyze(snapshot)
      try harness.applyHighlights(result)
      XCTAssertEqual(result.analyzedSpan, visible)
      XCTAssertLessThanOrEqual(
        result.inputUTF16Units,
        AnalysisLimits.viewportDefault.maximumUTF16Units
      )
      XCTAssertEqual(harness.decoratedSpans, result.keywordSpans)
      XCTAssertTrue(
        harness.decoratedSpans.allSatisfy {
          $0.location >= visible.location && $0.upperBound <= visible.upperBound
        }
      )

      harness.restoreRecoveryState(EditorRecoveryState(selectedSpan: inserted))
      let selectedAccessibility = harness.accessibilitySnapshot()
      XCTAssertEqual(selectedAccessibility.selectedSpan, inserted)
      XCTAssertEqual(selectedAccessibility.selectedText, marker)

      XCTAssertTrue(harness.canUndo)
      harness.undo()
      XCTAssertEqual(harness.documentUTF16Length, baselineLength)
      XCTAssertTrue(harness.canRedo)
      harness.redo()
      XCTAssertEqual(
        harness.documentUTF16Length,
        baselineLength + (marker as NSString).length
      )
      harness.undo()
      XCTAssertEqual(harness.documentUTF16Length, baselineLength)
    }

    let found = try await finder.firstRange(
      in: fixture.text,
      needle: BF01Fixture.findNeedle
    )
    XCTAssertEqual(found, fixture.findNeedleSpan)
    let nearEndFound = try await finder.firstRange(
      in: fixture.text,
      needle: BF01Fixture.nearEndNeedle
    )
    XCTAssertEqual(nearEndFound, fixture.nearEndNeedleSpan)
    let absent = try await finder.firstRange(
      in: fixture.text,
      needle: "BF01_ABSENT_RESULT_00000000"
    )
    XCTAssertNil(absent)

    XCTAssertTrue(harness.performKeyboardSelector(.moveToEndOfDocument))
    XCTAssertEqual(harness.selectedSpan.location, harness.documentUTF16Length)
    let recovery = harness.captureRecoveryState()
    XCTAssertTrue(harness.performKeyboardSelector(.moveToBeginningOfDocument))
    XCTAssertEqual(harness.selectedSpan.location, 0)
    harness.restoreRecoveryState(recovery)
    XCTAssertEqual(harness.selectedSpan, recovery.selectedSpan)
    try harness.forceViewportDisplay(around: recovery.selectedSpan)
    XCTAssertTrue(harness.usesTextKit2)
    XCTAssertEqual(harness.textKit1FallbackCount, 0)
  }
}
