import XCTest

@testable import GridSpikeCore

final class GridPageServiceTests: XCTestCase {
  func testDefaultPageAndChunksRespectRowAndByteCaps() async throws {
    let fixture = FixtureGenerator.bf03Wide()
    let configuration = try GridPageConfiguration()
    let service = SyntheticGridPageService(
      fixture: fixture,
      configuration: configuration,
      cacheLimits: try PageCacheLimits()
    )

    let page = try await service.page(index: 0, generation: 1)
    XCTAssertEqual(page.rows.count, 200)
    XCTAssertEqual(page.startRow, 0)
    XCTAssertEqual(page.endRow, 200)

    let chunks = try await service.chunks(for: page)
    XCTAssertFalse(chunks.isEmpty)
    XCTAssertEqual(chunks.flatMap(\.rows).count, 200)
    for chunk in chunks {
      XCTAssertLessThanOrEqual(chunk.rows.count, 1_000)
      XCTAssertLessThanOrEqual(chunk.approximateByteCount, 4 * 1_024 * 1_024)
    }
  }

  func testCacheIsBoundedAndPendingEditOverlayIsIndependent() async throws {
    let fixture = FixtureGenerator.bf02Million()
    let service = SyntheticGridPageService(
      fixture: fixture,
      configuration: try GridPageConfiguration(),
      cacheLimits: try PageCacheLimits(maximumItems: 5, maximumBytes: 64 * 1_024 * 1_024)
    )
    let overlay = PendingEditOverlay<CellID, GridCellValue>(
      limits: try PendingEditLimits(maximumCells: 10, maximumBytes: 1_024)
    ) { edit in
      edit.originalValue.approximateByteCount + edit.proposedValue.approximateByteCount + 64
    }

    guard let cell = fixture.cell(row: 0, column: 4) else {
      XCTFail("Expected deterministic fixture cell")
      return
    }
    try await overlay.set(
      PendingEdit(
        originalValue: cell.value,
        proposedValue: .loaded(.text("edited")),
        sourceVersion: 1
      ),
      for: cell.id
    )

    for pageIndex in 0..<10 {
      _ = try await service.page(index: pageIndex, generation: 1)
    }
    let cacheInventory = await service.cacheInventory()
    let editAfterEviction = await overlay.edit(for: cell.id)
    XCTAssertLessThanOrEqual(cacheInventory.itemCount, 5)
    XCTAssertLessThanOrEqual(cacheInventory.byteCount, 64 * 1_024 * 1_024)
    XCTAssertEqual(editAfterEviction?.proposedValue, .loaded(.text("edited")))
  }

  func testGenerationInvalidationRemovesOnlyStaleGeneration() async throws {
    let fixture = FixtureGenerator.bf02Million()
    let service = SyntheticGridPageService(
      fixture: fixture,
      configuration: try GridPageConfiguration(),
      cacheLimits: try PageCacheLimits()
    )
    _ = try await service.page(index: 0, generation: 1)
    _ = try await service.page(index: 1, generation: 2)

    await service.invalidateGenerations(except: 2)
    let oldCached = await service.isCached(pageIndex: 0, generation: 1)
    let currentCached = await service.isCached(pageIndex: 1, generation: 2)
    XCTAssertFalse(oldCached)
    XCTAssertTrue(currentCached)
  }

  func testMemoryPressureShrinksCacheWithoutAffectingLogicalRowIdentity() async throws {
    let fixture = FixtureGenerator.bf02TenMillion()
    let service = SyntheticGridPageService(
      fixture: fixture,
      configuration: try GridPageConfiguration(),
      cacheLimits: try PageCacheLimits()
    )
    let stableID = fixture.rowID(at: 9_999_999)
    for pageIndex in 0..<5 {
      _ = try await service.page(index: pageIndex, generation: 1)
    }

    await service.handleMemoryPressure(.critical)
    let inventory = await service.cacheInventory()
    XCTAssertEqual(inventory.itemCount, 0)
    XCTAssertEqual(fixture.rowID(at: 9_999_999), stableID)
  }
}
