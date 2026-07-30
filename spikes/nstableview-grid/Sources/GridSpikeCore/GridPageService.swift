import Foundation

public struct GridPageKey: Hashable, Sendable {
  public let resultID: ResultID
  public let generation: UInt64
  public let pageIndex: Int

  public init(resultID: ResultID, generation: UInt64, pageIndex: Int) {
    self.resultID = resultID
    self.generation = generation
    self.pageIndex = pageIndex
  }
}

public struct GridPage: Hashable, Sendable {
  public let key: GridPageKey
  public let startRow: Int
  public let rows: [GridRow]
  public let approximateByteCount: Int

  public init(key: GridPageKey, startRow: Int, rows: [GridRow]) {
    self.key = key
    self.startRow = startRow
    self.rows = rows
    self.approximateByteCount = rows.reduce(64) { partial, row in
      let (sum, overflow) = partial.addingReportingOverflow(row.approximateByteCount)
      return overflow ? Int.max : sum
    }
  }

  public var endRow: Int {
    startRow + rows.count
  }

  public func row(atLogicalIndex index: Int) -> GridRow? {
    let offset = index - startRow
    guard rows.indices.contains(offset) else {
      return nil
    }
    return rows[offset]
  }
}

public struct GridPageChunk: Hashable, Sendable {
  public let pageKey: GridPageKey
  public let ordinal: Int
  public let rows: [GridRow]
  public let approximateByteCount: Int

  public init(
    pageKey: GridPageKey,
    ordinal: Int,
    rows: [GridRow],
    approximateByteCount: Int
  ) {
    self.pageKey = pageKey
    self.ordinal = ordinal
    self.rows = rows
    self.approximateByteCount = approximateByteCount
  }
}

public struct GridPageConfiguration: Equatable, Sendable {
  public let pageRows: Int
  public let maximumChunkRows: Int
  public let maximumChunkBytes: Int

  public init(
    pageRows: Int = 200,
    maximumChunkRows: Int = 1_000,
    maximumChunkBytes: Int = 4 * 1_024 * 1_024
  ) throws {
    guard (50...2_000).contains(pageRows) else {
      throw GridPageError.invalidPageRows(pageRows)
    }
    guard maximumChunkRows > 0, maximumChunkRows <= 1_000 else {
      throw GridPageError.invalidChunkRows(maximumChunkRows)
    }
    guard maximumChunkBytes > 0, maximumChunkBytes <= 4 * 1_024 * 1_024 else {
      throw GridPageError.invalidChunkBytes(maximumChunkBytes)
    }
    self.pageRows = pageRows
    self.maximumChunkRows = maximumChunkRows
    self.maximumChunkBytes = maximumChunkBytes
  }
}

public enum GridPageError: Error, Equatable, Sendable {
  case invalidPageRows(Int)
  case invalidChunkRows(Int)
  case invalidChunkBytes(Int)
  case pageIndexOutOfBounds(Int)
  case rowExceedsChunkByteLimit(rowBytes: Int, limitBytes: Int)
  case generatedRowMissing(Int)
}

/// Actor-owned synthetic page service. It generates only one requested page,
/// inserts it into the separately bounded LRU cache and never materializes the
/// fixture's logical result cardinality.
public actor SyntheticGridPageService {
  public let fixture: FixtureGenerator
  public let configuration: GridPageConfiguration

  private let cache: BoundedPageCache<GridPageKey, GridPage>

  public init(
    fixture: FixtureGenerator,
    configuration: GridPageConfiguration,
    cacheLimits: PageCacheLimits
  ) {
    self.fixture = fixture
    self.configuration = configuration
    self.cache = BoundedPageCache(limits: cacheLimits) { page in
      page.approximateByteCount
    }
  }

  public func page(index pageIndex: Int, generation: UInt64) async throws -> GridPage {
    let pageCount =
      (fixture.logicalRowCount + configuration.pageRows - 1)
      / configuration.pageRows
    guard pageIndex >= 0, pageIndex < pageCount else {
      throw GridPageError.pageIndexOutOfBounds(pageIndex)
    }

    let key = GridPageKey(
      resultID: fixture.resultID,
      generation: generation,
      pageIndex: pageIndex
    )
    if let cached = await cache.value(for: key) {
      return cached
    }

    let start = pageIndex * configuration.pageRows
    let end = min(start + configuration.pageRows, fixture.logicalRowCount)
    var rows: [GridRow] = []
    rows.reserveCapacity(end - start)
    for logicalIndex in start..<end {
      if logicalIndex.isMultiple(of: 16) {
        try Task.checkCancellation()
      }
      guard let row = fixture.row(at: logicalIndex) else {
        throw GridPageError.generatedRowMissing(logicalIndex)
      }
      rows.append(row)
    }

    let page = GridPage(key: key, startRow: start, rows: rows)
    try await cache.insert(page, for: key)
    return page
  }

  public func page(containingLogicalRow row: Int, generation: UInt64) async throws -> GridPage {
    guard row >= 0, row < fixture.logicalRowCount else {
      throw GridPageError.pageIndexOutOfBounds(row / configuration.pageRows)
    }
    return try await page(index: row / configuration.pageRows, generation: generation)
  }

  public func chunks(for page: GridPage) throws -> [GridPageChunk] {
    var chunks: [GridPageChunk] = []
    var currentRows: [GridRow] = []
    var currentBytes = 0

    func appendCurrentChunk() {
      guard !currentRows.isEmpty else {
        return
      }
      chunks.append(
        GridPageChunk(
          pageKey: page.key,
          ordinal: chunks.count,
          rows: currentRows,
          approximateByteCount: currentBytes
        )
      )
      currentRows.removeAll(keepingCapacity: true)
      currentBytes = 0
    }

    for row in page.rows {
      let rowBytes = row.approximateByteCount
      guard rowBytes <= configuration.maximumChunkBytes else {
        throw GridPageError.rowExceedsChunkByteLimit(
          rowBytes: rowBytes,
          limitBytes: configuration.maximumChunkBytes
        )
      }
      let wouldExceedRows = currentRows.count >= configuration.maximumChunkRows
      let wouldExceedBytes = currentBytes > configuration.maximumChunkBytes - rowBytes
      if wouldExceedRows || wouldExceedBytes {
        appendCurrentChunk()
      }
      currentRows.append(row)
      currentBytes += rowBytes
    }
    appendCurrentChunk()
    return chunks
  }

  public func invalidateGenerations(except generation: UInt64) async {
    let resultID = fixture.resultID
    await cache.invalidate { key in
      key.resultID == resultID && key.generation != generation
    }
  }

  public func handleMemoryPressure(_ pressure: PageCacheMemoryPressure) async {
    await cache.handleMemoryPressure(pressure)
  }

  public func cacheInventory() async -> PageCacheInventory {
    await cache.inventory()
  }

  public func isCached(pageIndex: Int, generation: UInt64) async -> Bool {
    let key = GridPageKey(
      resultID: fixture.resultID,
      generation: generation,
      pageIndex: pageIndex
    )
    return await cache.contains(key)
  }
}
