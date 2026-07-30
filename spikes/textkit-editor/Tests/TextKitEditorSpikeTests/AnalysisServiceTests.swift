import Foundation
import XCTest

@testable import TextKitEditorSpike

final class AnalysisServiceTests: XCTestCase {
  func testAnalysisIsBoundedAndFindsOnlyWholeKeywords() async throws {
    let analyzer = BoundedSQLAnalyzer(
      limits: AnalysisLimits(
        maximumUTF16Units: 128,
        maximumMatches: 2,
        cancellationCheckStride: 4
      )
    )
    let text = "SELECT selection FROM table_name WHERE value = 1; UPDATE table_name SET value = 2;"
    let snapshot = AnalysisSnapshot(
      text: text,
      documentSpan: TextSpan(location: 40, length: (text as NSString).length),
      revision: 7
    )

    let result = try await analyzer.analyze(snapshot)

    XCTAssertEqual(result.keywordSpans.count, 2)
    XCTAssertEqual(result.keywordSpans[0], TextSpan(location: 40, length: 6))
    XCTAssertEqual(result.keywordSpans[1], TextSpan(location: 57, length: 4))
    XCTAssertTrue(result.hitOutputLimit)
    XCTAssertEqual(result.revision, 7)
  }

  func testAnalysisRejectsInputOverViewportCap() async {
    let analyzer = BoundedSQLAnalyzer(
      limits: AnalysisLimits(
        maximumUTF16Units: 32,
        maximumMatches: 4,
        cancellationCheckStride: 4
      )
    )
    let text = String(repeating: "S", count: 33)
    let snapshot = AnalysisSnapshot(
      text: text,
      documentSpan: TextSpan(location: 0, length: 33),
      revision: 1
    )

    do {
      _ = try await analyzer.analyze(snapshot)
      XCTFail("Expected analysis limit failure")
    } catch let error as EditorSpikeError {
      XCTAssertEqual(
        error,
        .analysisLimitExceeded(actualUTF16Units: 33, maximumUTF16Units: 32)
      )
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testAnalysisRejectsMismatchedDocumentSpan() async {
    let analyzer = BoundedSQLAnalyzer()
    let snapshot = AnalysisSnapshot(
      text: "SELECT 1",
      documentSpan: TextSpan(location: 10, length: 1),
      revision: 1
    )

    do {
      _ = try await analyzer.analyze(snapshot)
      XCTFail("Expected invalid range")
    } catch let error as EditorSpikeError {
      XCTAssertEqual(error, .invalidRange(snapshot.documentSpan))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testFindValidatesLimitsAndChunkBoundary() async throws {
    let finder = IncrementalFindService(
      limits: FindLimits(
        maximumDocumentUTF16Units: 64,
        maximumNeedleUTF16Units: 8,
        searchChunkUTF16Units: 8
      )
    )
    let document = "1234567BOUNDARY-tail"
    let found = try await finder.firstRange(in: document, needle: "BOUNDARY")
    XCTAssertEqual(found, TextSpan(location: 7, length: 8))

    do {
      _ = try await finder.firstRange(in: document, needle: "")
      XCTFail("Expected empty needle failure")
    } catch let error as EditorSpikeError {
      XCTAssertEqual(error, .emptyFindNeedle)
    }

    do {
      _ = try await finder.firstRange(in: String(repeating: "x", count: 65), needle: "x")
      XCTFail("Expected document limit failure")
    } catch let error as EditorSpikeError {
      XCTAssertEqual(
        error,
        .findDocumentLimitExceeded(actualUTF16Units: 65, maximumUTF16Units: 64)
      )
    }
  }

  func testBoundedFindMatchesFoundationForUnicodeAndOverlaps() async throws {
    let finder = IncrementalFindService(
      limits: FindLimits(
        maximumDocumentUTF16Units: 128,
        maximumNeedleUTF16Units: 16,
        searchChunkUTF16Units: 3
      )
    )
    let cases = [
      ("aaaaab", "aaab"),
      ("12東京34東京", "東京"),
      ("prefix-🙂-suffix", "🙂-s"),
      ("abcdef", "not-there"),
      ("single", "s"),
    ]

    for (document, needle) in cases {
      let expectedRange = (document as NSString).range(of: needle)
      let expected =
        expectedRange.location == NSNotFound
        ? nil
        : TextSpan(location: expectedRange.location, length: expectedRange.length)
      let actual = try await finder.firstRange(in: document, needle: needle)
      XCTAssertEqual(actual, expected, "document=\(document), needle=\(needle)")
    }
  }

  func testStructuredCancellationStopsAnalysis() async throws {
    let analyzer = BoundedSQLAnalyzer(
      limits: AnalysisLimits(
        maximumUTF16Units: 65_536,
        maximumMatches: 1_024,
        cancellationCheckStride: 1
      )
    )
    let text = String(repeating: "SELECT value FROM table_name WHERE value = 1; ", count: 1_300)
    let snapshot = AnalysisSnapshot(
      text: text,
      documentSpan: TextSpan(location: 0, length: (text as NSString).length),
      revision: 1
    )

    let observedCancellation = try await withThrowingTaskGroup(of: Bool.self) { group in
      group.addTask {
        do {
          _ = try await analyzer.analyze(snapshot)
          return false
        } catch is CancellationError {
          return true
        }
      }
      try await Task.sleep(for: .milliseconds(1))
      group.cancelAll()
      return try await group.next() ?? false
    }

    XCTAssertTrue(observedCancellation)
  }

  func testStructuredCancellationStopsIncrementalFind() async throws {
    let finder = IncrementalFindService(
      limits: FindLimits(
        maximumDocumentUTF16Units: 4 * 1_024 * 1_024,
        maximumNeedleUTF16Units: 64,
        searchChunkUTF16Units: 1_024
      )
    )
    let document = String(repeating: "x", count: 4 * 1_024 * 1_024)

    let observedCancellation = try await withThrowingTaskGroup(of: Bool.self) { group in
      group.addTask {
        do {
          _ = try await finder.firstRange(in: document, needle: "not-present")
          return false
        } catch is CancellationError {
          return true
        }
      }
      try await Task.sleep(for: .milliseconds(1))
      group.cancelAll()
      return try await group.next() ?? false
    }

    XCTAssertTrue(observedCancellation)
  }
}
