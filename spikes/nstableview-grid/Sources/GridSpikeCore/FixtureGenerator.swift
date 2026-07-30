import Foundation

public enum FixtureAccessError: Error, Equatable, Sendable, CustomStringConvertible {
  case rowOutOfBounds(index: Int, count: Int)
  case columnOutOfBounds(index: Int, count: Int)

  public var description: String {
    switch self {
    case .rowOutOfBounds(let index, let count):
      "Row index \(index) is outside the logical range 0..<\(count)."
    case .columnOutOfBounds(let index, let count):
      "Column index \(index) is outside the schema range 0..<\(count)."
    }
  }
}

/// A private recipe for one synthetic column.  It is intentionally small and
/// does not contain a row-sized buffer; all values are derived from
/// `(seed, row, column)` when requested.
private enum FixtureColumnRole: String, Sendable {
  case signedInteger
  case unsignedInteger
  case exactDecimal
  case approximateDecimal
  case text
  case boolean
  case date
  case time
  case datetime
  case interval
  case uuid
  case json
  case xml
  case binary
  case enumeration
  case array
  case composite
  case spatial
  case network
  case bitString
  case unknown
  case wideText
  case deferredJSON
  case deferredBinary
  case fillerText
}

private struct FixtureColumnPlan: Sendable {
  let role: FixtureColumnRole
  let name: String
  let dataType: NormalizedDataType
  let preferredWidth: Double
  let isFrozen: Bool
  let isDeferred: Bool
}

/// Deterministic, formula-based BF-02/BF-03 fixture generator.
///
/// The generator owns only the bounded schema (at most 500 columns).  Logical
/// rows are never stored: `row(at:)` and `cell(row:column:)` derive a value in
/// O(number of requested columns) from the row/column coordinates.
public struct FixtureGenerator: Sendable {
  public static let maximumChecksumSampleRows = 1_024

  public let spec: GridFixtureSpec
  public let schema: GridSchema

  private let plans: [FixtureColumnPlan]

  public init(spec: GridFixtureSpec) {
    self.spec = spec
    let builtPlans = Self.makePlans(spec: spec)
    self.plans = builtPlans
    let columns = builtPlans.enumerated().map { ordinal, plan in
      let id = ColumnID(resultID: spec.resultID, name: plan.name, ordinal: ordinal)
      return GridColumn(
        id: id,
        ordinal: ordinal,
        name: plan.name,
        dataType: plan.dataType,
        isFrozen: plan.isFrozen,
        preferredWidth: plan.preferredWidth,
        isDeferred: plan.isDeferred
      )
    }
    self.schema = GridSchema(resultID: spec.resultID, columns: columns)
  }

  public init(_ spec: GridFixtureSpec) {
    self.init(spec: spec)
  }

  public static func bf02Million() -> FixtureGenerator {
    FixtureGenerator(spec: .bf02Million)
  }

  public static func bf02TenMillion() -> FixtureGenerator {
    FixtureGenerator(spec: .bf02TenMillion)
  }

  public static func bf03Wide() -> FixtureGenerator {
    FixtureGenerator(spec: .bf03Wide)
  }

  public var resultID: ResultID { spec.resultID }
  public var logicalRowCount: Int { spec.rowCount }
  public var logicalColumnCount: Int { spec.columnCount }
  public var rowCount: Int { spec.rowCount }
  public var columnCount: Int { spec.columnCount }

  /// Returns a stable row identity without allocating a row or its cells.
  public func rowID(at index: Int) -> RowID? {
    guard index >= 0, index < spec.rowCount else { return nil }
    return RowID(resultID: spec.resultID, logicalIndex: index)
  }

  public func rowID(index: Int) -> RowID? { rowID(at: index) }

  public func columnID(at index: Int) -> ColumnID? {
    guard let column = schema.column(at: index) else { return nil }
    return column.id
  }

  /// Optional convenience for callers that treat an out-of-range viewport as
  /// an empty result.  Safety-critical paths can use `makeRow(at:)` to receive
  /// a typed error instead.
  public func row(at index: Int) -> GridRow? {
    guard let rowID = rowID(at: index) else { return nil }
    return makeRow(rowID: rowID, index: index)
  }

  public func makeRow(at index: Int) throws -> GridRow {
    guard let rowID = rowID(at: index) else {
      throw FixtureAccessError.rowOutOfBounds(index: index, count: spec.rowCount)
    }
    return makeRow(rowID: rowID, index: index)
  }

  private func makeRow(rowID: RowID, index: Int) -> GridRow {
    // The only array created here is bounded by the schema column count (500
    // for BF-03), never by the logical row count.
    let cells = plans.enumerated().map { ordinal, plan in
      let column = schema.columns[ordinal]
      let cellID = CellID(rowID: rowID, columnID: column.id)
      return GridCell(
        id: cellID,
        rowID: rowID,
        columnID: column.id,
        ordinal: ordinal,
        dataType: plan.dataType,
        value: makeValue(role: plan.role, row: index, column: ordinal)
      )
    }
    return GridRow(id: rowID, logicalIndex: index, cells: cells)
  }

  public func cell(row rowIndex: Int, column columnIndex: Int) -> GridCell? {
    guard let rowID = rowID(at: rowIndex), let column = schema.column(at: columnIndex) else {
      return nil
    }
    let plan = plans[columnIndex]
    return GridCell(
      id: CellID(rowID: rowID, columnID: column.id),
      rowID: rowID,
      columnID: column.id,
      ordinal: columnIndex,
      dataType: plan.dataType,
      value: makeValue(role: plan.role, row: rowIndex, column: columnIndex)
    )
  }

  public func makeCell(row rowIndex: Int, column columnIndex: Int) throws -> GridCell {
    guard rowIndex >= 0, rowIndex < spec.rowCount else {
      throw FixtureAccessError.rowOutOfBounds(index: rowIndex, count: spec.rowCount)
    }
    guard columnIndex >= 0, columnIndex < spec.columnCount else {
      throw FixtureAccessError.columnOutOfBounds(index: columnIndex, count: spec.columnCount)
    }
    // The bounds above make this access safe without force unwraps.
    if let result = cell(row: rowIndex, column: columnIndex) {
      return result
    }
    // This branch is unreachable after validation, but keeps the API's error
    // contract explicit if the schema implementation changes in the future.
    throw FixtureAccessError.columnOutOfBounds(index: columnIndex, count: spec.columnCount)
  }

  public func row(at rowID: RowID) -> GridRow? {
    guard rowID.resultID == resultID else { return nil }
    return row(at: rowID.logicalIndex)
  }

  public func cell(rowID: RowID, columnID: ColumnID) -> GridCell? {
    guard rowID.resultID == resultID,
      let column = schema.column(id: columnID)
    else { return nil }
    return cell(row: rowID.logicalIndex, column: column.ordinal)
  }

  /// A bounded-memory estimate for one row.  Deferred values contribute only
  /// locator and preview metadata, never their advertised logical length.
  public func approximateResidentBytes(for row: GridRow) -> Int {
    row.approximateByteCount
  }

  public func approximateResidentBytes(rowAt index: Int) -> Int {
    row(at: index)?.approximateByteCount ?? 0
  }

  public func approximateResidentBytes(rows range: Range<Int>) -> Int {
    let bounded = range.clamped(to: 0..<spec.rowCount)
    var total = 0
    for index in bounded {
      total = saturatingAdd(total, approximateResidentBytes(rowAt: index))
      if total == Int.max { break }
    }
    return total
  }

  public func approximateBytes(for row: GridRow) -> Int {
    approximateResidentBytes(for: row)
  }

  /// Returns a deterministic, bounded sample summary.  `sampleCount` limits
  /// work and memory; it never changes the logical fixture cardinality.
  public func checksumSummary(sampleCount requestedSampleCount: Int = 1_024)
    -> FixtureChecksumSummary
  {
    let sampleCount = max(
      1,
      min(requestedSampleCount, spec.rowCount, Self.maximumChecksumSampleRows)
    )
    var schemaHasher = GridStableHasher()
    schemaHasher.append("schema-v1")
    schemaHasher.append(UInt64(spec.columnCount))
    for (ordinal, column) in schema.columns.enumerated() {
      schemaHasher.append(UInt64(ordinal))
      schemaHasher.append(column.id.rawValue)
      schemaHasher.append(column.name)
      append(type: column.dataType, to: &schemaHasher)
      schemaHasher.append(column.isFrozen)
      schemaHasher.append(column.isDeferred)
    }

    var rowHasher = GridStableHasher()
    var cellHasher = GridStableHasher()
    rowHasher.append("rows-v1")
    cellHasher.append("cells-v1")
    var sampledRows = 0
    var sampledCells = 0
    for rowIndex in sampleIndices(count: sampleCount) {
      guard let rowID = rowID(at: rowIndex) else { continue }
      sampledRows += 1
      rowHasher.append(rowID.resultID.rawValue)
      rowHasher.append(Int64(rowID.logicalIndex))
      for (columnIndex, plan) in plans.enumerated() {
        guard let column = schema.column(at: columnIndex) else { continue }
        sampledCells += 1
        let value = makeValue(role: plan.role, row: rowIndex, column: columnIndex)
        cellHasher.append(rowID.resultID.rawValue)
        cellHasher.append(Int64(rowIndex))
        cellHasher.append(column.id.rawValue)
        append(value: value, to: &cellHasher)
      }
    }

    let schemaChecksum = schemaHasher.value
    let rowChecksum = rowHasher.value
    let cellChecksum = cellHasher.value
    var combinedHasher = GridStableHasher()
    combinedHasher.append("combined-v1")
    combinedHasher.append(schemaChecksum)
    combinedHasher.append(rowChecksum)
    combinedHasher.append(cellChecksum)
    combinedHasher.append(UInt64(spec.rowCount))
    combinedHasher.append(UInt64(spec.columnCount))

    return FixtureChecksumSummary(
      schemaChecksum: schemaChecksum,
      rowChecksum: rowChecksum,
      cellChecksum: cellChecksum,
      combinedChecksum: combinedHasher.value,
      sampledRowCount: sampledRows,
      sampledCellCount: sampledCells,
      logicalRowCount: spec.rowCount,
      logicalColumnCount: spec.columnCount
    )
  }

  public func checksum(sampleCount: Int = 1_024) -> UInt64 {
    checksumSummary(sampleCount: sampleCount).combinedChecksum
  }

  // MARK: Plans

  private static func makePlans(spec: GridFixtureSpec) -> [FixtureColumnPlan] {
    let base: [(FixtureColumnRole, String, NormalizedDataType, Double)] = [
      (
        .signedInteger, "id",
        .integer(
          IntegerTypeDescriptor(
            signedness: .signed, bitWidth: 64, precision: 19, rawTypeName: "BIGINT")), 90
      ),
      (
        .unsignedInteger, "unsigned_count",
        .integer(
          IntegerTypeDescriptor(
            signedness: .unsigned, bitWidth: 64, precision: 20, rawTypeName: "BIGINT UNSIGNED")),
        120
      ),
      (
        .exactDecimal, "amount",
        .decimal(
          DecimalTypeDescriptor(
            precision: 18, scale: 4, exactness: .exact, rawTypeName: "DECIMAL(18,4)")), 120
      ),
      (
        .approximateDecimal, "ratio",
        .decimal(
          DecimalTypeDescriptor(
            precision: 17, scale: nil, exactness: .approximate, rawTypeName: "DOUBLE")), 110
      ),
      (
        .text, "label",
        .string(
          StringTypeDescriptor(
            length: 256, collation: "und-x-icu", charset: "UTF-8", rawTypeName: "VARCHAR(256)")),
        180
      ),
      (
        .boolean, "active",
        .boolean(BooleanTypeDescriptor(representation: .native, rawTypeName: "BOOLEAN")), 90
      ),
      (
        .date, "created_date",
        .date(
          TemporalTypeDescriptor(
            timezoneSemantics: .none, precision: nil, calendar: "gregorian", rawTypeName: "DATE")),
        120
      ),
      (
        .time, "created_time",
        .time(
          TemporalTypeDescriptor(
            timezoneSemantics: .fixedOffset, precision: 6, calendar: "gregorian",
            rawTypeName: "TIME WITH TIME ZONE")), 150
      ),
      (
        .datetime, "updated_at",
        .datetime(
          TemporalTypeDescriptor(
            timezoneSemantics: .namedZone, precision: 3, calendar: "gregorian",
            rawTypeName: "TIMESTAMP WITH TIME ZONE")), 180
      ),
      (
        .interval, "elapsed",
        .interval(
          IntervalTypeDescriptor(fields: "day to second", precision: 6, rawTypeName: "INTERVAL")),
        140
      ),
      (
        .uuid, "row_uuid", .uuid(UUIDTypeDescriptor(physicalForm: .native, rawTypeName: "UUID")),
        280
      ),
      (
        .json, "document",
        .json(JSONTypeDescriptor(physicalForm: .text, validation: "RFC 8259", rawTypeName: "JSON")),
        220
      ),
      (
        .xml, "markup",
        .xml(XMLTypeDescriptor(physicalForm: .text, validation: "well-formed", rawTypeName: "XML")),
        220
      ),
      (
        .binary, "payload",
        .binary(
          BinaryTypeDescriptor(
            isLargeObject: false, isInline: true, logicalLength: nil, locatorLifetime: .valueOwned,
            rawTypeName: "BYTEA")), 150
      ),
      (
        .enumeration, "state",
        .enumeration(
          EnumTypeDescriptor(
            allowedLabels: ["new", "ready", "failed"], baseType: "text",
            constraints: ["allowed-labels"], rawTypeName: "status_enum")), 110
      ),
      (
        .array, "tags",
        .array(ArrayTypeDescriptor(elementType: "text", dimensions: [nil], rawTypeName: "TEXT[]")),
        180
      ),
      (
        .composite, "profile",
        .composite(
          CompositeTypeDescriptor(
            fields: ["display_name:text", "score:decimal"], rawTypeName: "profile_record")), 220
      ),
      (
        .spatial, "location",
        .spatial(
          SpatialTypeDescriptor(
            subtype: "POINT", srid: 4326, encoding: "WKB", rawTypeName: "GEOMETRY(POINT,4326)")),
        180
      ),
      (
        .network, "client_network",
        .network(NetworkTypeDescriptor(family: "IPv4", length: 32, rawTypeName: "INET")), 160
      ),
      (
        .bitString, "flags",
        .bitString(BitStringTypeDescriptor(length: 16, rawTypeName: "BIT(16)")), 110
      ),
      (
        .unknown, "engine_value",
        .unknown(
          UnknownTypeDescriptor(
            rawTypeIdentity: "vendor.custom_type", preservesLosslessBytes: true,
            preservesLosslessText: true)), 180
      ),
    ]

    var plans = base.prefix(spec.columnCount).map { tuple in
      FixtureColumnPlan(
        role: tuple.0,
        name: tuple.1,
        dataType: tuple.2,
        preferredWidth: tuple.3,
        isFrozen: false,
        isDeferred: false
      )
    }

    if spec.columnCount > plans.count {
      for ordinal in plans.count..<spec.columnCount {
        let isWideText = spec.kind == .bf03Wide && ordinal >= 21 && ordinal < 26
        let deferredIndex = ordinal - 26
        let isDeferredJSON = spec.kind == .bf03Wide && deferredIndex == 0
        let isDeferredBinary = spec.kind == .bf03Wide && deferredIndex >= 1 && deferredIndex <= 2
        let role: FixtureColumnRole
        let type: NormalizedDataType
        let name: String
        let width: Double
        if isWideText {
          role = .wideText
          name = "wide_text_\(ordinal - 20)"
          type = .string(
            StringTypeDescriptor(
              length: 10_240, collation: "und-x-icu", charset: "UTF-8", rawTypeName: "TEXT"))
          width = 260
        } else if isDeferredJSON {
          role = .deferredJSON
          name = "deferred_json_1m"
          type = .json(
            JSONTypeDescriptor(physicalForm: .binary, validation: "RFC 8259", rawTypeName: "JSONB"))
          width = 240
        } else if isDeferredBinary {
          role = .deferredBinary
          let lengthName = deferredIndex == 1 ? "10m" : "100m"
          name = "deferred_blob_\(lengthName)"
          let logicalLength: Int64 = deferredIndex == 1 ? 10_485_760 : 104_857_600
          type = .binary(
            BinaryTypeDescriptor(
              isLargeObject: true, isInline: false, logicalLength: logicalLength,
              locatorLifetime: .cursorScoped, rawTypeName: "BLOB"))
          width = 200
        } else {
          role = .fillerText
          name = "column_\(ordinal)"
          type = .string(
            StringTypeDescriptor(
              length: 512, collation: "und-x-icu", charset: "UTF-8", rawTypeName: "TEXT"))
          width = 150
        }
        plans.append(
          FixtureColumnPlan(
            role: role,
            name: name,
            dataType: type,
            preferredWidth: width,
            isFrozen: false,
            isDeferred: isDeferredJSON || isDeferredBinary
          )
        )
      }
    }

    // BF-02 has the full normalized type matrix; BF-03 has exactly 500
    // columns and three frozen columns per the measurement contract.
    if spec.kind == .bf03Wide {
      plans = plans.enumerated().map { ordinal, plan in
        let nonFrozenWidths: [Double] = [80, 120, 180]
        let width =
          ordinal < spec.frozenColumnCount
          ? 120
          : nonFrozenWidths[(ordinal - spec.frozenColumnCount) % nonFrozenWidths.count]
        return FixtureColumnPlan(
          role: plan.role,
          name: plan.name,
          dataType: plan.dataType,
          preferredWidth: width,
          isFrozen: ordinal < spec.frozenColumnCount,
          isDeferred: plan.isDeferred
        )
      }
    }
    return plans
  }

  // MARK: Value generation

  private func hash(row: Int, column: Int, tag: String) -> UInt64 {
    var hasher = GridStableHasher()
    hasher.append("fixture-v1")
    hasher.append(spec.seed)
    hasher.append(tag)
    hasher.append(Int64(row))
    hasher.append(Int64(column))
    return hasher.value
  }

  private func makeValue(role: FixtureColumnRole, row: Int, column: Int) -> GridCellValue {
    let hash = hash(row: row, column: column, tag: role.rawValue)
    switch role {
    case .signedInteger:
      return .loaded(.signedInteger(Int64(row)))
    case .unsignedInteger:
      return .loaded(.unsignedInteger(UInt64(row) &* 17 &+ hash % 17))
    case .exactDecimal:
      let whole = Int64(row % 100_000)
      let fraction = Decimal(hash % 10_000) / Decimal(10_000)
      return .loaded(.decimal(Decimal(whole) + fraction))
    case .approximateDecimal:
      let value = Double(row % 100_000) / 37.0 + Double(hash % 10_000) / 10_000.0
      return .loaded(.floatingPoint(value))
    case .text:
      if row % 11 == 0 { return .loaded(.text("")) }
      if row % 29 == 0 { return .null }
      return .loaded(.text("row-\(row)-\(String(hash, radix: 16))"))
    case .boolean:
      if row % 29 == 0 { return .null }
      return .loaded(.boolean((hash & 1) == 0))
    case .date:
      if row % 29 == 0 { return .null }
      return .loaded(
        .date(GridDateValue(year: 2020 + row % 10, month: row % 12 + 1, day: row % 28 + 1)))
    case .time:
      return .loaded(.time(GridTimeValue(hour: row % 24, minute: row % 60, second: Int(hash % 60))))
    case .datetime:
      return .loaded(
        .datetime(
          GridDateTimeValue(
            epochMilliseconds: 1_700_000_000_000 + Int64(row) * 1_000, timezoneOffsetMinutes: 420,
            timezoneName: "Asia/Ho_Chi_Minh")))
    case .interval:
      return .loaded(
        .interval(
          GridIntervalValue(
            months: Int64(row % 12), days: Int64(row % 31), microseconds: Int64(hash % 1_000_000))))
    case .uuid:
      return .loaded(.uuid(deterministicUUID(hash: hash)))
    case .json:
      if row % 23 == 0 { return .notLoaded }
      if row % 29 == 0 { return .null }
      return .loaded(.json("{\"row\":\(row),\"hash\":\"\(String(hash, radix: 16))\"}"))
    case .xml:
      return .loaded(.xml("<row index=\"\(row)\" hash=\"\(String(hash, radix: 16))\"/>"))
    case .binary:
      if row % 17 == 0 { return .loaded(.binary(Data())) }
      if row % 31 == 0 { return .null }
      return .loaded(
        .binary(Data([UInt8(truncatingIfNeeded: hash), UInt8(truncatingIfNeeded: hash >> 8)])))
    case .enumeration:
      let labels = ["new", "ready", "failed"]
      return .loaded(.enumeration(labels[Int(hash % UInt64(labels.count))]))
    case .array:
      return .loaded(.array([.text("tag-\(row % 7)"), .signedInteger(Int64(row % 100))]))
    case .composite:
      return .loaded(
        .composite([
          GridCompositeField(name: "display_name", value: .text("user-\(row)")),
          GridCompositeField(name: "score", value: .signedInteger(Int64(hash % 100))),
        ]))
    case .spatial:
      let x = Double(row % 180) + Double(hash % 1_000) / 1_000
      let y = Double(row % 90) + Double(hash % 1_000) / 1_000
      return .loaded(
        .spatial(
          GridSpatialValue(
            subtype: "POINT", srid: 4326, encoded: String(format: "POINT(%.3f %.3f)", x, y))))
    case .network:
      return .loaded(.network(GridNetworkValue(family: "IPv4", value: "192.0.2.\(row % 254 + 1)")))
    case .bitString:
      return .loaded(
        .bitString(GridBitStringValue(bits: String(hash, radix: 2).leftPad(to: 16, with: "0"))))
    case .unknown:
      return .loaded(
        .unknown(
          GridUnknownValue(
            rawTypeIdentity: "vendor.custom_type", bytes: Data([UInt8(truncatingIfNeeded: hash)]))))
    case .wideText:
      return .loaded(.text(wideText(row: row, hash: hash)))
    case .deferredJSON:
      if row % 37 == 0 { return .notLoaded }
      return .deferred(
        makeDeferred(kind: .json, logicalLength: 1_048_576, row: row, column: column, hash: hash))
    case .deferredBinary:
      let logicalLength: Int64 = column == 27 ? 10_485_760 : 104_857_600
      if row % 41 == 0 { return .notLoaded }
      return .deferred(
        makeDeferred(
          kind: .binary, logicalLength: logicalLength, row: row, column: column, hash: hash))
    case .fillerText:
      if row % 29 == 0 { return .null }
      return .loaded(.text("cell-\(row)-\(column)-\(String(hash, radix: 16))"))
    }
  }

  private func wideText(row: Int, hash: UInt64) -> String {
    let targetBytes = 10_240
    let prefix = "row-\(row)-\(String(hash, radix: 16))-"
    let prefixCount = prefix.utf8.count
    let suffixCount = max(0, targetBytes - prefixCount)
    return prefix + String(repeating: "x", count: suffixCount)
  }

  private func makeDeferred(
    kind: DeferredValueKind,
    logicalLength: Int64,
    row: Int,
    column: Int,
    hash: UInt64
  ) -> DeferredValueMetadata {
    // A short preview is enough for the spike and makes it impossible for a
    // declared 1/10/100 MiB length to become a matching allocation.
    let previewLength = 128
    var bytes = Data(count: previewLength)
    for index in 0..<previewLength {
      bytes[index] = UInt8(truncatingIfNeeded: hash &+ UInt64(index))
    }
    return DeferredValueMetadata(
      kind: kind,
      logicalByteLength: logicalLength,
      locator: "fixture://\(spec.resultID.rawValue)/row/\(row)/column/\(column)",
      preview: bytes
    )
  }

  private func deterministicUUID(hash: UInt64) -> UUID {
    var bytes = [UInt8](repeating: 0, count: 16)
    var first = hash
    var second = hash &* 0x9E37_79B9_7F4A_7C15
    for index in 0..<8 {
      bytes[index] = UInt8(truncatingIfNeeded: first)
      first >>= 8
      bytes[index + 8] = UInt8(truncatingIfNeeded: second)
      second >>= 8
    }
    bytes[6] = (bytes[6] & 0x0F) | 0x40
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
      ))
  }

  // MARK: Checksums

  private func sampleIndices(count: Int) -> [Int] {
    guard spec.rowCount > count else { return Array(0..<spec.rowCount) }
    guard count > 1 else { return [0] }
    var indices: [Int] = []
    indices.reserveCapacity(count)
    let lastIndex = UInt64(spec.rowCount - 1)
    let denominator = UInt64(count - 1)
    let quotient = lastIndex / denominator
    let remainder = lastIndex % denominator
    for sample in 0..<count {
      let sampleValue = UInt64(sample)
      let index = sampleValue * quotient + (sampleValue * remainder) / denominator
      indices.append(Int(index))
    }
    return indices
  }

  private func append(type: NormalizedDataType, to hasher: inout GridStableHasher) {
    hasher.append(type.group.rawValue)
    hasher.append(type.rawTypeName)
    switch type {
    case .integer(let descriptor):
      hasher.append(descriptor.signedness.rawValue)
      hasher.append(Int64(descriptor.bitWidth ?? 0))
      hasher.append(Int64(descriptor.precision ?? 0))
    case .decimal(let descriptor):
      hasher.append(Int64(descriptor.precision ?? 0))
      hasher.append(Int64(descriptor.scale ?? 0))
      hasher.append(descriptor.exactness.rawValue)
    case .string(let descriptor):
      hasher.append(Int64(descriptor.length ?? 0))
      hasher.append(descriptor.collation ?? "")
      hasher.append(descriptor.charset ?? "")
      hasher.append(descriptor.isFixedLength)
    case .boolean(let descriptor):
      hasher.append(descriptor.representation.rawValue)
    case .date(let descriptor), .time(let descriptor), .datetime(let descriptor):
      hasher.append(descriptor.timezoneSemantics.rawValue)
      hasher.append(Int64(descriptor.precision ?? 0))
      hasher.append(descriptor.calendar ?? "")
    case .interval(let descriptor):
      hasher.append(descriptor.fields)
      hasher.append(Int64(descriptor.precision ?? 0))
    case .uuid(let descriptor):
      hasher.append(descriptor.physicalForm.rawValue)
    case .json(let descriptor):
      hasher.append(descriptor.physicalForm.rawValue)
      hasher.append(descriptor.validation ?? "")
    case .xml(let descriptor):
      hasher.append(descriptor.physicalForm.rawValue)
      hasher.append(descriptor.validation ?? "")
    case .binary(let descriptor):
      hasher.append(descriptor.isLargeObject)
      hasher.append(descriptor.isInline)
      hasher.append(descriptor.logicalLength ?? 0)
      hasher.append(descriptor.locatorLifetime.rawValue)
    case .enumeration(let descriptor):
      for label in descriptor.allowedLabels { hasher.append(label) }
      hasher.append(descriptor.baseType)
      for constraint in descriptor.constraints { hasher.append(constraint) }
    case .array(let descriptor):
      hasher.append(descriptor.elementType)
      for dimension in descriptor.dimensions { hasher.append(Int64(dimension ?? 0)) }
    case .composite(let descriptor):
      for field in descriptor.fields { hasher.append(field) }
    case .spatial(let descriptor):
      hasher.append(descriptor.subtype)
      hasher.append(Int64(descriptor.srid ?? 0))
      hasher.append(descriptor.encoding)
    case .network(let descriptor):
      hasher.append(descriptor.family)
      hasher.append(Int64(descriptor.length ?? 0))
    case .bitString(let descriptor):
      hasher.append(Int64(descriptor.length ?? 0))
    case .unknown(let descriptor):
      hasher.append(descriptor.rawTypeIdentity)
      hasher.append(descriptor.preservesLosslessBytes)
      hasher.append(descriptor.preservesLosslessText)
    }
  }

  private func append(value: GridCellValue, to hasher: inout GridStableHasher) {
    switch value {
    case .notLoaded:
      hasher.append("not-loaded")
    case .null:
      hasher.append("null")
    case .loaded(let normalized):
      append(normalized: normalized, to: &hasher)
    case .deferred(let metadata):
      hasher.append("deferred")
      hasher.append(metadata.kind.rawValue)
      hasher.append(metadata.logicalByteLength)
      hasher.append(metadata.locator)
      hasher.append(metadata.preview)
    }
  }

  private func append(normalized: GridNormalizedValue, to hasher: inout GridStableHasher) {
    switch normalized {
    case .signedInteger(let value):
      hasher.append("i")
      hasher.append(value)
    case .unsignedInteger(let value):
      hasher.append("u")
      hasher.append(value)
    case .decimal(let value):
      hasher.append("d")
      hasher.append(NSDecimalNumber(decimal: value).stringValue)
    case .floatingPoint(let value):
      hasher.append("f")
      hasher.append(value.bitPattern)
    case .text(let value):
      hasher.append("t")
      hasher.append(value)
    case .boolean(let value):
      hasher.append("b")
      hasher.append(value)
    case .date(let value):
      hasher.append("date")
      hasher.append(Int64(value.year))
      hasher.append(Int64(value.month))
      hasher.append(Int64(value.day))
    case .time(let value):
      hasher.append("time")
      hasher.append(Int64(value.hour))
      hasher.append(Int64(value.minute))
      hasher.append(Int64(value.second))
      hasher.append(Int64(value.nanosecond))
    case .datetime(let value):
      hasher.append("datetime")
      hasher.append(value.epochMilliseconds)
      hasher.append(Int64(value.timezoneOffsetMinutes ?? 0))
      hasher.append(value.timezoneName ?? "")
    case .interval(let value):
      hasher.append("interval")
      hasher.append(value.months)
      hasher.append(value.days)
      hasher.append(value.microseconds)
    case .uuid(let value):
      hasher.append("uuid")
      hasher.append(value.uuidString)
    case .json(let value):
      hasher.append("json")
      hasher.append(value)
    case .xml(let value):
      hasher.append("xml")
      hasher.append(value)
    case .binary(let value):
      hasher.append("binary")
      hasher.append(value)
    case .enumeration(let value):
      hasher.append("enum")
      hasher.append(value)
    case .array(let values):
      hasher.append("array")
      for value in values { append(normalized: value, to: &hasher) }
    case .composite(let fields):
      hasher.append("composite")
      for field in fields {
        hasher.append(field.name)
        append(normalized: field.value, to: &hasher)
      }
    case .spatial(let value):
      hasher.append("spatial")
      hasher.append(value.subtype)
      hasher.append(Int64(value.srid ?? 0))
      hasher.append(value.encoded)
    case .network(let value):
      hasher.append("network")
      hasher.append(value.family)
      hasher.append(value.value)
    case .bitString(let value):
      hasher.append("bits")
      hasher.append(value.bits)
    case .unknown(let value):
      hasher.append("unknown")
      hasher.append(value.rawTypeIdentity)
      if let bytes = value.bytes { hasher.append(bytes) }
      if let text = value.text { hasher.append(text) }
    }
  }
}

extension String {
  fileprivate func leftPad(to length: Int, with character: Character) -> String {
    guard count < length else { return String(prefix(length)) }
    return String(repeating: String(character), count: length - count) + self
  }
}
