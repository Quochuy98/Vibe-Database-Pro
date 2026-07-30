import AppKit
import XCTest

@testable import GridSpikeAppKit
@testable import GridSpikeCore

@MainActor
final class VirtualizedGridHarnessTests: XCTestCase {
  func testBF03BuildsViewBasedFrozenAndMainTablesWithoutLogicalRowMaterialization() throws {
    let controller = try VirtualizedGridViewController(fixture: .bf03Wide())
    controller.loadView()

    XCTAssertEqual(controller.numberOfRows(in: controller.primaryTableView), 100_000)
    XCTAssertEqual(controller.frozenProjectionTableView.numberOfColumns, 3)
    XCTAssertEqual(controller.primaryTableView.numberOfColumns, 497)
    XCTAssertEqual(controller.frozenProjectionTableView.tableColumns.map(\.width), [120, 120, 120])
    let mainColumn = try XCTUnwrap(controller.primaryTableView.tableColumns.first)
    let frozenColumn = try XCTUnwrap(controller.frozenProjectionTableView.tableColumns.first)
    XCTAssertTrue(
      controller.tableView(controller.primaryTableView, viewFor: mainColumn, row: 0)
        is ReusableGridCellView
    )
    XCTAssertTrue(
      controller.tableView(controller.frozenProjectionTableView, viewFor: frozenColumn, row: 0)
        is ReusableGridCellView
    )
  }

  func testPageLoadCreatesVisibleReusableCellsAndThemeTouchesNoDataCache() async throws {
    let controller = try VirtualizedGridViewController(fixture: .bf02Million())
    let window = makeLayoutWindow(controller: controller)
    defer { dispose(window: window) }

    try await controller.loadPage(containingLogicalRow: 0)
    layout(window: window)
    _ = controller.primaryTableView.view(atColumn: 0, row: 0, makeIfNecessary: true)
    _ = controller.primaryTableView.view(atColumn: 1, row: 0, makeIfNecessary: true)
    layout(window: window)

    let rowID = try XCTUnwrap(controller.fixture.rowID(at: 0))
    try controller.select(rowID: rowID)
    let themeResult = controller.applyAppearance(.dark)
    let inventory = controller.inventory()

    XCTAssertTrue(themeResult.statePreserved)
    XCTAssertEqual(themeResult.dataReloadCountBefore, themeResult.dataReloadCountAfter)
    XCTAssertGreaterThan(themeResult.invalidatedVisibleCells, 0)
    XCTAssertGreaterThan(inventory.createdCellViews, 0)
    XCTAssertEqual(inventory.currentPageRows, 200)
  }

  func testStableSelectionScrollAndPendingEditSurviveEvictionReorderThemeAndPressure() async throws
  {
    let fixture = FixtureGenerator.bf02Million()
    let controller = try VirtualizedGridViewController(fixture: fixture)
    let window = makeLayoutWindow(controller: controller)
    defer { dispose(window: window) }

    try await controller.loadPage(containingLogicalRow: 0)
    layout(window: window)
    let rowID = try XCTUnwrap(fixture.rowID(at: 0))
    let cell = try XCTUnwrap(fixture.cell(row: 0, column: 4))
    try controller.select(rowID: rowID)
    controller.scroll(toLogicalRow: 0, intraRowOffset: 3)
    try await controller.recordPendingEdit(
      cellID: cell.id,
      proposedValue: .loaded(.text("edited but never applied")),
      sourceVersion: 1
    )
    let initialState = controller.captureVisibleState()

    for pageIndex in 1...7 {
      try await controller.loadPage(containingLogicalRow: pageIndex * 200)
    }
    controller.moveMainColumn(from: 0, to: 20)
    let themeResult = controller.applyAppearance(.dark)
    await controller.handleMemoryPressure(.critical)

    let pendingAfterPressure = await controller.pendingEdits.edit(for: cell.id)
    let stateAfterPressure = controller.captureVisibleState()
    XCTAssertEqual(pendingAfterPressure?.proposedValue, .loaded(.text("edited but never applied")))
    XCTAssertEqual(stateAfterPressure.selectedRowIDs, initialState.selectedRowIDs)
    XCTAssertEqual(stateAfterPressure.pendingEditCellIDs, initialState.pendingEditCellIDs)
    XCTAssertTrue(themeResult.statePreserved)
    XCTAssertNil(controller.currentPageRange)
  }

  func testFrozenScrollAndSelectionSynchronizeByStableLogicalRow() throws {
    let controller = try VirtualizedGridViewController(fixture: .bf03Wide())
    let window = makeLayoutWindow(controller: controller)
    defer { dispose(window: window) }
    layout(window: window)

    controller.scroll(toLogicalRow: 2_000, intraRowOffset: 5)
    layout(window: window)
    XCTAssertEqual(
      controller.primaryScrollView.contentView.bounds.origin.y,
      controller.frozenProjectionScrollView.contentView.bounds.origin.y,
      accuracy: 0.5
    )

    controller.primaryTableView.selectRowIndexes(
      IndexSet(integer: 2_000), byExtendingSelection: false)
    controller.tableViewSelectionDidChange(
      Notification(
        name: NSTableView.selectionDidChangeNotification, object: controller.primaryTableView)
    )
    XCTAssertTrue(controller.frozenProjectionTableView.selectedRowIndexes.contains(2_000))
    XCTAssertEqual(controller.captureVisibleState().selectedRowIDs.first?.logicalIndex, 2_000)
  }

  func testAccessibilityProjectionDetectsIncompleteFrozenLogicalTableAndKeyboardFocus() throws {
    let controller = try VirtualizedGridViewController(fixture: .bf03Wide())
    let window = makeLayoutWindow(controller: controller)
    defer { dispose(window: window) }
    layout(window: window)

    let snapshot = controller.accessibilityContractSnapshot()
    XCTAssertFalse(snapshot.exposesOneLogicalTable)
    XCTAssertEqual(snapshot.logicalRowCount, 100_000)
    XCTAssertEqual(snapshot.logicalColumnCount, 500)
    XCTAssertEqual(snapshot.frozenColumnCount, 3)
    XCTAssertTrue(snapshot.hasStableHeaderLabels)
    XCTAssertTrue(snapshot.distinguishesValueStates)
    XCTAssertEqual(controller.primaryTableView.accessibilityRole(), .table)
    XCTAssertFalse(controller.frozenProjectionTableView.isAccessibilityElement())
    XCTAssertTrue(controller.makePrimaryTableFirstResponder(in: window))
    XCTAssertTrue(window.firstResponder === controller.primaryTableView)
  }

  func testDeferredCellCannotEnterPendingEditPath() async throws {
    let fixture = FixtureGenerator.bf03Wide()
    let controller = try VirtualizedGridViewController(fixture: fixture)
    controller.loadView()
    let deferred = try XCTUnwrap(fixture.cell(row: 1, column: 26))

    do {
      try await controller.recordPendingEdit(
        cellID: deferred.id,
        proposedValue: .loaded(.json("{}")),
        sourceVersion: 1
      )
      XCTFail("Expected deferred value edit rejection")
    } catch let error as GridHarnessError {
      XCTAssertEqual(error, .editNotAllowedForUnloadedOrDeferredValue)
    }
  }

  private func makeLayoutWindow(controller: NSViewController) -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 80, y: 80, width: 1_280, height: 800),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentView = controller.view
    window.title = "DataForge DF-M0-004 synthetic grid"
    return window
  }

  private func layout(window: NSWindow) {
    window.contentView?.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
  }

  private func dispose(window: NSWindow) {
    window.contentView = nil
    window.close()
  }
}
