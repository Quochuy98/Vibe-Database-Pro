import AppKit
import Darwin
import Foundation
import GridSpikeAppKit
import GridSpikeCore
import os.signpost

struct EvidenceArguments: Sendable {
  let fixture: String
  let rows: Int
  let samples: Int
  let scrollSeconds: Double
  let sourceRevision: String
}

enum EvidenceError: Error, CustomStringConvertible {
  case invalidArguments(String)
  case invariantFailed(String)
  case footprintUnavailable(Int32)

  var description: String {
    switch self {
    case .invalidArguments(let message): "Invalid arguments: \(message)"
    case .invariantFailed(let message): "Evidence invariant failed: \(message)"
    case .footprintUnavailable(let code): "proc_pid_rusage failed with code \(code)"
    }
  }
}

private actor EvidenceGate {
  private var openState = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !openState else {
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func open() {
    guard !openState else {
      return
    }
    openState = true
    let pending = waiters
    waiters.removeAll(keepingCapacity: false)
    for waiter in pending {
      waiter.resume()
    }
  }
}

@MainActor
enum EvidenceRunner {
  private static let signpostLog = OSLog(
    subsystem: "com.dataforge.spike.grid",
    category: .pointsOfInterest
  )

  static func run(arguments: EvidenceArguments) async throws -> EvidenceReport {
    let fixture = try makeFixture(arguments: arguments)
    let checksum = fixture.checksumSummary(sampleCount: 128)
    let controller = try VirtualizedGridViewController(fixture: fixture)
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let window = makeVisibleWindow()
    defer {
      window.contentViewController = nil
      window.close()
    }

    pumpRunLoop(seconds: 5)
    let baselineFootprint = try physicalFootprintBytes()
    var peakFootprint = baselineFootprint
    window.contentViewController = controller
    layout(window: window)
    pumpRunLoop(seconds: 0.5)
    peakFootprint = max(peakFootprint, try physicalFootprintBytes())

    let firstLayoutValues = try await firstLayoutProxySamples(
      controller: controller,
      window: window,
      samples: arguments.samples,
      peakFootprint: &peakFootprint
    )

    try await controller.loadPage(containingLogicalRow: 0)
    layout(window: window)
    let rowID = try require(fixture.rowID(at: 0), "fixture row zero")
    let editableCell = try require(fixture.cell(row: 0, column: 4), "editable fixture cell")
    try controller.select(rowID: rowID)
    controller.scroll(toLogicalRow: 0, intraRowOffset: 3)
    try await controller.recordPendingEdit(
      cellID: editableCell.id,
      proposedValue: .loaded(.text("synthetic pending edit; never applied")),
      sourceVersion: 1
    )

    let themeOutcome = try themeProxySamples(
      controller: controller,
      window: window,
      samples: arguments.samples,
      peakFootprint: &peakFootprint
    )
    let stateBeforeColumnOperations = controller.captureVisibleState()
    let columnIdentityPreserved = try exerciseColumnIdentity(
      controller: controller, fixture: fixture)
    controller.resetCellReuseEvidence()

    let scrollEvidence = try await runScrollEvidence(
      controller: controller,
      fixture: fixture,
      window: window,
      samples: arguments.samples,
      seconds: arguments.scrollSeconds,
      peakFootprint: &peakFootprint
    )
    let cancellation = try await cancellationEvidence(samples: arguments.samples)
    peakFootprint = max(peakFootprint, try physicalFootprintBytes())

    let pendingAfterChurn = await controller.pendingEdits.edit(for: editableCell.id)
    let cacheInventory = await controller.pageService.cacheInventory()
    let harnessInventory = controller.inventory()
    let accessibilityContract = controller.accessibilityContractSnapshot()
    let keyboardFocus = controller.makePrimaryTableFirstResponder(in: window)
    let stateAfterWork = controller.captureVisibleState()
    let deferredSafe = deferredMetadataRemainsUnmaterialized()
    let hardwareModel = sysctlString("hw.model") ?? "unavailable"
    let screen = window.screen ?? NSScreen.main
    let displayFrames = screen?.maximumFramesPerSecond ?? 0
    let displayDescription = displayDescription(screen)
    let incrementalPeak =
      peakFootprint >= baselineFootprint
      ? peakFootprint - baselineFootprint
      : 0
    let memoryTarget = UInt64(150 * 1_024 * 1_024)
    let releaseFloor = isM1ReleaseFloor(
      model: hardwareModel,
      memoryBytes: ProcessInfo.processInfo.physicalMemory
    )

    return EvidenceReport(
      schemaVersion: 1,
      fixture: arguments.fixture,
      fixtureGeneratorRevision: 1,
      logicalRows: fixture.logicalRowCount,
      logicalColumns: fixture.logicalColumnCount,
      sampledFixtureChecksumAlgorithm: checksum.algorithm,
      sampledFixtureChecksum: String(format: "%016llx", checksum.combinedChecksum),
      sampledRows: checksum.sampledRowCount,
      sampledCells: checksum.sampledCellCount,
      sourceRevision: arguments.sourceRevision,
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      hardwareModel: hardwareModel,
      physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
      processorCount: ProcessInfo.processInfo.processorCount,
      displayDescription: displayDescription,
      displayMaximumFramesPerSecond: displayFrames,
      sampleCount: arguments.samples,
      scrollSeconds: arguments.scrollSeconds,
      firstLayoutProxy: LatencySummary(firstLayoutValues),
      themeVisibleLayoutProxy: LatencySummary(themeOutcome.values),
      scroll: scrollEvidence,
      cancellation: cancellation,
      cache: CacheEvidence(
        itemCount: cacheInventory.itemCount,
        byteCount: cacheInventory.byteCount,
        maximumItems: cacheInventory.maximumItems,
        maximumBytes: cacheInventory.maximumBytes,
        hits: cacheInventory.hitCount,
        misses: cacheInventory.missCount,
        evictions: cacheInventory.evictionCount
      ),
      harness: HarnessEvidence(
        logicalRows: harnessInventory.logicalRows,
        logicalColumns: harnessInventory.logicalColumns,
        createdCellViews: harnessInventory.createdCellViews,
        peakGeometricallyVisibleCells: harnessInventory.peakGeometricallyVisibleCells,
        peakAvailableCellViews: harnessInventory.peakAvailableCellViews,
        horizontalViewExpansionRatio: harnessInventory.horizontalViewExpansionRatio,
        cellReuseWithinTwoTimesVisibleBudget: harnessInventory
          .cellReuseWithinTwoTimesVisibleBudget,
        pendingEditCells: harnessInventory.pendingEditCells,
        dataReloadCount: harnessInventory.dataReloadCount
      ),
      accessibility: AccessibilityEvidence(
        oneLogicalTableMetadataSmoke: accessibilityContract.exposesOneLogicalTable,
        rowCount: accessibilityContract.logicalRowCount,
        columnCount: accessibilityContract.logicalColumnCount,
        frozenColumnCount: accessibilityContract.frozenColumnCount,
        stableHeaders: accessibilityContract.hasStableHeaderLabels,
        distinctNotLoadedNullEmptyTextEmptyBinary: accessibilityContract
          .distinguishesValueStates,
        keyboardFirstResponderSmoke: keyboardFocus,
        manualVoiceOverEstablished: false,
        note:
          "Automated metadata detects that the ignored frozen projection is missing from the primary table's accessibility columns. Manual VoiceOver remains required."
      ),
      state: StateEvidence(
        pendingEditSurvivedCacheChurn: pendingAfterChurn?.proposedValue
          == .loaded(.text("synthetic pending edit; never applied")),
        selectionPreservedAcrossTheme: themeOutcome.statePreserved,
        scrollAnchorPreservedAcrossTheme: themeOutcome.statePreserved,
        pendingEditPreservedAcrossTheme: themeOutcome.statePreserved,
        columnIdentityPreservedAcrossReorderAndResize: columnIdentityPreserved
          && stateBeforeColumnOperations.pendingEditCellIDs
            == stateAfterWork.pendingEditCellIDs,
        frozenVerticalSynchronizationSmoke: scrollEvidence.runs.allSatisfy(
          \.frozenVerticalOffsetsMatched
        ),
        deferredValuesNeverMaterialized: deferredSafe
      ),
      memory: MemoryEvidence(
        emptyVisibleHarnessPhysicalFootprintBytes: baselineFootprint,
        peakPhysicalFootprintBytes: peakFootprint,
        incrementalPeakBytes: incrementalPeak,
        targetBytes: memoryTarget,
        withinDeveloperHostTarget: incrementalPeak <= memoryTarget,
        releaseFloorMachineEstablished: releaseFloor,
        note:
          "Developer-host physical footprint above a blank visible AppKit window; compare separate 1M and 10M processes. M1/16 GiB remains release-blocking."
      ),
      budget: BudgetEvidence(
        firstPresentedFrameTargetMilliseconds: 300,
        firstLayoutProxyP95Milliseconds: LatencySummary(firstLayoutValues).p95Milliseconds,
        firstLayoutProxyWithinNumericTarget: LatencySummary(firstLayoutValues)
          .p95Milliseconds <= 300,
        firstPresentedFrameEstablished: false,
        themePresentedFrameTargetMilliseconds: 100,
        themeLayoutProxyP95Milliseconds: LatencySummary(themeOutcome.values)
          .p95Milliseconds,
        themeLayoutProxyWithinNumericTarget: LatencySummary(themeOutcome.values)
          .p95Milliseconds <= 100,
        themePresentedFrameEstablished: false,
        frameIntervalP95TargetMilliseconds: 18.18,
        presentedFrameGateEstablished: false,
        note:
          "Forced layout/display and scroll-step duration are proxies. Core Animation presented-frame evidence is separate."
      ),
      appKitWindowWasOrderedVisible: window.isVisible,
      instrumentsCoreAnimationRequired: true,
      manualVoiceOverRequired: true,
      eightHourSoakEstablished: false,
      noDatabaseNetworkFFICredentialOrSQLWritePath: true
    )
  }

  private static func makeFixture(arguments: EvidenceArguments) throws -> FixtureGenerator {
    switch (arguments.fixture, arguments.rows) {
    case ("bf02", 1_000_000): FixtureGenerator.bf02Million()
    case ("bf02", 10_000_000): FixtureGenerator.bf02TenMillion()
    case ("bf03", 100_000): FixtureGenerator.bf03Wide()
    default:
      throw EvidenceError.invalidArguments(
        "bf02 rows must be 1000000 or 10000000; bf03 rows must be 100000"
      )
    }
  }

  private static func makeVisibleWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 80, y: 80, width: 1_280, height: 800),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    window.title = "DataForge DF-M0-004 · synthetic data only"
    window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1_280, height: 800))
    window.orderFrontRegardless()
    return window
  }

  private static func firstLayoutProxySamples(
    controller: VirtualizedGridViewController,
    window: NSWindow,
    samples: Int,
    peakFootprint: inout UInt64
  ) async throws -> [Double] {
    var values: [Double] = []
    for sample in 0...samples {
      let generation = UInt64(sample + 2)
      await controller.setGeneration(generation)
      let page = try await controller.pageService.page(index: 0, generation: generation)
      let start = ContinuousClock.now
      os_signpost(.begin, log: signpostLog, name: "GridFirstLayoutProxy")
      try controller.apply(page: page)
      layout(window: window)
      os_signpost(.end, log: signpostLog, name: "GridFirstLayoutProxy")
      let elapsed = milliseconds(since: start)
      peakFootprint = max(peakFootprint, try physicalFootprintBytes())
      if sample > 0 {
        values.append(elapsed)
      }
    }
    return values
  }

  private static func themeProxySamples(
    controller: VirtualizedGridViewController,
    window: NSWindow,
    samples: Int,
    peakFootprint: inout UInt64
  ) throws -> (values: [Double], statePreserved: Bool) {
    var values: [Double] = []
    var allStatePreserved = true
    for sample in 0...samples {
      let appearance: GridAppearance = sample.isMultiple(of: 2) ? .dark : .light
      let start = ContinuousClock.now
      os_signpost(.begin, log: signpostLog, name: "GridThemeLayoutProxy")
      let outcome = controller.applyAppearance(appearance)
      layout(window: window)
      os_signpost(.end, log: signpostLog, name: "GridThemeLayoutProxy")
      let elapsed = milliseconds(since: start)
      allStatePreserved =
        allStatePreserved
        && outcome.statePreserved
        && outcome.dataReloadCountBefore == outcome.dataReloadCountAfter
      peakFootprint = max(peakFootprint, try physicalFootprintBytes())
      if sample > 0 {
        values.append(elapsed)
      }
    }
    return (values, allStatePreserved)
  }

  private static func exerciseColumnIdentity(
    controller: VirtualizedGridViewController,
    fixture: FixtureGenerator
  ) throws -> Bool {
    guard let firstMain = fixture.schema.columns.first(where: { !$0.isFrozen }) else {
      return false
    }
    let identifier = NSUserInterfaceItemIdentifier(String(firstMain.id.rawValue, radix: 16))
    let table = controller.primaryTableView
    guard
      let originalIndex = table.tableColumns.firstIndex(where: {
        $0.identifier == identifier
      })
    else {
      return false
    }
    let destination = min(20, table.tableColumns.count - 1)
    controller.moveMainColumn(from: originalIndex, to: destination)
    try controller.resizeMainColumn(id: firstMain.id, to: 180)
    return table.tableColumns.contains(where: {
      $0.identifier == identifier && abs($0.width - 180) < 0.5
    })
  }

  private static func runScrollEvidence(
    controller: VirtualizedGridViewController,
    fixture: FixtureGenerator,
    window: NSWindow,
    samples: Int,
    seconds: Double,
    peakFootprint: inout UInt64
  ) async throws -> ScrollEvidence {
    if fixture.spec.kind == .bf03Wide {
      return try await runHorizontalScroll(
        controller: controller,
        fixture: fixture,
        window: window,
        samples: samples,
        seconds: seconds,
        peakFootprint: &peakFootprint
      )
    }
    return try await runVerticalScroll(
      controller: controller,
      fixture: fixture,
      window: window,
      samples: samples,
      seconds: seconds,
      peakFootprint: &peakFootprint
    )
  }

  private static func runVerticalScroll(
    controller: VirtualizedGridViewController,
    fixture: FixtureGenerator,
    window: NSWindow,
    samples: Int,
    seconds: Double,
    peakFootprint: inout UInt64
  ) async throws -> ScrollEvidence {
    let velocity = 2_400.0
    let rowHeight = 24.0
    let travelRows = max(1, Int((velocity * seconds / 2) / rowHeight))
    let nearEnd = max(0, fixture.logicalRowCount - travelRows - 2)
    let anchors = [
      ("start", 0),
      ("midpoint", max(0, fixture.logicalRowCount / 2 - travelRows / 2)),
      ("near-end", nearEnd),
    ]
    var runs: [ScrollRunEvidence] = []

    for sample in 0...samples {
      for (anchorName, anchorRow) in anchors {
        try await prefetchPages(
          controller: controller,
          startRow: anchorRow,
          travelRows: travelRows
        )
        let result = try await verticalScrollRun(
          controller: controller,
          fixture: fixture,
          window: window,
          anchorRow: anchorRow,
          seconds: seconds,
          velocity: velocity,
          peakFootprint: &peakFootprint
        )
        if sample > 0 {
          runs.append(
            ScrollRunEvidence(
              sample: sample,
              anchor: anchorName,
              stepDurationProxy: LatencySummary(result.values),
              proxyStepsOver18Point18Milliseconds: result.values.filter { $0 > 18.18 }.count,
              proxyStepsOver33Point33Milliseconds: result.values.filter { $0 > 33.33 }.count,
              frozenVerticalOffsetsMatched: result.frozenOffsetsMatched
            )
          )
        }
      }
    }
    return ScrollEvidence(
      kind: "BF-02 vertical start/midpoint/near-end",
      durationSecondsPerRun: seconds,
      targetPointsPerSecond: velocity,
      displayRefreshHertz: 60,
      presentedFrameIntervalsEstablished: false,
      runs: runs,
      note:
        "Per-step forced layout durations are diagnostic proxies, not Core Animation presented frames."
    )
  }

  private static func verticalScrollRun(
    controller: VirtualizedGridViewController,
    fixture: FixtureGenerator,
    window: NSWindow,
    anchorRow: Int,
    seconds: Double,
    velocity: Double,
    peakFootprint: inout UInt64
  ) async throws -> (values: [Double], frozenOffsetsMatched: Bool) {
    let stepCount = max(2, Int(ceil(seconds * 60)))
    let travelPoints = velocity * seconds / 2
    var values: [Double] = []
    var frozenOffsetsMatched = true
    os_signpost(.begin, log: signpostLog, name: "GridVerticalScrollProxy")
    defer { os_signpost(.end, log: signpostLog, name: "GridVerticalScrollProxy") }

    for step in 0..<stepCount {
      let phase = Double(step) / Double(max(1, stepCount - 1))
      let triangle = phase <= 0.5 ? phase * 2 : (1 - phase) * 2
      let targetPoints = Double(anchorRow) * 24 + travelPoints * triangle
      let targetRow = min(
        fixture.logicalRowCount - 1,
        max(0, Int(targetPoints / 24))
      )
      let start = ContinuousClock.now
      if controller.currentPageRange?.contains(targetRow) != true {
        try await controller.loadPage(containingLogicalRow: targetRow)
      }
      controller.scroll(
        toLogicalRow: targetRow,
        intraRowOffset: targetPoints - Double(targetRow) * 24
      )
      layout(window: window)
      values.append(milliseconds(since: start))
      if !controller.frozenProjectionScrollView.isHidden {
        frozenOffsetsMatched =
          frozenOffsetsMatched
          && abs(
            controller.primaryScrollView.contentView.bounds.origin.y
              - controller.frozenProjectionScrollView.contentView.bounds.origin.y
          ) <= 0.5
      }
      peakFootprint = max(peakFootprint, try physicalFootprintBytes())
      pumpRunLoop(seconds: 1.0 / 60.0)
    }
    return (values, frozenOffsetsMatched)
  }

  private static func runHorizontalScroll(
    controller: VirtualizedGridViewController,
    fixture: FixtureGenerator,
    window: NSWindow,
    samples: Int,
    seconds: Double,
    peakFootprint: inout UInt64
  ) async throws -> ScrollEvidence {
    let velocity = 2_400.0
    try await controller.loadPage(containingLogicalRow: 0)
    var runs: [ScrollRunEvidence] = []
    for sample in 0...samples {
      let stepCount = max(2, Int(ceil(seconds * 60)))
      let travelPoints = velocity * seconds / 2
      var values: [Double] = []
      var synchronized = true
      os_signpost(.begin, log: signpostLog, name: "GridHorizontalScrollProxy")
      for step in 0..<stepCount {
        let phase = Double(step) / Double(max(1, stepCount - 1))
        let triangle = phase <= 0.5 ? phase * 2 : (1 - phase) * 2
        let start = ContinuousClock.now
        controller.scrollHorizontally(to: travelPoints * triangle)
        layout(window: window)
        values.append(milliseconds(since: start))
        synchronized =
          synchronized
          && abs(
            controller.frozenProjectionScrollView.contentView.bounds.origin.x
          ) <= 0.5
        peakFootprint = max(peakFootprint, try physicalFootprintBytes())
        pumpRunLoop(seconds: 1.0 / 60.0)
      }
      os_signpost(.end, log: signpostLog, name: "GridHorizontalScrollProxy")
      if sample > 0 {
        runs.append(
          ScrollRunEvidence(
            sample: sample,
            anchor: "wide-horizontal",
            stepDurationProxy: LatencySummary(values),
            proxyStepsOver18Point18Milliseconds: values.filter { $0 > 18.18 }.count,
            proxyStepsOver33Point33Milliseconds: values.filter { $0 > 33.33 }.count,
            frozenVerticalOffsetsMatched: synchronized
          )
        )
      }
    }
    return ScrollEvidence(
      kind: "BF-03 500-column horizontal with three frozen columns",
      durationSecondsPerRun: seconds,
      targetPointsPerSecond: velocity,
      displayRefreshHertz: 60,
      presentedFrameIntervalsEstablished: false,
      runs: runs,
      note:
        "Frozen projection remains fixed while the main table scrolls; manual VoiceOver and Core Animation frame presentation remain separate."
    )
  }

  private static func prefetchPages(
    controller: VirtualizedGridViewController,
    startRow: Int,
    travelRows: Int
  ) async throws {
    let pageRows = 200
    let firstPage = startRow / pageRows
    let lastPage = (startRow + travelRows) / pageRows
    for pageIndex in firstPage...lastPage {
      _ = try await controller.pageService.page(
        index: pageIndex,
        generation: controller.generation
      )
    }
  }

  private static func cancellationEvidence(samples: Int) async throws -> CancellationEvidence {
    var acknowledgements: [Double] = []
    var terminalValues: [Double] = []
    var allLateValuesSuppressed = true

    for sample in 0...samples {
      let coordinator = GridFetchCoordinator<Int>()
      let started = EvidenceGate()
      let release = EvidenceGate()
      let task = Task {
        try await coordinator.fetch {
          await started.open()
          await release.wait()
          return 42
        }
      }
      await started.wait()
      let acknowledgementStart = ContinuousClock.now
      let acknowledged = await coordinator.requestCancellation()
      let acknowledgement = milliseconds(since: acknowledgementStart)
      guard acknowledged else {
        throw EvidenceError.invariantFailed("synthetic cancellation was not acknowledged")
      }
      try await Task.sleep(for: .milliseconds(510))
      let stateAtBoundary = await coordinator.state
      let terminalStart = ContinuousClock.now
      await release.open()
      do {
        _ = try await task.value
        allLateValuesSuppressed = false
      } catch is CancellationError {
        // Expected late-value suppression.
      }
      let terminal = milliseconds(since: terminalStart)
      let finalState = await coordinator.state
      allLateValuesSuppressed =
        allLateValuesSuppressed
        && stateAtBoundary == .cancelRequested(requestID: 1)
        && finalState == .cancelled(requestID: 1)
      if sample > 0 {
        acknowledgements.append(acknowledgement)
        terminalValues.append(terminal)
      }
    }

    return CancellationEvidence(
      acknowledgement: LatencySummary(acknowledgements),
      terminalAfterRelease: LatencySummary(terminalValues),
      acknowledgementTargetMilliseconds: 100,
      noAdmissionObservationMilliseconds: 500,
      allAcknowledgementsWithinTarget: acknowledgements.allSatisfy { $0 <= 100 },
      everyLateValueSuppressed: allLateValuesSuppressed,
      driverNetworkFFIEstablished: false
    )
  }

  private static func deferredMetadataRemainsUnmaterialized() -> Bool {
    let fixture = FixtureGenerator.bf03Wide()
    let expectedLengths: [Int64] = [1_048_576, 10_485_760, 104_857_600]
    let metadata = (26...28).compactMap { column in
      fixture.cell(row: 1, column: column)?.value.deferredMetadata
    }
    return metadata.map(\.logicalByteLength) == expectedLengths
      && metadata.allSatisfy { !$0.isMaterialized && $0.previewByteCount <= 64 * 1_024 }
  }

  private static func physicalFootprintBytes() throws -> UInt64 {
    var information = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &information) { pointer in
      pointer.withMemoryRebound(
        to: integer_t.self,
        capacity: Int(count)
      ) { rebound in
        task_info(
          mach_task_self_,
          task_flavor_t(TASK_VM_INFO),
          rebound,
          &count
        )
      }
    }
    guard result == KERN_SUCCESS else {
      throw EvidenceError.footprintUnavailable(result)
    }
    return information.phys_footprint
  }

  private static func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
      return nil
    }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else {
      return nil
    }
    let utf8 = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: utf8, as: UTF8.self)
  }

  private static func displayDescription(_ screen: NSScreen?) -> String {
    guard let screen else {
      return "unavailable"
    }
    return
      "\(Int(screen.frame.width))x\(Int(screen.frame.height)) points @ \(screen.backingScaleFactor)x"
  }

  private static func isM1ReleaseFloor(model: String, memoryBytes: UInt64) -> Bool {
    let knownM1Models: Set<String> = [
      "MacBookAir10,1",
      "MacBookPro17,1",
      "MacBookPro18,1",
      "MacBookPro18,2",
      "MacBookPro18,3",
      "MacBookPro18,4",
      "Macmini9,1",
      "iMac21,1",
      "iMac21,2",
    ]
    let os = ProcessInfo.processInfo.operatingSystemVersion
    return knownM1Models.contains(model)
      && memoryBytes >= UInt64(16 * 1_024 * 1_024 * 1_024)
      && os.majorVersion == 14
  }

  private static func layout(window: NSWindow) {
    window.contentView?.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
  }

  private static func pumpRunLoop(seconds: Double) {
    guard seconds > 0 else {
      return
    }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
  }

  private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now)
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }

  private static func require<T>(_ value: T?, _ name: String) throws -> T {
    guard let value else {
      throw EvidenceError.invariantFailed("missing \(name)")
    }
    return value
  }
}
