import XCTest

@testable import GridSpikeCore

final class BoundedPageCacheTests: XCTestCase {
  private struct Payload: Equatable, Sendable {
    let id: Int
    let bytes: Int
  }

  func testLimitsRejectNonPositiveValues() {
    XCTAssertThrowsError(try PageCacheLimits(maximumItems: 0, maximumBytes: 1))
    XCTAssertThrowsError(try PageCacheLimits(maximumItems: 1, maximumBytes: 0))
  }

  func testLeastRecentlyUsedEntryIsEvictedAtItemCeiling() async throws {
    let limits = try PageCacheLimits(maximumItems: 2, maximumBytes: 100)
    let cache = BoundedPageCache<Int, Payload>(limits: limits, byteCost: { $0.bytes })

    try await cache.insert(Payload(id: 1, bytes: 10), for: 1)
    try await cache.insert(Payload(id: 2, bytes: 10), for: 2)
    let firstHit = await cache.value(for: 1)
    XCTAssertEqual(firstHit?.id, 1)
    try await cache.insert(Payload(id: 3, bytes: 10), for: 3)

    let evicted = await cache.value(for: 2)
    let retainedFirst = await cache.value(for: 1)
    let retainedThird = await cache.value(for: 3)
    XCTAssertNil(evicted)
    XCTAssertEqual(retainedFirst?.id, 1)
    XCTAssertEqual(retainedThird?.id, 3)
    let inventory = await cache.inventory()
    XCTAssertEqual(inventory.itemCount, 2)
    XCTAssertEqual(inventory.byteCount, 20)
    XCTAssertEqual(inventory.evictionCount, 1)
  }

  func testByteCeilingEvictsAndOversizedReplacementPreservesExistingValue() async throws {
    let limits = try PageCacheLimits(maximumItems: 5, maximumBytes: 20)
    let cache = BoundedPageCache<Int, Payload>(limits: limits, byteCost: { $0.bytes })

    try await cache.insert(Payload(id: 1, bytes: 12), for: 1)
    try await cache.insert(Payload(id: 2, bytes: 12), for: 2)
    let evicted = await cache.value(for: 1)
    let retained = await cache.value(for: 2)
    XCTAssertNil(evicted)
    XCTAssertEqual(retained?.id, 2)

    do {
      try await cache.insert(Payload(id: 99, bytes: 21), for: 2)
      XCTFail("Expected oversized value to be rejected")
    } catch let error as PageCacheError {
      XCTAssertEqual(error, .valueExceedsByteLimit(valueBytes: 21, limitBytes: 20))
    }
    let valueAfterRejectedReplacement = await cache.value(for: 2)
    XCTAssertEqual(valueAfterRejectedReplacement?.id, 2)
  }

  func testMemoryPressureShrinksOrClearsWithoutChangingConfiguredCeilings() async throws {
    let limits = try PageCacheLimits(maximumItems: 5, maximumBytes: 100)
    let cache = BoundedPageCache<Int, Payload>(limits: limits, byteCost: { $0.bytes })
    for index in 0..<5 {
      try await cache.insert(Payload(id: index, bytes: 10), for: index)
    }

    await cache.handleMemoryPressure(.warning)
    var inventory = await cache.inventory()
    XCTAssertEqual(inventory.itemCount, 2)
    XCTAssertLessThanOrEqual(inventory.byteCount, 50)
    XCTAssertEqual(inventory.maximumItems, 5)
    XCTAssertEqual(inventory.maximumBytes, 100)

    await cache.handleMemoryPressure(.critical)
    inventory = await cache.inventory()
    XCTAssertEqual(inventory.itemCount, 0)
    XCTAssertEqual(inventory.byteCount, 0)
  }

  func testConcurrentAdmissionsRemainWithinBothLimits() async throws {
    let limits = try PageCacheLimits(maximumItems: 5, maximumBytes: 50)
    let cache = BoundedPageCache<Int, Payload>(limits: limits, byteCost: { $0.bytes })

    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<100 {
        group.addTask {
          try await cache.insert(Payload(id: index, bytes: 10), for: index)
        }
      }
      try await group.waitForAll()
    }

    let inventory = await cache.inventory()
    XCTAssertLessThanOrEqual(inventory.itemCount, 5)
    XCTAssertLessThanOrEqual(inventory.byteCount, 50)
  }
}
