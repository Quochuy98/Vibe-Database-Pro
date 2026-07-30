import Foundation

struct LatencySummary: Codable, Sendable {
  let rawMilliseconds: [Double]
  let medianMilliseconds: Double
  let p95Milliseconds: Double
  let worstMilliseconds: Double
  let coefficientOfVariation: Double

  init(_ values: [Double]) {
    let sorted = values.sorted()
    rawMilliseconds = values
    guard !sorted.isEmpty else {
      medianMilliseconds = 0
      p95Milliseconds = 0
      worstMilliseconds = 0
      coefficientOfVariation = 0
      return
    }
    if sorted.count.isMultiple(of: 2) {
      let upper = sorted.count / 2
      medianMilliseconds = (sorted[upper - 1] + sorted[upper]) / 2
    } else {
      medianMilliseconds = sorted[sorted.count / 2]
    }
    let p95Index = min(
      sorted.count - 1,
      max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
    )
    p95Milliseconds = sorted[p95Index]
    worstMilliseconds = sorted[sorted.count - 1]
    let mean = sorted.reduce(0, +) / Double(sorted.count)
    if mean == 0 {
      coefficientOfVariation = 0
    } else {
      let variance =
        sorted.reduce(0) { partial, value in
          partial + pow(value - mean, 2)
        } / Double(sorted.count)
      coefficientOfVariation = sqrt(variance) / mean
    }
  }
}

struct ScrollRunEvidence: Codable, Sendable {
  let sample: Int
  let anchor: String
  let stepDurationProxy: LatencySummary
  let proxyStepsOver18Point18Milliseconds: Int
  let proxyStepsOver33Point33Milliseconds: Int
  let frozenVerticalOffsetsMatched: Bool
}

struct ScrollEvidence: Codable, Sendable {
  let kind: String
  let durationSecondsPerRun: Double
  let targetPointsPerSecond: Double
  let displayRefreshHertz: Int
  let presentedFrameIntervalsEstablished: Bool
  let runs: [ScrollRunEvidence]
  let note: String
}

struct CancellationEvidence: Codable, Sendable {
  let acknowledgement: LatencySummary
  let terminalAfterRelease: LatencySummary
  let acknowledgementTargetMilliseconds: Double
  let noAdmissionObservationMilliseconds: Double
  let allAcknowledgementsWithinTarget: Bool
  let everyLateValueSuppressed: Bool
  let driverNetworkFFIEstablished: Bool
}

struct CacheEvidence: Codable, Sendable {
  let itemCount: Int
  let byteCount: Int
  let maximumItems: Int
  let maximumBytes: Int
  let hits: UInt64
  let misses: UInt64
  let evictions: UInt64
}

struct HarnessEvidence: Codable, Sendable {
  let logicalRows: Int
  let logicalColumns: Int
  let createdCellViews: Int
  let peakGeometricallyVisibleCells: Int
  let peakAvailableCellViews: Int
  let horizontalViewExpansionRatio: Double
  let cellReuseWithinTwoTimesVisibleBudget: Bool
  let pendingEditCells: Int
  let dataReloadCount: Int
}

struct AccessibilityEvidence: Codable, Sendable {
  let oneLogicalTableMetadataSmoke: Bool
  let rowCount: Int
  let columnCount: Int
  let frozenColumnCount: Int
  let stableHeaders: Bool
  let distinctNotLoadedNullEmptyTextEmptyBinary: Bool
  let keyboardFirstResponderSmoke: Bool
  let manualVoiceOverEstablished: Bool
  let note: String
}

struct StateEvidence: Codable, Sendable {
  let pendingEditSurvivedCacheChurn: Bool
  let selectionPreservedAcrossTheme: Bool
  let scrollAnchorPreservedAcrossTheme: Bool
  let pendingEditPreservedAcrossTheme: Bool
  let columnIdentityPreservedAcrossReorderAndResize: Bool
  let frozenVerticalSynchronizationSmoke: Bool
  let deferredValuesNeverMaterialized: Bool
}

struct MemoryEvidence: Codable, Sendable {
  let emptyVisibleHarnessPhysicalFootprintBytes: UInt64
  let peakPhysicalFootprintBytes: UInt64
  let incrementalPeakBytes: UInt64
  let targetBytes: UInt64
  let withinDeveloperHostTarget: Bool
  let releaseFloorMachineEstablished: Bool
  let note: String
}

struct BudgetEvidence: Codable, Sendable {
  let firstPresentedFrameTargetMilliseconds: Double
  let firstLayoutProxyP95Milliseconds: Double
  let firstLayoutProxyWithinNumericTarget: Bool
  let firstPresentedFrameEstablished: Bool
  let themePresentedFrameTargetMilliseconds: Double
  let themeLayoutProxyP95Milliseconds: Double
  let themeLayoutProxyWithinNumericTarget: Bool
  let themePresentedFrameEstablished: Bool
  let frameIntervalP95TargetMilliseconds: Double
  let presentedFrameGateEstablished: Bool
  let note: String
}

struct EvidenceReport: Codable, Sendable {
  let schemaVersion: Int
  let fixture: String
  let fixtureGeneratorRevision: Int
  let logicalRows: Int
  let logicalColumns: Int
  let sampledFixtureChecksumAlgorithm: String
  let sampledFixtureChecksum: String
  let sampledRows: Int
  let sampledCells: Int
  let sourceRevision: String
  let operatingSystem: String
  let hardwareModel: String
  let physicalMemoryBytes: UInt64
  let processorCount: Int
  let displayDescription: String
  let displayMaximumFramesPerSecond: Int
  let sampleCount: Int
  let scrollSeconds: Double
  let firstLayoutProxy: LatencySummary
  let themeVisibleLayoutProxy: LatencySummary
  let scroll: ScrollEvidence
  let cancellation: CancellationEvidence
  let cache: CacheEvidence
  let harness: HarnessEvidence
  let accessibility: AccessibilityEvidence
  let state: StateEvidence
  let memory: MemoryEvidence
  let budget: BudgetEvidence
  let appKitWindowWasOrderedVisible: Bool
  let instrumentsCoreAnimationRequired: Bool
  let manualVoiceOverRequired: Bool
  let eightHourSoakEstablished: Bool
  let noDatabaseNetworkFFICredentialOrSQLWritePath: Bool
}
