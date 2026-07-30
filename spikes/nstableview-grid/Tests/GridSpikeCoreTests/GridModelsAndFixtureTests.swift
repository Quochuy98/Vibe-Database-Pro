import Foundation
import XCTest

@testable import GridSpikeCore

final class GridModelsAndFixtureTests: XCTestCase {
  func testStableIdentitiesSurviveEquivalentRegenerationAndColumnReorder() throws {
    let first = FixtureGenerator(spec: .bf02Million)
    let second = FixtureGenerator(spec: .bf02Million)

    let firstRow = try XCTUnwrap(first.rowID(at: 123_456))
    let secondRow = try XCTUnwrap(second.rowID(at: 123_456))
    XCTAssertEqual(firstRow, secondRow)
    XCTAssertEqual(firstRow, RowID(resultID: first.resultID, index: 123_456))
    XCTAssertEqual(firstRow, RowID(resultID: first.resultID, offset: 123_456))

    let original = try XCTUnwrap(first.columnID(at: 4))
    let reordered = ColumnID(rawValue: original.rawValue, name: original.name, ordinal: 400)
    XCTAssertEqual(original, reordered)
    XCTAssertEqual(original.hashValue, reordered.hashValue)

    let firstCell = CellID(rowID: firstRow, columnID: original)
    let regeneratedCell = CellID(rowID: secondRow, columnID: reordered)
    XCTAssertEqual(firstCell, regeneratedCell)
  }

  func testResultIdentityIsDeterministicAndScopedToFixture() {
    let first = FixtureGenerator(spec: .bf02Million)
    let repeated = FixtureGenerator(spec: .bf02Million)
    let tenMillion = FixtureGenerator(spec: .bf02TenMillion)

    XCTAssertEqual(first.resultID, repeated.resultID)
    XCTAssertNotEqual(first.resultID, tenMillion.resultID)
    XCTAssertEqual(first.resultID.description, repeated.resultID.description)
  }

  func testBF02CoversEveryNormalizedTypeGroupAndFidelityFields() throws {
    let generator = FixtureGenerator(spec: .bf02Million)
    XCTAssertEqual(generator.rowCount, 1_000_000)
    XCTAssertEqual(
      Set(generator.schema.columns.map(\.typeGroup)), Set(NormalizedDataTypeGroup.allCases))

    guard case .integer(let integer) = generator.schema.columns[0].dataType else {
      return XCTFail("Expected integer descriptor")
    }
    XCTAssertEqual(integer.signedness, .signed)
    XCTAssertEqual(integer.bitWidth, 64)
    XCTAssertEqual(integer.precision, 19)

    guard case .decimal(let decimal) = generator.schema.columns[2].dataType else {
      return XCTFail("Expected decimal descriptor")
    }
    XCTAssertEqual(decimal.precision, 18)
    XCTAssertEqual(decimal.scale, 4)
    XCTAssertEqual(decimal.exactness, .exact)

    guard case .string(let text) = generator.schema.columns[4].dataType else {
      return XCTFail("Expected string descriptor")
    }
    XCTAssertEqual(text.length, 256)
    XCTAssertEqual(text.charset, "UTF-8")
    XCTAssertNotNil(text.collation)

    guard case .datetime(let timestamp) = generator.schema.columns[8].dataType else {
      return XCTFail("Expected datetime descriptor")
    }
    XCTAssertEqual(timestamp.timezoneSemantics, .namedZone)
    XCTAssertEqual(timestamp.precision, 3)

    guard case .unknown(let unknown) = generator.schema.columns[20].dataType else {
      return XCTFail("Expected unknown descriptor")
    }
    XCTAssertEqual(unknown.rawTypeIdentity, "vendor.custom_type")
    XCTAssertTrue(unknown.preservesLosslessBytes)
    XCTAssertTrue(unknown.preservesLosslessText)
  }

  func testNotLoadedNullEmptyTextAndEmptyBinaryAreDistinctStates() throws {
    let generator = FixtureGenerator(spec: .bf02Million)
    let emptyText = try generator.makeCell(row: 11, column: 4)
    let sqlNull = try generator.makeCell(row: 29, column: 4)
    let notLoaded = try generator.makeCell(row: 23, column: 11)
    let emptyBinary = try generator.makeCell(row: 17, column: 13)

    XCTAssertEqual(emptyText.value, .loaded(.text("")))
    XCTAssertTrue(emptyText.value.normalizedValue?.isEmptyText == true)
    XCTAssertTrue(sqlNull.value.isNull)
    XCTAssertTrue(notLoaded.value.isNotLoaded)
    XCTAssertEqual(emptyBinary.value, .loaded(.binary(Data())))
    XCTAssertTrue(emptyBinary.value.normalizedValue?.isEmptyBinary == true)

    XCTAssertNotEqual(emptyText.value, sqlNull.value)
    XCTAssertNotEqual(sqlNull.value, notLoaded.value)
    XCTAssertNotEqual(emptyBinary.value, notLoaded.value)
  }

  func testGeneratorPreservesTypedPayloads() throws {
    let generator = FixtureGenerator(spec: .bf02Million)
    let values = try (0..<21).map { try generator.makeCell(row: 1, column: $0).value }

    assertLoaded(values[0]) { if case .signedInteger = $0 { true } else { false } }
    assertLoaded(values[1]) { if case .unsignedInteger = $0 { true } else { false } }
    assertLoaded(values[2]) { if case .decimal = $0 { true } else { false } }
    assertLoaded(values[3]) { if case .floatingPoint = $0 { true } else { false } }
    assertLoaded(values[4]) { if case .text = $0 { true } else { false } }
    assertLoaded(values[5]) { if case .boolean = $0 { true } else { false } }
    assertLoaded(values[6]) { if case .date = $0 { true } else { false } }
    assertLoaded(values[7]) { if case .time = $0 { true } else { false } }
    assertLoaded(values[8]) { if case .datetime = $0 { true } else { false } }
    assertLoaded(values[9]) { if case .interval = $0 { true } else { false } }
    assertLoaded(values[10]) { if case .uuid = $0 { true } else { false } }
    assertLoaded(values[11]) { if case .json = $0 { true } else { false } }
    assertLoaded(values[12]) { if case .xml = $0 { true } else { false } }
    assertLoaded(values[13]) { if case .binary = $0 { true } else { false } }
    assertLoaded(values[14]) { if case .enumeration = $0 { true } else { false } }
    assertLoaded(values[15]) { if case .array = $0 { true } else { false } }
    assertLoaded(values[16]) { if case .composite = $0 { true } else { false } }
    assertLoaded(values[17]) { if case .spatial = $0 { true } else { false } }
    assertLoaded(values[18]) { if case .network = $0 { true } else { false } }
    assertLoaded(values[19]) { if case .bitString = $0 { true } else { false } }
    assertLoaded(values[20]) { if case .unknown = $0 { true } else { false } }
  }

  func testBF03HasFormulaDimensionsFrozenWidthsAndFiveTenKiBTextColumns() throws {
    let generator = FixtureGenerator(spec: .bf03Wide)
    XCTAssertEqual(generator.rowCount, 100_000)
    XCTAssertEqual(generator.columnCount, 500)
    XCTAssertEqual(generator.schema.columns.filter(\.isFrozen).count, 3)
    XCTAssertEqual(generator.schema.columns.prefix(3).map(\.preferredWidth), [120, 120, 120])

    let nonFrozenWidths = generator.schema.columns.dropFirst(3).prefix(9).map(\.preferredWidth)
    XCTAssertEqual(nonFrozenWidths, [80, 120, 180, 80, 120, 180, 80, 120, 180])

    let wideTextCells = try (21..<26).map { try generator.makeCell(row: 1, column: $0) }
    let byteCounts = wideTextCells.compactMap { cell -> Int? in
      guard case .loaded(.text(let value)) = cell.value else { return nil }
      return value.utf8.count
    }
    XCTAssertEqual(byteCounts.count, 5)
    XCTAssertEqual(byteCounts, Array(repeating: 10_240, count: 5))
  }

  func testDeferredOneTenAndHundredMiBValuesRemainMetadataOnly() throws {
    let generator = FixtureGenerator(spec: .bf03Wide)
    let cells = try (26...28).map { try generator.makeCell(row: 1, column: $0) }
    let metadata = try cells.map { try XCTUnwrap($0.value.deferredMetadata) }

    XCTAssertEqual(metadata.map(\.logicalByteLength), [1_048_576, 10_485_760, 104_857_600])
    XCTAssertEqual(metadata.map(\.kind), [.json, .binary, .binary])
    XCTAssertTrue(metadata.allSatisfy { !$0.isMaterialized })
    XCTAssertTrue(
      metadata.allSatisfy { $0.previewByteCount <= DeferredValueMetadata.maximumPreviewBytes })
    XCTAssertTrue(metadata.allSatisfy { $0.previewByteCount == 128 })
    XCTAssertTrue(metadata.allSatisfy { Int64($0.approximateByteCount) < $0.logicalByteLength })

    for cell in cells {
      guard let logicalLength = cell.value.deferredMetadata?.logicalByteLength else {
        return XCTFail("Expected deferred metadata")
      }
      XCTAssertLessThan(Int64(cell.approximateByteCount), logicalLength)
    }
  }

  func testDeferredInitializerHardCapsPreviewWithoutTrustingLogicalLength() {
    let oversizedPreview = Data(
      repeating: 0x7F, count: DeferredValueMetadata.maximumPreviewBytes + 1_024)
    let metadata = DeferredValueMetadata(
      kind: .binary,
      logicalByteLength: 104_857_600,
      locator: "fixture://bounded",
      preview: oversizedPreview
    )

    XCTAssertEqual(metadata.logicalByteLength, 104_857_600)
    XCTAssertEqual(metadata.previewByteCount, DeferredValueMetadata.maximumPreviewBytes)
    XCTAssertFalse(metadata.isMaterialized)
  }

  func testTenMillionLastRowIsGeneratedDirectlyWithoutCardinalityStorage() throws {
    let generator = FixtureGenerator(spec: .bf02TenMillion)
    let lastIndex = 9_999_999
    let row = try generator.makeRow(at: lastIndex)

    XCTAssertEqual(row.logicalIndex, lastIndex)
    XCTAssertEqual(row.id, RowID(resultID: generator.resultID, logicalIndex: lastIndex))
    XCTAssertEqual(row.cells.count, generator.columnCount)
    XCTAssertLessThan(row.approximateByteCount, 1_000_000)
    XCTAssertNil(generator.row(at: 10_000_000))
  }

  func testRowsAndCellsAreDeterministicAcrossCalls() throws {
    let first = FixtureGenerator(spec: .bf03Wide)
    let second = FixtureGenerator(spec: .bf03Wide)

    XCTAssertEqual(try first.makeRow(at: 50_000), try first.makeRow(at: 50_000))
    XCTAssertEqual(try first.makeRow(at: 50_000), try second.makeRow(at: 50_000))
    XCTAssertEqual(
      try first.makeCell(row: 99_999, column: 499), try second.makeCell(row: 99_999, column: 499))
  }

  func testChecksumSummaryIsDeterministicBoundedAndDimensionSensitive() throws {
    let first = FixtureGenerator(spec: .bf02Million)
    let repeated = FixtureGenerator(spec: .bf02Million)
    let tenMillion = FixtureGenerator(spec: .bf02TenMillion)

    let firstSummary = first.checksumSummary(sampleCount: 16)
    XCTAssertEqual(firstSummary, repeated.checksumSummary(sampleCount: 16))
    XCTAssertEqual(firstSummary.sampledRowCount, 16)
    XCTAssertEqual(firstSummary.sampledCellCount, 16 * first.columnCount)
    XCTAssertEqual(firstSummary.logicalRowCount, 1_000_000)
    XCTAssertEqual(firstSummary.logicalColumnCount, first.columnCount)
    XCTAssertEqual(firstSummary.algorithm, "fnv1a64-grid-v1")
    XCTAssertNotEqual(
      firstSummary.combinedChecksum, tenMillion.checksumSummary(sampleCount: 16).combinedChecksum)

    let customSpec = try GridFixtureSpec(rowCount: 50, columnCount: 5, seed: 123)
    let custom = FixtureGenerator(spec: customSpec)
    let allRows = custom.checksumSummary(sampleCount: 100)
    XCTAssertEqual(allRows.sampledRowCount, 50)
    XCTAssertEqual(allRows.sampledCellCount, 250)
  }

  func testApproximateByteAccountingCountsResidentPayloadOnly() throws {
    let generator = FixtureGenerator(spec: .bf03Wide)
    let deferred = try generator.makeCell(row: 1, column: 28)
    let wideText = try generator.makeCell(row: 1, column: 21)
    let row = try generator.makeRow(at: 1)

    XCTAssertLessThan(deferred.approximateByteCount, 100_000)
    XCTAssertGreaterThan(wideText.approximateByteCount, 10_000)
    XCTAssertEqual(generator.approximateResidentBytes(for: row), row.approximateByteCount)
    XCTAssertEqual(generator.approximateResidentBytes(rows: 1..<2), row.approximateByteCount)
    XCTAssertGreaterThan(row.approximateByteCount, 0)
  }

  func testInvalidCoordinatesReturnNilOrTypedError() throws {
    let generator = FixtureGenerator(spec: .bf02Million)
    XCTAssertNil(generator.rowID(at: -1))
    XCTAssertNil(generator.row(at: generator.rowCount))
    XCTAssertNil(generator.cell(row: 0, column: generator.columnCount))

    XCTAssertThrowsError(try generator.makeRow(at: -1)) { error in
      XCTAssertEqual(error as? FixtureAccessError, .rowOutOfBounds(index: -1, count: 1_000_000))
    }
    XCTAssertThrowsError(try generator.makeCell(row: 0, column: 21)) { error in
      XCTAssertEqual(error as? FixtureAccessError, .columnOutOfBounds(index: 21, count: 21))
    }
  }

  func testConfigurationValidationUsesTypedErrors() {
    XCTAssertThrowsError(try GridFixtureSpec(rowCount: 0, columnCount: 1)) { error in
      XCTAssertEqual(error as? GridFixtureConfigurationError, .invalidRowCount(0))
    }
    XCTAssertThrowsError(try GridFixtureSpec(rowCount: 1, columnCount: 0)) { error in
      XCTAssertEqual(error as? GridFixtureConfigurationError, .invalidColumnCount(0))
    }
    XCTAssertThrowsError(try GridFixtureSpec(rowCount: 1, columnCount: 501)) { error in
      XCTAssertEqual(error as? GridFixtureConfigurationError, .invalidColumnCount(501))
    }
    XCTAssertThrowsError(try GridFixtureSpec(rowCount: 1, columnCount: 1, seed: 0)) { error in
      XCTAssertEqual(error as? GridFixtureConfigurationError, .invalidSeed)
    }
  }

  func testValueStatesAndDeferredMetadataRoundTripCodable() throws {
    let values: [GridCellValue] = [
      .notLoaded,
      .null,
      .loaded(.text("")),
      .loaded(.binary(Data())),
      .deferred(
        DeferredValueMetadata(
          kind: .json, logicalByteLength: 1_048_576, locator: "fixture://row/1",
          preview: Data([1, 2, 3]))),
    ]
    let encoded = try JSONEncoder().encode(values)
    let decoded = try JSONDecoder().decode([GridCellValue].self, from: encoded)
    XCTAssertEqual(decoded, values)
  }

  private func assertLoaded(
    _ value: GridCellValue,
    file: StaticString = #filePath,
    line: UInt = #line,
    matches: (GridNormalizedValue) -> Bool
  ) {
    guard case .loaded(let normalized) = value else {
      return XCTFail("Expected loaded typed value, got \(value)", file: file, line: line)
    }
    XCTAssertTrue(matches(normalized), file: file, line: line)
  }
}
