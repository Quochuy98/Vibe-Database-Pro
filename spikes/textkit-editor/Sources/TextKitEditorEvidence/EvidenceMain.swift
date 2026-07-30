import Foundation
import TextKitEditorSpike

// Keep this file distinct from main.swift so both SwiftPM and generated Xcode schemes
// compile the @main entry point with the same semantics.

private struct LatencySummary: Codable, Sendable {
  let medianMilliseconds: Double
  let p95Milliseconds: Double
  let worstMilliseconds: Double
  let samples: Int
  let rawMilliseconds: [Double]

  init(_ values: [Double]) {
    let sorted = values.sorted()
    samples = sorted.count
    rawMilliseconds = values
    if sorted.isEmpty {
      medianMilliseconds = 0
      p95Milliseconds = 0
      worstMilliseconds = 0
    } else {
      let p95Index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)
      if sorted.count.isMultiple(of: 2) {
        let upperMiddle = sorted.count / 2
        medianMilliseconds = (sorted[upperMiddle - 1] + sorted[upperMiddle]) / 2
      } else {
        medianMilliseconds = sorted[sorted.count / 2]
      }
      p95Milliseconds = sorted[p95Index]
      worstMilliseconds = sorted[sorted.count - 1]
    }
  }
}

private struct PositionEvidence: Codable, Sendable {
  let position: String
  let viewportPreparation: LatencySummary
  let editAndForcedLocalLayout: LatencySummary
}

private struct FindScenarioEvidence: Codable, Sendable {
  let scenario: String
  let expectedLocation: Int?
  let observedLocation: Int?
  let latency: LatencySummary
}

private struct BudgetEvidence: Codable, Sendable {
  let editProxyP95TargetMilliseconds: Double
  let editProxyP95WithinTarget: Bool
  let inputToPaintEstablished: Bool
  let findResultP95TargetMilliseconds: Double
  let findResultP95WithinTarget: Bool
  let analysisCancellationTargetMilliseconds: Double
  let analysisCancellationObservedWithinTarget: Bool
  let analysisWorkerStartEstablished: Bool
  let findCancellationTargetMilliseconds: Double
  let findCancellationObservedWithinTarget: Bool
  let findWorkerStartEstablished: Bool
  let viewportPreparationTargetMilliseconds: Double
  let viewportPreparationWithinTarget: Bool
  let largeFileModeRequired: Bool
  let largeFileModeActivated: Bool
  let largeFileModePolicyPassed: Bool
  let note: String
}

private struct EvidenceReport: Codable, Sendable {
  let schemaVersion: Int
  let fixture: String
  let fixtureBytes: Int
  let fixtureUTF16Units: Int
  let fixtureLines: Int
  let fixtureStatements: Int
  let fixtureGeneratorRevision: Int
  let fixtureFingerprint: String
  let operatingSystem: String
  let processorCount: Int
  let physicalMemoryBytes: UInt64
  let sampleCount: Int
  let generationMilliseconds: Double
  let textKit2Load: LatencySummary
  let edits: [PositionEvidence]
  let visibleAnalysis: LatencySummary
  let visibleHighlightAndLayout: LatencySummary
  let highlightedKeywordCount: Int
  let highlightOutputLimitReached: Bool
  let analysisCancellation: LatencySummary
  let analysisCancellationObserved: Bool
  let findCancellation: LatencySummary
  let findCancellationObserved: Bool
  let findResultWorstP95Milliseconds: Double
  let findScenarios: [FindScenarioEvidence]
  let undo: LatencySummary
  let redo: LatencySummary
  let keyboardSelectorSmokePassed: Bool
  let keyEquivalentRoutingEstablished: Bool
  let accessibilityMetadataSmokePassed: Bool
  let manualVoiceOverEstablished: Bool
  let inMemorySelectionRestorePassed: Bool
  let durableCrashRecoveryEstablished: Bool
  let usesTextKit2: Bool
  let textKit1FallbackCount: Int
  let mode: String
  let modeAccessibilityStatus: String
  let budget: BudgetEvidence
}

private enum EvidenceError: Error, CustomStringConvertible {
  case invalidArguments(String)
  case invariantFailed(String)

  var description: String {
    switch self {
    case .invalidArguments(let message):
      "Invalid arguments: \(message)"
    case .invariantFailed(let message):
      "Evidence invariant failed: \(message)"
    }
  }
}

@main
private enum TextKitEditorEvidenceMain {
  static func main() async {
    do {
      let arguments = try parseArguments(Array(CommandLine.arguments.dropFirst()))
      let (fixture, generationMilliseconds) = try measure {
        try BF01FixtureGenerator.make(size: arguments.size)
      }
      let report = try await benchmark(
        fixture: fixture,
        size: arguments.size,
        samples: arguments.samples,
        generationMilliseconds: generationMilliseconds
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let data = try encoder.encode(report)
      guard let json = String(data: data, encoding: .utf8) else {
        throw EvidenceError.invariantFailed("JSON output was not UTF-8")
      }
      print(json)
    } catch {
      FileHandle.standardError.write(Data("textkit-editor evidence failed: \(error)\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    }
  }

  private static func parseArguments(_ arguments: [String]) throws -> (size: BF01Size, samples: Int)
  {
    var size = BF01Size.tenMiB
    var samples = 10
    var index = 0

    while index < arguments.count {
      switch arguments[index] {
      case "--size":
        index += 1
        guard index < arguments.count, let raw = Int(arguments[index]),
          let parsed = BF01Size(rawValue: raw)
        else {
          throw EvidenceError.invalidArguments("--size must be 10 or 100")
        }
        size = parsed
      case "--samples":
        index += 1
        guard index < arguments.count, let parsed = Int(arguments[index]), parsed >= 10 else {
          throw EvidenceError.invalidArguments("--samples must be at least 10")
        }
        samples = parsed
      default:
        throw EvidenceError.invalidArguments("unknown option \(arguments[index])")
      }
      index += 1
    }
    return (size, samples)
  }

  @MainActor
  private static func benchmark(
    fixture: BF01Fixture,
    size: BF01Size,
    samples: Int,
    generationMilliseconds: Double
  ) async throws -> EvidenceReport {
    let harness = try TextKit2EditorHarness()
    let analyzer = BoundedSQLAnalyzer()
    let finder = IncrementalFindService()

    try harness.load(fixture)
    var loadValues = [Double]()
    loadValues.reserveCapacity(samples)
    for _ in 0..<samples {
      let (_, elapsed) = try measure {
        try harness.load(fixture)
      }
      loadValues.append(elapsed)
    }
    let loadLatency = LatencySummary(loadValues)
    guard harness.usesTextKit2 else {
      throw EvidenceError.invariantFailed("NSTextView did not retain a TextKit 2 network")
    }

    let baselineLength = harness.documentUTF16Length
    let baselineBytes = harness.documentUTF8Bytes
    var positionEvidence = [PositionEvidence]()
    for position in EditPosition.allCases {
      let resetPosition: EditPosition = position == .start ? .end : .start
      try harness.prepareViewport(for: resetPosition)
      try harness.prepareViewport(for: position)
      var viewportValues = [Double]()
      viewportValues.reserveCapacity(samples)
      for _ in 0..<samples {
        try harness.prepareViewport(for: resetPosition)
        let (_, elapsed) = try measure {
          try harness.prepareViewport(for: position)
        }
        viewportValues.append(elapsed)
      }
      let warmupMarker = "/* BF01_\(position.rawValue)_WARMUP */"
      let warmupSpan = try harness.insert(warmupMarker, at: position)
      try harness.forceViewportDisplay(around: warmupSpan)
      guard try harness.text(in: warmupSpan) == warmupMarker else {
        throw EvidenceError.invariantFailed("warm-up edit text mismatch")
      }
      harness.undo()
      guard harness.documentUTF16Length == baselineLength,
        harness.documentUTF8Bytes == baselineBytes
      else {
        throw EvidenceError.invariantFailed("warm-up undo did not restore document")
      }

      var values = [Double]()
      values.reserveCapacity(samples)
      for sample in 0..<samples {
        let marker = "/* BF01_\(position.rawValue)_\(sample) */"
        let (insertedSpan, milliseconds) = try measure {
          let span = try harness.insert(marker, at: position)
          try harness.forceViewportDisplay(around: span)
          return span
        }
        guard try harness.text(in: insertedSpan) == marker else {
          throw EvidenceError.invariantFailed("measured edit text mismatch")
        }
        values.append(milliseconds)
        harness.undo()
        guard harness.documentUTF16Length == baselineLength,
          harness.documentUTF8Bytes == baselineBytes
        else {
          throw EvidenceError.invariantFailed("undo did not restore \(position.rawValue) edit")
        }
      }
      positionEvidence.append(
        PositionEvidence(
          position: position.rawValue,
          viewportPreparation: LatencySummary(viewportValues),
          editAndForcedLocalLayout: LatencySummary(values)
        )
      )
    }

    let visibleSpan = try harness.visibleSpan(
      around: 16_384,
      requestedLength: 32_768
    )
    try harness.prepareViewport(around: visibleSpan)
    let snapshot = try harness.analysisSnapshot(for: visibleSpan)
    var analysisResult = try await analyzer.analyze(snapshot)
    var analysisValues = [Double]()
    analysisValues.reserveCapacity(samples)
    for _ in 0..<samples {
      let (result, elapsed) = try await measureAsync {
        try await analyzer.analyze(snapshot)
      }
      analysisResult = result
      analysisValues.append(elapsed)
    }
    try harness.applyHighlights(analysisResult)
    try harness.forceViewportDisplay(around: visibleSpan)
    var highlightValues = [Double]()
    highlightValues.reserveCapacity(samples)
    for _ in 0..<samples {
      let (_, elapsed) = try measure {
        try harness.applyHighlights(analysisResult)
        try harness.forceViewportDisplay(around: visibleSpan)
      }
      highlightValues.append(elapsed)
    }
    let analysisLatency = LatencySummary(analysisValues)
    let highlightLatency = LatencySummary(highlightValues)
    guard !analysisResult.keywordSpans.isEmpty else {
      throw EvidenceError.invariantFailed("visible SQL analysis returned no keyword spans")
    }

    let (analysisCancellationObserved, analysisCancellationLatency) =
      try await measureAnalysisCancellation(samples: samples)

    let (findCancellationObserved, findCancellationLatency) =
      try await measureFindCancellation(fixture: fixture, samples: samples)

    let findScenarios = try await benchmarkFindScenarios(
      finder: finder,
      fixture: fixture,
      samples: samples
    )
    let matchingFindScenarios = findScenarios.filter { $0.expectedLocation != nil }
    guard !matchingFindScenarios.isEmpty else {
      throw EvidenceError.invariantFailed("matching find scenarios were empty")
    }
    let worstFindResultP95 =
      matchingFindScenarios
      .map(\.latency.p95Milliseconds)
      .max() ?? .infinity

    let warmupUndoMarker = "/* BF01_UNDO_REDO_WARMUP */"
    _ = try harness.insert(warmupUndoMarker, at: .middle)
    harness.undo()
    harness.redo()
    harness.undo()
    guard harness.documentUTF16Length == baselineLength,
      harness.documentUTF8Bytes == baselineBytes
    else {
      throw EvidenceError.invariantFailed("warm-up undo/redo did not restore document")
    }

    var undoValues = [Double]()
    var redoValues = [Double]()
    undoValues.reserveCapacity(samples)
    redoValues.reserveCapacity(samples)
    for sample in 0..<samples {
      let marker = "/* BF01_UNDO_REDO_\(sample) */"
      _ = try harness.insert(marker, at: .middle)
      let (_, undoElapsed) = measure {
        harness.undo()
      }
      guard harness.documentUTF16Length == baselineLength,
        harness.documentUTF8Bytes == baselineBytes
      else {
        throw EvidenceError.invariantFailed("undo did not restore document")
      }
      let (_, redoElapsed) = measure {
        harness.redo()
      }
      guard
        harness.documentUTF16Length == baselineLength + (marker as NSString).length,
        harness.documentUTF8Bytes == baselineBytes + marker.utf8.count
      else {
        throw EvidenceError.invariantFailed("redo did not restore edit")
      }
      undoValues.append(undoElapsed)
      redoValues.append(redoElapsed)
      harness.undo()
    }
    let undoLatency = LatencySummary(undoValues)
    let redoLatency = LatencySummary(redoValues)

    let movedToEnd =
      harness.performKeyboardSelector(.moveToEndOfDocument)
      && harness.selectedSpan.location == harness.documentUTF16Length
    let recoveryState = harness.captureRecoveryState()
    let movedToStart =
      harness.performKeyboardSelector(.moveToBeginningOfDocument)
      && harness.selectedSpan.location == 0
    harness.restoreRecoveryState(recoveryState)
    let recoveredSelection = harness.selectedSpan == recoveryState.selectedSpan

    let accessibility = harness.accessibilitySnapshot()
    let accessibilityMetadataPassed =
      accessibility.label == TextKit2EditorHarness.accessibilityLabel
      && accessibility.role == "AXTextArea"
      && accessibility.help.contains(harness.featurePolicy.accessibilityStatus)
      && accessibility.isEditable
      && accessibility.isFocused

    let worstEditP95 =
      positionEvidence
      .map(\.editAndForcedLocalLayout.p95Milliseconds)
      .max() ?? 0
    let editTarget = size == .tenMiB ? 16.7 : 50.0
    let findTarget = 300.0
    let viewportPreparationTarget = 100.0
    let worstViewportPreparation =
      positionEvidence
      .map(\.viewportPreparation.p95Milliseconds)
      .max() ?? 0
    guard harness.usesTextKit2, harness.textKit1FallbackCount == 0 else {
      throw EvidenceError.invariantFailed("editor switched from TextKit 2 to TextKit 1")
    }

    return EvidenceReport(
      schemaVersion: 2,
      fixture: "BF-01-\(size.rawValue)MiB",
      fixtureBytes: fixture.byteCount,
      fixtureUTF16Units: fixture.utf16UnitCount,
      fixtureLines: fixture.lineCount,
      fixtureStatements: fixture.statementCount,
      fixtureGeneratorRevision: BF01Fixture.generatorRevision,
      fixtureFingerprint: fixture.fingerprint,
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      processorCount: ProcessInfo.processInfo.activeProcessorCount,
      physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
      sampleCount: samples,
      generationMilliseconds: generationMilliseconds,
      textKit2Load: loadLatency,
      edits: positionEvidence,
      visibleAnalysis: analysisLatency,
      visibleHighlightAndLayout: highlightLatency,
      highlightedKeywordCount: analysisResult.keywordSpans.count,
      highlightOutputLimitReached: analysisResult.hitOutputLimit,
      analysisCancellation: analysisCancellationLatency,
      analysisCancellationObserved: analysisCancellationObserved,
      findCancellation: findCancellationLatency,
      findCancellationObserved: findCancellationObserved,
      findResultWorstP95Milliseconds: worstFindResultP95,
      findScenarios: findScenarios,
      undo: undoLatency,
      redo: redoLatency,
      keyboardSelectorSmokePassed: movedToEnd && movedToStart,
      keyEquivalentRoutingEstablished: false,
      accessibilityMetadataSmokePassed: accessibilityMetadataPassed,
      manualVoiceOverEstablished: false,
      inMemorySelectionRestorePassed: recoveredSelection,
      durableCrashRecoveryEstablished: false,
      usesTextKit2: harness.usesTextKit2,
      textKit1FallbackCount: harness.textKit1FallbackCount,
      mode: harness.featurePolicy.mode.rawValue,
      modeAccessibilityStatus: harness.featurePolicy.accessibilityStatus,
      budget: BudgetEvidence(
        editProxyP95TargetMilliseconds: editTarget,
        editProxyP95WithinTarget: worstEditP95 <= editTarget,
        inputToPaintEstablished: false,
        findResultP95TargetMilliseconds: findTarget,
        findResultP95WithinTarget: worstFindResultP95 <= findTarget,
        analysisCancellationTargetMilliseconds: 250,
        analysisCancellationObservedWithinTarget: analysisCancellationObserved
          && analysisCancellationLatency.p95Milliseconds <= 250,
        analysisWorkerStartEstablished: false,
        findCancellationTargetMilliseconds: 250,
        findCancellationObservedWithinTarget: findCancellationObserved
          && findCancellationLatency.p95Milliseconds <= 250,
        findWorkerStartEstablished: false,
        viewportPreparationTargetMilliseconds: viewportPreparationTarget,
        viewportPreparationWithinTarget: worstViewportPreparation <= viewportPreparationTarget,
        largeFileModeRequired: size == .oneHundredMiB,
        largeFileModeActivated: harness.featurePolicy.mode == .largeFile,
        largeFileModePolicyPassed: size != .oneHundredMiB
          || harness.featurePolicy.mode == .largeFile,
        note:
          "Edit timing includes synchronous API work and forced local TextKit 2 layout in a hidden host; it does not establish input-to-paint. Analysis and absent-find cancellation are requested 1 ms after task creation without a worker-start barrier, then measure child termination. Key-equivalent routing, manual VoiceOver, durable recovery, and Instruments cancellation signposts remain required."
      )
    )
  }

  @MainActor
  private static func benchmarkFindScenarios(
    finder: IncrementalFindService,
    fixture: BF01Fixture,
    samples: Int
  ) async throws -> [FindScenarioEvidence] {
    let scenarios: [(String, String, TextSpan?)] = [
      ("middle-marker", BF01Fixture.findNeedle, fixture.findNeedleSpan),
      ("near-end-marker", BF01Fixture.nearEndNeedle, fixture.nearEndNeedleSpan),
      ("absent-marker", "BF01_ABSENT_RESULT_00000000", nil),
    ]
    var evidence = [FindScenarioEvidence]()

    for (name, needle, expected) in scenarios {
      let warmup = try await finder.firstRange(in: fixture.text, needle: needle)
      guard warmup == expected else {
        throw EvidenceError.invariantFailed("\(name) find warm-up returned an unexpected range")
      }

      var values = [Double]()
      values.reserveCapacity(samples)
      var observed: TextSpan?
      for _ in 0..<samples {
        let (result, elapsed) = try await measureAsync {
          try await finder.firstRange(in: fixture.text, needle: needle)
        }
        guard result == expected else {
          throw EvidenceError.invariantFailed("\(name) find returned an unexpected range")
        }
        observed = result
        values.append(elapsed)
      }

      evidence.append(
        FindScenarioEvidence(
          scenario: name,
          expectedLocation: expected?.location,
          observedLocation: observed?.location,
          latency: LatencySummary(values)
        )
      )
    }
    return evidence
  }

  @MainActor
  private static func measureAnalysisCancellation(
    samples: Int
  ) async throws -> (Bool, LatencySummary) {
    let limits = AnalysisLimits.viewportDefault
    let analyzer = BoundedSQLAnalyzer(limits: limits)
    let text = String(
      String(repeating: "SELECT value FROM source WHERE value = 1; ", count: 1_500)
        .prefix(limits.maximumUTF16Units)
    )
    let snapshot = AnalysisSnapshot(
      text: text,
      documentSpan: TextSpan(location: 0, length: (text as NSString).length),
      revision: 1
    )
    _ = try await cancelAnalysis(analyzer: analyzer, snapshot: snapshot)

    var observedAll = true
    var values = [Double]()
    values.reserveCapacity(samples)
    for _ in 0..<samples {
      let result = try await cancelAnalysis(analyzer: analyzer, snapshot: snapshot)
      observedAll = observedAll && result.0
      values.append(result.1)
    }
    return (observedAll, LatencySummary(values))
  }

  @MainActor
  private static func measureFindCancellation(
    fixture: BF01Fixture,
    samples: Int
  ) async throws -> (Bool, LatencySummary) {
    let finder = IncrementalFindService()
    let absentNeedle = "BF01_ABSENT_CANCELLATION_RESULT"
    _ = try await cancelFind(
      finder: finder,
      document: fixture.text,
      needle: absentNeedle
    )

    var observedAll = true
    var values = [Double]()
    values.reserveCapacity(samples)
    for _ in 0..<samples {
      let result = try await cancelFind(
        finder: finder,
        document: fixture.text,
        needle: absentNeedle
      )
      observedAll = observedAll && result.0
      values.append(result.1)
    }
    return (observedAll, LatencySummary(values))
  }

  @MainActor
  private static func cancelFind(
    finder: IncrementalFindService,
    document: String,
    needle: String
  ) async throws -> (Bool, Double) {
    let clock = ContinuousClock()
    return try await withThrowingTaskGroup(of: Bool.self) { group in
      group.addTask {
        do {
          _ = try await finder.firstRange(in: document, needle: needle)
          return false
        } catch is CancellationError {
          return true
        }
      }
      try await Task.sleep(for: .milliseconds(1))
      let cancellationStart = clock.now
      group.cancelAll()
      let observed = try await group.next() ?? false
      return (observed, milliseconds(cancellationStart.duration(to: clock.now)))
    }
  }

  @MainActor
  private static func cancelAnalysis(
    analyzer: BoundedSQLAnalyzer,
    snapshot: AnalysisSnapshot
  ) async throws -> (Bool, Double) {
    let clock = ContinuousClock()
    return try await withThrowingTaskGroup(of: Bool.self) { group in
      group.addTask {
        do {
          _ = try await analyzer.analyze(snapshot)
          return false
        } catch is CancellationError {
          return true
        }
      }
      try await Task.sleep(for: .milliseconds(1))
      let cancellationStart = clock.now
      group.cancelAll()
      let observed = try await group.next() ?? false
      return (observed, milliseconds(cancellationStart.duration(to: clock.now)))
    }
  }
}

private func measure<T>(_ operation: () throws -> T) rethrows -> (T, Double) {
  let clock = ContinuousClock()
  let start = clock.now
  let value = try operation()
  return (value, milliseconds(start.duration(to: clock.now)))
}

@MainActor
private func measureAsync<T>(_ operation: () async throws -> T) async rethrows -> (T, Double) {
  let clock = ContinuousClock()
  let start = clock.now
  let value = try await operation()
  return (value, milliseconds(start.duration(to: clock.now)))
}

private func milliseconds(_ duration: Duration) -> Double {
  let components = duration.components
  return (Double(components.seconds) * 1_000)
    + (Double(components.attoseconds) / 1_000_000_000_000_000)
}
