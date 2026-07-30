import AppKit
import GridSpikeCore

public struct GridScrollAnchor: Equatable, Sendable {
  public let rowID: RowID
  public let intraRowOffset: Double

  public init(rowID: RowID, intraRowOffset: Double) {
    self.rowID = rowID
    self.intraRowOffset = intraRowOffset
  }
}

public struct GridVisibleStateSnapshot: Equatable, Sendable {
  public let selectedRowIDs: Set<RowID>
  public let scrollAnchor: GridScrollAnchor?
  public let pendingEditCellIDs: Set<CellID>

  public init(
    selectedRowIDs: Set<RowID>,
    scrollAnchor: GridScrollAnchor?,
    pendingEditCellIDs: Set<CellID>
  ) {
    self.selectedRowIDs = selectedRowIDs
    self.scrollAnchor = scrollAnchor
    self.pendingEditCellIDs = pendingEditCellIDs
  }
}

public struct GridThemeUpdateResult: Equatable, Sendable {
  public let invalidatedVisibleCells: Int
  public let dataReloadCountBefore: Int
  public let dataReloadCountAfter: Int
  public let statePreserved: Bool
}

public struct GridAccessibilityContractSnapshot: Equatable, Sendable {
  public let exposesOneLogicalTable: Bool
  public let logicalRowCount: Int
  public let logicalColumnCount: Int
  public let frozenColumnCount: Int
  public let hasStableHeaderLabels: Bool
  public let distinguishesValueStates: Bool
}

public struct GridHarnessInventory: Equatable, Sendable {
  public let logicalRows: Int
  public let logicalColumns: Int
  public let createdCellViews: Int
  public let peakGeometricallyVisibleCells: Int
  public let peakAvailableCellViews: Int
  public let dataReloadCount: Int
  public let pendingEditCells: Int
  public let currentPageRows: Int

  public var cellReuseWithinTwoTimesVisibleBudget: Bool {
    peakAvailableCellViews > 0
      && createdCellViews <= peakAvailableCellViews * 2
  }

  public var horizontalViewExpansionRatio: Double {
    guard peakGeometricallyVisibleCells > 0 else {
      return 0
    }
    return Double(peakAvailableCellViews) / Double(peakGeometricallyVisibleCells)
  }
}

public enum GridHarnessError: Error, Equatable, Sendable {
  case pageResultMismatch
  case pageGenerationMismatch
  case rowIdentityMismatch
  case columnIdentityMismatch
  case editNotAllowedForUnloadedOrDeferredValue
}

@MainActor
public final class VirtualizedGridViewController: NSViewController,
  NSTableViewDataSource,
  NSTableViewDelegate
{
  public let fixture: FixtureGenerator
  public let pageService: SyntheticGridPageService
  public let pendingEdits: PendingEditOverlay<CellID, GridCellValue>

  private let pageConfiguration: GridPageConfiguration
  private let themeResolver = GridThemeResolver()
  private let frozenTableView = NSTableView()
  private let mainTableView = NSTableView()
  private let frozenScrollView = NSScrollView()
  private let mainScrollView = NSScrollView()
  private var frozenCoordinator: FrozenColumnCoordinator?
  private var columnByIdentifier: [NSUserInterfaceItemIdentifier: GridColumn] = [:]
  private var pageLoadTask: Task<Void, Never>?
  private var isSynchronizingSelection = false
  private var pendingEditCellIDs: Set<CellID> = []
  private var selectedRowIDs: Set<RowID> = []
  private var currentPage: GridPage?

  public private(set) var generation: UInt64
  public private(set) var appearance: GridAppearance
  public private(set) var createdCellViewCount = 0
  public private(set) var peakGeometricallyVisibleCellCount = 0
  public private(set) var peakAvailableCellViewCount = 0
  public private(set) var dataReloadCount = 0
  public private(set) var lastThemeInvalidatedCellCount = 0
  public private(set) var lastLoadErrorCategory: String?
  public private(set) var isLoadingPage = false

  public init(
    fixture: FixtureGenerator,
    generation: UInt64 = 1,
    appearance: GridAppearance = .light
  ) throws {
    let pageConfiguration = try GridPageConfiguration()
    self.fixture = fixture
    self.generation = generation
    self.appearance = appearance
    self.pageConfiguration = pageConfiguration
    self.pageService = SyntheticGridPageService(
      fixture: fixture,
      configuration: pageConfiguration,
      cacheLimits: try PageCacheLimits()
    )
    self.pendingEdits = PendingEditOverlay(
      limits: try PendingEditLimits()
    ) { edit in
      edit.originalValue.approximateByteCount
        + edit.proposedValue.approximateByteCount
        + 64
    }
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    nil
  }

  deinit {
    pageLoadTask?.cancel()
  }

  public override func loadView() {
    let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 1_280, height: 800))
    rootView.setAccessibilityRole(.group)
    rootView.setAccessibilityLabel("Synthetic typed result grid")
    view = rootView

    configure(tableView: frozenTableView, isFrozenProjection: true)
    configure(tableView: mainTableView, isFrozenProjection: false)
    configure(scrollView: frozenScrollView, tableView: frozenTableView, isFrozen: true)
    configure(scrollView: mainScrollView, tableView: mainTableView, isFrozen: false)
    installColumns()

    let stack = NSStackView(views: [frozenScrollView, mainScrollView])
    stack.orientation = .horizontal
    stack.alignment = .top
    stack.distribution = .fill
    stack.spacing = 1
    stack.translatesAutoresizingMaskIntoConstraints = false
    rootView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: rootView.topAnchor),
      stack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
    ])

    let frozenWidth = fixture.schema.columns
      .filter(\.isFrozen)
      .reduce(0) { $0 + $1.preferredWidth }
    frozenScrollView.widthAnchor.constraint(equalToConstant: frozenWidth).isActive = true
    frozenScrollView.isHidden = frozenWidth == 0

    frozenCoordinator = FrozenColumnCoordinator(
      frozenScrollView: frozenScrollView,
      mainScrollView: mainScrollView
    )
    frozenTableView.reloadData()
    mainTableView.reloadData()
    dataReloadCount += 1
  }

  public override func viewWillDisappear() {
    super.viewWillDisappear()
    pageLoadTask?.cancel()
    pageLoadTask = nil
  }

  public var primaryTableView: NSTableView {
    mainTableView
  }

  public var frozenProjectionTableView: NSTableView {
    frozenTableView
  }

  public var primaryScrollView: NSScrollView {
    mainScrollView
  }

  public var frozenProjectionScrollView: NSScrollView {
    frozenScrollView
  }

  public var currentPageRange: Range<Int>? {
    guard let currentPage else {
      return nil
    }
    return currentPage.startRow..<currentPage.endRow
  }

  public func numberOfRows(in _: NSTableView) -> Int {
    fixture.logicalRowCount
  }

  public func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  ) -> NSView? {
    guard let tableColumn,
      let column = columnByIdentifier[tableColumn.identifier],
      let cell = presentedCell(row: row, column: column)
    else {
      return nil
    }

    let cellView: ReusableGridCellView
    if let reusable = tableView.makeView(
      withIdentifier: ReusableGridCellView.reuseIdentifier,
      owner: self
    ) as? ReusableGridCellView {
      cellView = reusable
    } else {
      cellView = ReusableGridCellView()
      createdCellViewCount += 1
    }
    configure(cellView: cellView, cell: cell, column: column)
    recordVisibleCellPeak()
    return cellView
  }

  public func tableViewSelectionDidChange(_ notification: Notification) {
    guard !isSynchronizingSelection,
      let sourceTable = notification.object as? NSTableView
    else {
      return
    }
    isSynchronizingSelection = true
    let indexes = sourceTable.selectedRowIndexes
    let target = sourceTable === mainTableView ? frozenTableView : mainTableView
    if !target.isHidden {
      target.selectRowIndexes(indexes, byExtendingSelection: false)
    }
    selectedRowIDs = Set(indexes.compactMap { fixture.rowID(at: $0) })
    isSynchronizingSelection = false
  }

  public func tableViewColumnDidMove(_ notification: Notification) {
    guard let table = notification.object as? NSTableView, table === mainTableView else {
      return
    }
    // Column identity is stored in each NSTableColumn identifier; no row,
    // selection, page or pending-edit identity is changed here.
    recordVisibleCellPeak()
  }

  public func scrollViewDidLiveScroll(_ notification: Notification) {
    guard let source = notification.object as? NSScrollView else {
      return
    }
    if source === mainScrollView {
      frozenCoordinator?.synchronizeFromMain()
    } else if source === frozenScrollView {
      frozenCoordinator?.synchronizeFromFrozen()
    }
    scheduleVisiblePageLoad()
    recordVisibleCellPeak()
  }

  public func loadPage(containingLogicalRow row: Int) async throws {
    isLoadingPage = true
    defer { isLoadingPage = false }
    let page = try await pageService.page(
      containingLogicalRow: row,
      generation: generation
    )
    try apply(page: page)
  }

  public func apply(page: GridPage) throws {
    guard page.key.resultID == fixture.resultID else {
      throw GridHarnessError.pageResultMismatch
    }
    guard page.key.generation == generation else {
      throw GridHarnessError.pageGenerationMismatch
    }
    for row in page.rows {
      guard row.id == fixture.rowID(at: row.logicalIndex) else {
        throw GridHarnessError.rowIdentityMismatch
      }
    }
    currentPage = page
    _ = reconfigureVisibleCells(in: frozenTableView)
    _ = reconfigureVisibleCells(in: mainTableView)
    restoreSelection()
  }

  public func setGeneration(_ newGeneration: UInt64) async {
    generation = newGeneration
    currentPage = nil
    pageLoadTask?.cancel()
    pageLoadTask = nil
    await pageService.invalidateGenerations(except: newGeneration)
    _ = reconfigureVisibleCells(in: frozenTableView)
    _ = reconfigureVisibleCells(in: mainTableView)
  }

  public func handleMemoryPressure(_ pressure: PageCacheMemoryPressure) async {
    await pageService.handleMemoryPressure(pressure)
    currentPage = nil
    _ = reconfigureVisibleCells(in: frozenTableView)
    _ = reconfigureVisibleCells(in: mainTableView)
    restoreSelection()
  }

  public func select(rowID: RowID) throws {
    guard rowID.resultID == fixture.resultID,
      rowID.logicalIndex >= 0,
      rowID.logicalIndex < fixture.logicalRowCount
    else {
      throw GridHarnessError.rowIdentityMismatch
    }
    let indexes = IndexSet(integer: rowID.logicalIndex)
    isSynchronizingSelection = true
    mainTableView.selectRowIndexes(indexes, byExtendingSelection: false)
    if !frozenTableView.isHidden {
      frozenTableView.selectRowIndexes(indexes, byExtendingSelection: false)
    }
    selectedRowIDs = [rowID]
    isSynchronizingSelection = false
  }

  public func recordPendingEdit(
    cellID: CellID,
    proposedValue: GridCellValue,
    sourceVersion: UInt64
  ) async throws {
    guard cellID.rowID.resultID == fixture.resultID,
      let originalCell = fixture.cell(
        rowID: cellID.rowID,
        columnID: cellID.columnID
      )
    else {
      throw GridHarnessError.columnIdentityMismatch
    }
    switch originalCell.value {
    case .notLoaded, .deferred:
      throw GridHarnessError.editNotAllowedForUnloadedOrDeferredValue
    case .null, .loaded:
      break
    }
    try await pendingEdits.set(
      PendingEdit(
        originalValue: originalCell.value,
        proposedValue: proposedValue,
        sourceVersion: sourceVersion
      ),
      for: cellID
    )
    pendingEditCellIDs.insert(cellID)
    invalidateVisibleCell(cellID)
  }

  public func rollbackPendingEdit(cellID: CellID) async {
    _ = await pendingEdits.rollback(cellID)
    pendingEditCellIDs.remove(cellID)
    invalidateVisibleCell(cellID)
  }

  public func captureVisibleState() -> GridVisibleStateSnapshot {
    GridVisibleStateSnapshot(
      selectedRowIDs: selectedRowIDs,
      scrollAnchor: captureScrollAnchor(),
      pendingEditCellIDs: pendingEditCellIDs
    )
  }

  public func applyAppearance(_ newAppearance: GridAppearance) -> GridThemeUpdateResult {
    let before = captureVisibleState()
    let reloadsBefore = dataReloadCount
    appearance = newAppearance
    themeResolver.changePalette()
    let invalidated = invalidateVisibleStyles()
    let after = captureVisibleState()
    lastThemeInvalidatedCellCount = invalidated
    return GridThemeUpdateResult(
      invalidatedVisibleCells: invalidated,
      dataReloadCountBefore: reloadsBefore,
      dataReloadCountAfter: dataReloadCount,
      statePreserved: before == after
    )
  }

  @discardableResult
  public func invalidateVisibleStyles() -> Int {
    var updated = 0
    updated += reconfigureVisibleCells(in: frozenTableView)
    updated += reconfigureVisibleCells(in: mainTableView)
    return updated
  }

  public func scroll(toLogicalRow row: Int, intraRowOffset: Double = 0) {
    let boundedRow = min(max(row, 0), fixture.logicalRowCount - 1)
    let y = Double(boundedRow) * Double(mainTableView.rowHeight) + intraRowOffset
    var origin = mainScrollView.contentView.bounds.origin
    origin.y = max(0, y)
    mainScrollView.contentView.scroll(to: origin)
    mainScrollView.reflectScrolledClipView(mainScrollView.contentView)
    frozenCoordinator?.synchronizeFromMain()
    scheduleVisiblePageLoad()
  }

  public func scrollHorizontally(to x: Double) {
    let documentWidth = mainTableView.bounds.width
    let maximum = max(0, documentWidth - mainScrollView.contentSize.width)
    var origin = mainScrollView.contentView.bounds.origin
    origin.x = min(max(x, 0), maximum)
    mainScrollView.contentView.scroll(to: origin)
    mainScrollView.reflectScrolledClipView(mainScrollView.contentView)
  }

  public func captureScrollAnchor() -> GridScrollAnchor? {
    guard fixture.logicalRowCount > 0 else {
      return nil
    }
    let y = max(0, Double(mainScrollView.contentView.bounds.origin.y))
    let rowHeight = Double(mainTableView.rowHeight)
    let logicalRow = min(Int(floor(y / rowHeight)), fixture.logicalRowCount - 1)
    guard let rowID = fixture.rowID(at: logicalRow) else {
      return nil
    }
    return GridScrollAnchor(
      rowID: rowID,
      intraRowOffset: y - Double(logicalRow) * rowHeight
    )
  }

  public func restore(scrollAnchor: GridScrollAnchor) throws {
    guard scrollAnchor.rowID.resultID == fixture.resultID else {
      throw GridHarnessError.rowIdentityMismatch
    }
    scroll(
      toLogicalRow: scrollAnchor.rowID.logicalIndex,
      intraRowOffset: scrollAnchor.intraRowOffset
    )
  }

  public func moveMainColumn(from source: Int, to destination: Int) {
    guard mainTableView.tableColumns.indices.contains(source),
      destination >= 0,
      destination < mainTableView.tableColumns.count
    else {
      return
    }
    mainTableView.moveColumn(source, toColumn: destination)
  }

  public func resizeMainColumn(id: ColumnID, to width: Double) throws {
    let identifier = Self.identifier(for: id)
    guard
      let column = mainTableView.tableColumns.first(where: {
        $0.identifier == identifier
      })
    else {
      throw GridHarnessError.columnIdentityMismatch
    }
    column.width = min(max(width, column.minWidth), column.maxWidth)
  }

  public func accessibilityContractSnapshot() -> GridAccessibilityContractSnapshot {
    let valueDescriptions = [
      GridCellPresentation.accessibilityValue(for: .notLoaded),
      GridCellPresentation.accessibilityValue(for: .null),
      GridCellPresentation.accessibilityValue(for: .loaded(.text(""))),
      GridCellPresentation.accessibilityValue(for: .loaded(.binary(Data()))),
    ]
    let frozenColumnCount = fixture.schema.columns.filter(\.isFrozen).count
    let completeLogicalTable =
      mainTableView.isAccessibilityElement()
      && !frozenTableView.isAccessibilityElement()
      && (frozenColumnCount == 0 || mainTableView.numberOfColumns == fixture.logicalColumnCount)
    return GridAccessibilityContractSnapshot(
      exposesOneLogicalTable: completeLogicalTable,
      logicalRowCount: fixture.logicalRowCount,
      logicalColumnCount: fixture.logicalColumnCount,
      frozenColumnCount: frozenColumnCount,
      hasStableHeaderLabels: Set(fixture.schema.columns.map(\.name)).count
        == fixture.logicalColumnCount,
      distinguishesValueStates: Set(valueDescriptions).count == valueDescriptions.count
    )
  }

  public func inventory() -> GridHarnessInventory {
    recordVisibleCellPeak()
    return GridHarnessInventory(
      logicalRows: fixture.logicalRowCount,
      logicalColumns: fixture.logicalColumnCount,
      createdCellViews: createdCellViewCount,
      peakGeometricallyVisibleCells: peakGeometricallyVisibleCellCount,
      peakAvailableCellViews: peakAvailableCellViewCount,
      dataReloadCount: dataReloadCount,
      pendingEditCells: pendingEditCellIDs.count,
      currentPageRows: currentPage?.rows.count ?? 0
    )
  }

  public func makePrimaryTableFirstResponder(in window: NSWindow) -> Bool {
    window.makeFirstResponder(mainTableView)
  }

  /// Starts a steady-scroll reuse observation after setup/first-layout work.
  /// Existing available views are the baseline; later unique creations are
  /// counted without treating prior cold-layout generations as scroll churn.
  public func resetCellReuseEvidence() {
    createdCellViewCount =
      availableCellViewCount(in: frozenTableView)
      + availableCellViewCount(in: mainTableView)
    peakGeometricallyVisibleCellCount =
      geometricVisibleCellCount(in: frozenTableView)
      + geometricVisibleCellCount(in: mainTableView)
    peakAvailableCellViewCount = createdCellViewCount
  }

  private func configure(tableView: NSTableView, isFrozenProjection: Bool) {
    tableView.dataSource = self
    tableView.delegate = self
    tableView.rowHeight = 24
    tableView.intercellSpacing = NSSize(width: 1, height: 0)
    tableView.columnAutoresizingStyle = .noColumnAutoresizing
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.allowsMultipleSelection = false
    tableView.allowsEmptySelection = true
    tableView.allowsColumnReordering = !isFrozenProjection
    tableView.allowsColumnResizing = true
    tableView.focusRingType = .default
    if isFrozenProjection {
      tableView.setAccessibilityElement(false)
      tableView.setAccessibilityRole(.group)
      tableView.setAccessibilityLabel("Frozen visual projection")
    } else {
      tableView.setAccessibilityElement(true)
      tableView.setAccessibilityRole(.table)
      tableView.setAccessibilityLabel("Synthetic typed result table")
      tableView.setAccessibilityHelp(
        "Includes all logical columns; the first columns may be visually frozen."
      )
    }
  }

  private func configure(
    scrollView: NSScrollView,
    tableView: NSTableView,
    isFrozen: Bool
  ) {
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = !isFrozen
    scrollView.hasHorizontalScroller = !isFrozen
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = true
  }

  private func installColumns() {
    for column in fixture.schema.columns {
      let tableColumn = NSTableColumn(identifier: Self.identifier(for: column.id))
      tableColumn.title = column.name
      tableColumn.width = column.preferredWidth
      tableColumn.minWidth = 48
      tableColumn.maxWidth = 600
      columnByIdentifier[tableColumn.identifier] = column
      if column.isFrozen {
        frozenTableView.addTableColumn(tableColumn)
      } else {
        mainTableView.addTableColumn(tableColumn)
      }
    }
  }

  private func presentedCell(row: Int, column: GridColumn) -> GridCell? {
    guard let rowID = fixture.rowID(at: row) else {
      return nil
    }
    if let loaded = currentPage?.row(atLogicalIndex: row)?.cell(at: column.ordinal) {
      return loaded
    }
    return GridCell(
      id: CellID(rowID: rowID, columnID: column.id),
      rowID: rowID,
      columnID: column.id,
      ordinal: column.ordinal,
      dataType: column.dataType,
      value: .notLoaded
    )
  }

  private func configure(
    cellView: ReusableGridCellView,
    cell: GridCell,
    column: GridColumn
  ) {
    let modified = pendingEditCellIDs.contains(cell.id)
    let traits = GridCellPresentation.traits(for: cell, modified: modified)
    let style = themeResolver.resolve(
      appearance: appearance,
      typeGroup: cell.dataType.group,
      traits: traits
    )
    cellView.configure(
      cell: cell,
      text: GridCellPresentation.text(for: cell.value),
      accessibilityValue: GridCellPresentation.accessibilityValue(for: cell.value),
      style: style,
      paletteVersion: themeResolver.paletteVersion,
      columnName: column.name
    )
  }

  private func scheduleVisiblePageLoad() {
    guard let anchor = captureScrollAnchor() else {
      return
    }
    if currentPage?.row(atLogicalIndex: anchor.rowID.logicalIndex) != nil {
      return
    }
    pageLoadTask?.cancel()
    let service = pageService
    let expectedGeneration = generation
    let logicalRow = anchor.rowID.logicalIndex
    isLoadingPage = true
    pageLoadTask = Task { [weak self] in
      do {
        let page = try await service.page(
          containingLogicalRow: logicalRow,
          generation: expectedGeneration
        )
        try Task.checkCancellation()
        guard let self, self.generation == expectedGeneration else {
          return
        }
        try self.apply(page: page)
        self.lastLoadErrorCategory = nil
      } catch is CancellationError {
        // A newer viewport request owns the next page.
      } catch {
        self?.lastLoadErrorCategory = "synthetic-page"
      }
      self?.isLoadingPage = false
    }
  }

  private func restoreSelection() {
    guard let first = selectedRowIDs.first else {
      return
    }
    let indexes = IndexSet(integer: first.logicalIndex)
    isSynchronizingSelection = true
    mainTableView.selectRowIndexes(indexes, byExtendingSelection: false)
    if !frozenTableView.isHidden {
      frozenTableView.selectRowIndexes(indexes, byExtendingSelection: false)
    }
    isSynchronizingSelection = false
  }

  private func invalidateVisibleCell(_ cellID: CellID) {
    for table in [frozenTableView, mainTableView] {
      guard
        let columnIndex = table.tableColumns.firstIndex(where: {
          $0.identifier == Self.identifier(for: cellID.columnID)
        })
      else {
        continue
      }
      guard
        let cellView = table.view(
          atColumn: columnIndex,
          row: cellID.rowID.logicalIndex,
          makeIfNecessary: false
        ) as? ReusableGridCellView,
        let column = columnByIdentifier[table.tableColumns[columnIndex].identifier],
        let cell = presentedCell(row: cellID.rowID.logicalIndex, column: column)
      else {
        continue
      }
      configure(cellView: cellView, cell: cell, column: column)
    }
  }

  private func reconfigureVisibleCells(in table: NSTableView) -> Int {
    guard !table.isHidden else {
      return 0
    }
    let rowRange = table.rows(in: table.visibleRect)
    let columnRange = table.columnIndexes(in: table.visibleRect)
    guard rowRange.location != NSNotFound, rowRange.length > 0 else {
      return 0
    }
    var updated = 0
    let rows = rowRange.location..<(rowRange.location + rowRange.length)
    for row in rows where row < fixture.logicalRowCount {
      for columnIndex in columnRange {
        guard columnIndex < table.tableColumns.count,
          let cellView = table.view(
            atColumn: columnIndex,
            row: row,
            makeIfNecessary: false
          ) as? ReusableGridCellView,
          let column = columnByIdentifier[table.tableColumns[columnIndex].identifier],
          let cell = presentedCell(row: row, column: column)
        else {
          continue
        }
        configure(cellView: cellView, cell: cell, column: column)
        updated += 1
      }
    }
    return updated
  }

  private func recordVisibleCellPeak() {
    let geometric =
      geometricVisibleCellCount(in: frozenTableView)
      + geometricVisibleCellCount(in: mainTableView)
    let available =
      availableCellViewCount(in: frozenTableView)
      + availableCellViewCount(in: mainTableView)
    peakGeometricallyVisibleCellCount = max(
      peakGeometricallyVisibleCellCount,
      geometric
    )
    peakAvailableCellViewCount = max(peakAvailableCellViewCount, available)
  }

  private func geometricVisibleCellCount(in table: NSTableView) -> Int {
    guard !table.isHidden else {
      return 0
    }
    let rows = table.rows(in: table.visibleRect)
    guard rows.location != NSNotFound else {
      return 0
    }
    return rows.length * table.columnIndexes(in: table.visibleRect).count
  }

  private func availableCellViewCount(in table: NSTableView) -> Int {
    guard !table.isHidden else {
      return 0
    }
    var count = 0
    table.enumerateAvailableRowViews { rowView, _ in
      count += rowView.subviews.filter { $0 is ReusableGridCellView }.count
    }
    return count
  }

  private static func identifier(for columnID: ColumnID) -> NSUserInterfaceItemIdentifier {
    NSUserInterfaceItemIdentifier(String(columnID.rawValue, radix: 16))
  }
}
