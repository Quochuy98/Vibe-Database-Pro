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

  func testEditorRejectsOversizedDocumentReplacementAndAnalysisRange() async throws {
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

  func testNativeTextViewRejectsOversizedReplacementDeletionAndDocumentGrowth() async throws {
    try await MainActor.run {
      let text = String(
        repeating: "x",
        count: TextKit2EditorHarness.maximumReplacementBytes + 1
      )
      let fixture = Self.syntheticFixture(text: text)
      let harness = try TextKit2EditorHarness()
      try harness.load(fixture)
      let baselineLength = harness.documentUTF16Length
      let baselineBytes = harness.documentUTF8Bytes
      let baselineRevision = harness.revision

      harness.textView.insertText(
        String(repeating: "y", count: TextKit2EditorHarness.maximumReplacementBytes + 1),
        replacementRange: NSRange(location: 0, length: 0)
      )
      harness.textView.insertText(
        "",
        replacementRange: NSRange(
          location: 0,
          length: TextKit2EditorHarness.maximumReplacementBytes + 1
        )
      )

      XCTAssertEqual(harness.documentUTF16Length, baselineLength)
      XCTAssertEqual(harness.documentUTF8Bytes, baselineBytes)
      XCTAssertEqual(harness.revision, baselineRevision)

      let atDocumentLimit = Self.syntheticFixture(
        text: "SELECT 1;",
        byteCount: TextKit2EditorHarness.maximumDocumentBytes
      )
      try harness.load(atDocumentLimit)
      let limitRevision = harness.revision
      harness.textView.insertText(
        "z",
        replacementRange: NSRange(location: harness.documentUTF16Length, length: 0)
      )
      XCTAssertEqual(harness.documentUTF16Length, atDocumentLimit.utf16UnitCount)
      XCTAssertEqual(harness.documentUTF8Bytes, TextKit2EditorHarness.maximumDocumentBytes)
      XCTAssertEqual(harness.revision, limitRevision)
    }
  }

  func testNativeTextViewEditInvalidatesAnalysisAndTracksBytesThroughUndo() async throws {
    let fixture = Self.syntheticFixture(text: "SELECT 1;")
    let analyzer = BoundedSQLAnalyzer()
    let harness = try await MainActor.run {
      try TextKit2EditorHarness()
    }
    let snapshot = try await MainActor.run {
      try harness.load(fixture)
      return try harness.analysisSnapshot(
        for: TextSpan(location: 0, length: harness.documentUTF16Length)
      )
    }
    let result = try await analyzer.analyze(snapshot)

    try await MainActor.run {
      let revisionBeforeEdit = harness.revision
      harness.textView.setSelectedRange(NSRange(location: 0, length: 0))
      harness.textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
      XCTAssertEqual(harness.revision, revisionBeforeEdit + 1)
      XCTAssertEqual(harness.documentUTF8Bytes, fixture.byteCount + 1)
      XCTAssertThrowsError(try harness.applyHighlights(result))

      guard let undoManager = harness.textView.undoManager else {
        return XCTFail("Expected delegate-owned undo manager")
      }
      let revisionAfterEdit = harness.revision
      undoManager.undo()
      XCTAssertEqual(harness.revision, revisionAfterEdit + 1)
      XCTAssertEqual(harness.documentUTF8Bytes, fixture.byteCount)
      XCTAssertEqual(harness.documentUTF16Length, fixture.utf16UnitCount)
      XCTAssertTrue(undoManager.canRedo)

      undoManager.redo()
      XCTAssertEqual(harness.revision, revisionAfterEdit + 2)
      XCTAssertEqual(harness.documentUTF8Bytes, fixture.byteCount + 1)
      XCTAssertEqual(harness.documentUTF16Length, fixture.utf16UnitCount + 1)
    }
  }

  func testNativeUndoGroupAggregatesMultipleByteDeltas() async throws {
    let fixture = Self.syntheticFixture(text: "SELECT 1;")
    try await MainActor.run {
      let harness = try TextKit2EditorHarness()
      try harness.load(fixture)
      guard let undoManager = harness.textView.undoManager else {
        return XCTFail("Expected delegate-owned undo manager")
      }
      undoManager.groupsByEvent = false

      let revisionBeforeEdits = harness.revision
      undoManager.beginUndoGrouping()
      harness.textView.insertText(
        "🙂",
        replacementRange: NSRange(location: harness.documentUTF16Length, length: 0)
      )
      harness.textView.insertText(
        "xy",
        replacementRange: NSRange(location: harness.documentUTF16Length, length: 0)
      )
      undoManager.endUndoGrouping()

      XCTAssertEqual(harness.revision, revisionBeforeEdits + 2)
      XCTAssertEqual(harness.documentUTF8Bytes, fixture.byteCount + 6)
      XCTAssertEqual(harness.documentUTF16Length, fixture.utf16UnitCount + 4)

      undoManager.undo()
      XCTAssertEqual(harness.revision, revisionBeforeEdits + 3)
      XCTAssertEqual(harness.documentUTF8Bytes, fixture.byteCount)
      XCTAssertEqual(harness.documentUTF16Length, fixture.utf16UnitCount)

      undoManager.redo()
      XCTAssertEqual(harness.revision, revisionBeforeEdits + 4)
      XCTAssertEqual(harness.documentUTF8Bytes, fixture.byteCount + 6)
      XCTAssertEqual(harness.documentUTF16Length, fixture.utf16UnitCount + 4)
    }
  }

  func testUndoHistoryIsBoundedAndByteTrackingStaysAligned() async throws {
    let fixture = Self.syntheticFixture(text: "x")
    try await MainActor.run {
      let harness = try TextKit2EditorHarness()
      try harness.load(fixture)
      guard let undoManager = harness.textView.undoManager else {
        return XCTFail("Expected delegate-owned undo manager")
      }
      undoManager.groupsByEvent = false
      XCTAssertEqual(undoManager.levelsOfUndo, TextKit2EditorHarness.maximumUndoLevels)

      for _ in 0...TextKit2EditorHarness.maximumUndoLevels {
        undoManager.beginUndoGrouping()
        harness.textView.insertText(
          "a",
          replacementRange: NSRange(location: harness.documentUTF16Length, length: 0)
        )
        undoManager.endUndoGrouping()
      }
      var undoCount = 0
      while undoManager.canUndo {
        undoManager.undo()
        undoCount += 1
      }
      XCTAssertEqual(undoCount, TextKit2EditorHarness.maximumUndoLevels)
      XCTAssertEqual(harness.documentUTF8Bytes, fixture.byteCount + 1)
      XCTAssertEqual(harness.documentUTF16Length, fixture.utf16UnitCount + 1)
    }
  }

  func testDocumentCapAndLargeFilePolicyApplyToEdits() async throws {
    try await MainActor.run {
      let harness = try TextKit2EditorHarness()
      let atLimit = Self.syntheticFixture(
        text: "SELECT 1;",
        byteCount: TextKit2EditorHarness.maximumDocumentBytes
      )
      try harness.load(atLimit)
      XCTAssertThrowsError(try harness.insert("x", at: .end)) { error in
        XCTAssertEqual(
          error as? EditorSpikeError,
          .documentLimitExceeded(
            actualBytes: TextKit2EditorHarness.maximumDocumentBytes + 1,
            maximumBytes: TextKit2EditorHarness.maximumDocumentBytes
          )
        )
      }

      let belowLargeMode = Self.syntheticFixture(
        text: "SELECT 1;",
        byteCount: TextKit2EditorHarness.largeFileThresholdBytes - 1
      )
      try harness.load(belowLargeMode)
      XCTAssertEqual(harness.featurePolicy.mode, .standard)
      _ = try harness.insert("xx", at: .end)
      XCTAssertEqual(harness.featurePolicy.mode, .largeFile)
      XCTAssertTrue(
        harness.accessibilitySnapshot().help.contains(
          TextKit2EditorHarness.largeFileAccessibilityStatus
        )
      )
      harness.undo()
      XCTAssertEqual(harness.featurePolicy.mode, .standard)
    }
  }

  func testHighlightApplicationRejectsUnboundedAndOutOfEnvelopeResults() async throws {
    let fixture = Self.syntheticFixture(text: "SELECT 1;")
    try await MainActor.run {
      let harness = try TextKit2EditorHarness()
      try harness.load(fixture)
      let envelope = TextSpan(location: 0, length: fixture.utf16UnitCount)
      let tooMany = AnalysisResult(
        analyzedSpan: envelope,
        keywordSpans: Array(
          repeating: TextSpan(location: 0, length: 1),
          count: AnalysisLimits.maximumAllowedMatches + 1
        ),
        revision: harness.revision,
        inputUTF16Units: envelope.length,
        hitOutputLimit: true
      )
      XCTAssertThrowsError(try harness.applyHighlights(tooMany)) { error in
        XCTAssertEqual(
          error as? EditorSpikeError,
          .analysisOutputLimitExceeded(
            actualMatches: AnalysisLimits.maximumAllowedMatches + 1,
            maximumMatches: AnalysisLimits.maximumAllowedMatches
          )
        )
      }

      let mismatchedLength = AnalysisResult(
        analyzedSpan: envelope,
        keywordSpans: [],
        revision: harness.revision,
        inputUTF16Units: envelope.length - 1,
        hitOutputLimit: false
      )
      XCTAssertThrowsError(try harness.applyHighlights(mismatchedLength)) { error in
        XCTAssertEqual(
          error as? EditorSpikeError,
          .analysisLengthMismatch(
            reportedUTF16Units: envelope.length - 1,
            actualUTF16Units: envelope.length
          )
        )
      }

      let outside = TextSpan(location: envelope.upperBound, length: 1)
      let outOfEnvelope = AnalysisResult(
        analyzedSpan: envelope,
        keywordSpans: [outside],
        revision: harness.revision,
        inputUTF16Units: envelope.length,
        hitOutputLimit: false
      )
      XCTAssertThrowsError(try harness.applyHighlights(outOfEnvelope)) { error in
        XCTAssertEqual(error as? EditorSpikeError, .analysisSpanOutsideAnalyzedRange(outside))
      }
    }
  }

  #if DEBUG
    func testFallbackObserverPositiveControl() async throws {
      try await MainActor.run {
        let harness = try TextKit2EditorHarness()
        XCTAssertEqual(harness.textKit1FallbackCount, 0)
        XCTAssertTrue(harness.intentionallyTriggerTextKit1FallbackForObserverTest())
        XCTAssertGreaterThan(harness.textKit1FallbackCount, 0)
        XCTAssertFalse(harness.usesTextKit2)
      }
    }
  #endif

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
    let baselineBytes = harness.documentUTF8Bytes
    for position in EditPosition.allCases {
      _ = try harness.prepareViewport(for: position)
      let marker = "/* BF01_\(position.rawValue)_EDIT */"
      let inserted = try harness.insert(marker, at: position)
      XCTAssertEqual(try harness.text(in: inserted), marker)
      XCTAssertEqual(
        harness.documentUTF16Length,
        baselineLength + (marker as NSString).length
      )
      XCTAssertEqual(harness.documentUTF8Bytes, baselineBytes + marker.utf8.count)

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
      XCTAssertEqual(harness.documentUTF8Bytes, baselineBytes)
      XCTAssertTrue(harness.canRedo)
      harness.redo()
      XCTAssertEqual(
        harness.documentUTF16Length,
        baselineLength + (marker as NSString).length
      )
      harness.undo()
      XCTAssertEqual(harness.documentUTF16Length, baselineLength)
      XCTAssertEqual(harness.documentUTF8Bytes, baselineBytes)
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

  private static func syntheticFixture(
    text: String,
    byteCount: Int? = nil
  ) -> BF01Fixture {
    let utf16Length = (text as NSString).length
    return BF01Fixture(
      text: text,
      byteCount: byteCount ?? text.utf8.count,
      utf16UnitCount: utf16Length,
      lineCount: 1,
      statementCount: 1,
      findNeedleSpan: TextSpan(location: 0, length: 0),
      nearEndNeedleSpan: TextSpan(location: utf16Length, length: 0),
      fingerprint: "synthetic-test-only"
    )
  }
}
