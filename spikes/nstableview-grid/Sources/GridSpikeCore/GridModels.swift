import Foundation

// MARK: - Stable identities

/// A small, deterministic FNV-1a implementation used by the disposable
/// fixture.  It deliberately has a fixed byte order so checksums and IDs do
/// not change between Apple Silicon machines.
@usableFromInline
internal struct GridStableHasher: Sendable {
  @usableFromInline
  internal private(set) var value: UInt64 = 14_695_981_039_346_656_037

  @usableFromInline
  internal mutating func append(byte: UInt8) {
    value ^= UInt64(byte)
    value &*= 1_099_511_628_211
  }

  @usableFromInline
  internal mutating func append(_ bytes: some Sequence<UInt8>) {
    for byte in bytes {
      append(byte: byte)
    }
  }

  @usableFromInline
  internal mutating func append(_ string: String) {
    append(string.utf8)
    append(byte: 0)
  }

  @usableFromInline
  internal mutating func append(_ value: UInt64) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { append($0) }
  }

  @usableFromInline
  internal mutating func append(_ value: Int64) {
    append(UInt64(bitPattern: value))
  }

  @usableFromInline
  internal mutating func append(_ value: Bool) {
    append(byte: value ? 1 : 0)
  }

  @usableFromInline
  internal mutating func append(_ value: Data) {
    for byte in value {
      append(byte: byte)
    }
    append(byte: 0)
  }
}

/// Identity of one logical result.  It is not a database identifier; the
/// synthetic fixture derives it from its kind, dimensions and seed.
public struct ResultID: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
  public let rawValue: UInt64

  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  public init(_ rawValue: UInt64) {
    self.init(rawValue: rawValue)
  }

  public init(seed: UInt64, namespace: String = "result") {
    var hasher = GridStableHasher()
    hasher.append(namespace)
    hasher.append(seed)
    self.rawValue = hasher.value
  }

  public var value: UInt64 { rawValue }

  public var description: String {
    String(format: "result-%016llx", rawValue)
  }

  public static func < (lhs: ResultID, rhs: ResultID) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// Stable logical row identity.  The offset is retained as a logical key and
/// is independent of page-cache eviction or view reuse.
public struct RowID: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
  public let resultID: ResultID
  public let logicalIndex: Int

  public init(resultID: ResultID, logicalIndex: Int) {
    self.resultID = resultID
    self.logicalIndex = logicalIndex
  }

  public init(resultID: ResultID, index: Int) {
    self.init(resultID: resultID, logicalIndex: index)
  }

  public init(resultID: ResultID, offset: Int) {
    self.init(resultID: resultID, logicalIndex: offset)
  }

  public var index: Int { logicalIndex }
  public var offset: Int { logicalIndex }

  public var description: String {
    "\(resultID.description)/row-\(logicalIndex)"
  }

  public static func < (lhs: RowID, rhs: RowID) -> Bool {
    if lhs.resultID != rhs.resultID { return lhs.resultID < rhs.resultID }
    return lhs.logicalIndex < rhs.logicalIndex
  }
}

/// Stable logical column identity.  Equality intentionally uses `rawValue`
/// only: changing the ordinal (for example after a reorder) must not change
/// the identity of a column.
public struct ColumnID: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
  public let rawValue: UInt64
  public let name: String
  public let ordinal: Int

  public init(rawValue: UInt64, name: String = "", ordinal: Int = 0) {
    self.rawValue = rawValue
    self.name = name
    self.ordinal = ordinal
  }

  public init(resultID: ResultID, name: String, ordinal: Int = 0) {
    var hasher = GridStableHasher()
    hasher.append("column")
    hasher.append(resultID.rawValue)
    hasher.append(name)
    self.init(rawValue: hasher.value, name: name, ordinal: ordinal)
  }

  public init(resultID: ResultID, index: Int, name: String? = nil) {
    let resolvedName = name ?? "column_\(index)"
    self.init(resultID: resultID, name: resolvedName, ordinal: index)
  }

  public var value: UInt64 { rawValue }
  public var description: String {
    if name.isEmpty { return String(format: "column-%016llx", rawValue) }
    return name
  }

  public static func < (lhs: ColumnID, rhs: ColumnID) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  public static func == (lhs: ColumnID, rhs: ColumnID) -> Bool {
    lhs.rawValue == rhs.rawValue
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(rawValue)
  }
}

public struct CellID: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
  public let rowID: RowID
  public let columnID: ColumnID
  public let rawValue: UInt64

  public init(rowID: RowID, columnID: ColumnID) {
    self.rowID = rowID
    self.columnID = columnID
    var hasher = GridStableHasher()
    hasher.append("cell")
    hasher.append(rowID.resultID.rawValue)
    hasher.append(Int64(rowID.logicalIndex))
    hasher.append(columnID.rawValue)
    self.rawValue = hasher.value
  }

  public init(rawValue: UInt64, rowID: RowID, columnID: ColumnID) {
    self.rawValue = rawValue
    self.rowID = rowID
    self.columnID = columnID
  }

  public var description: String {
    "\(rowID.description)/\(columnID.description)"
  }

  public static func < (lhs: CellID, rhs: CellID) -> Bool {
    if lhs.rowID != rhs.rowID { return lhs.rowID < rhs.rowID }
    return lhs.columnID < rhs.columnID
  }
}

// MARK: - Normalized data type taxonomy

public enum NormalizedDataTypeGroup: String, CaseIterable, Codable, Hashable, Sendable {
  case integer
  case decimal
  case string
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
}

public enum IntegerSignedness: String, Codable, Hashable, Sendable {
  case signed
  case unsigned
  case unspecified
}

public enum NumericExactness: String, Codable, Hashable, Sendable {
  case exact
  case approximate
}

public enum BooleanRepresentation: String, Codable, Hashable, Sendable {
  case native
  case emulated
}

public enum TemporalTimezoneSemantics: String, Codable, Hashable, Sendable {
  case none
  case fixedOffset
  case namedZone
  case engineDefined
}

public enum UUIDPhysicalForm: String, Codable, Hashable, Sendable {
  case native
  case binary
  case text
}

public enum JSONPhysicalForm: String, Codable, Hashable, Sendable {
  case text
  case binary
}

public enum BinaryLocatorLifetime: String, Codable, Hashable, Sendable {
  case valueOwned
  case cursorScoped
  case sessionScoped
  case external
}

public struct IntegerTypeDescriptor: Codable, Hashable, Sendable {
  public let signedness: IntegerSignedness
  public let bitWidth: Int?
  public let precision: Int?
  public let rawTypeName: String

  public init(
    signedness: IntegerSignedness,
    bitWidth: Int? = nil,
    precision: Int? = nil,
    rawTypeName: String = "integer"
  ) {
    self.signedness = signedness
    self.bitWidth = bitWidth
    self.precision = precision
    self.rawTypeName = rawTypeName
  }
}

public struct DecimalTypeDescriptor: Codable, Hashable, Sendable {
  public let precision: Int?
  public let scale: Int?
  public let exactness: NumericExactness
  public let rawTypeName: String

  public init(
    precision: Int? = nil,
    scale: Int? = nil,
    exactness: NumericExactness = .exact,
    rawTypeName: String = "decimal"
  ) {
    self.precision = precision
    self.scale = scale
    self.exactness = exactness
    self.rawTypeName = rawTypeName
  }
}

public struct StringTypeDescriptor: Codable, Hashable, Sendable {
  public let length: Int?
  public let collation: String?
  public let charset: String?
  public let isFixedLength: Bool
  public let rawTypeName: String

  public init(
    length: Int? = nil,
    collation: String? = nil,
    charset: String? = nil,
    isFixedLength: Bool = false,
    rawTypeName: String = "text"
  ) {
    self.length = length
    self.collation = collation
    self.charset = charset
    self.isFixedLength = isFixedLength
    self.rawTypeName = rawTypeName
  }
}

public struct BooleanTypeDescriptor: Codable, Hashable, Sendable {
  public let representation: BooleanRepresentation
  public let rawTypeName: String

  public init(
    representation: BooleanRepresentation = .native,
    rawTypeName: String = "boolean"
  ) {
    self.representation = representation
    self.rawTypeName = rawTypeName
  }
}

public struct TemporalTypeDescriptor: Codable, Hashable, Sendable {
  public let timezoneSemantics: TemporalTimezoneSemantics
  public let precision: Int?
  public let calendar: String?
  public let rawTypeName: String

  public init(
    timezoneSemantics: TemporalTimezoneSemantics = .none,
    precision: Int? = nil,
    calendar: String? = nil,
    rawTypeName: String
  ) {
    self.timezoneSemantics = timezoneSemantics
    self.precision = precision
    self.calendar = calendar
    self.rawTypeName = rawTypeName
  }
}

public struct IntervalTypeDescriptor: Codable, Hashable, Sendable {
  public let fields: String
  public let precision: Int?
  public let rawTypeName: String

  public init(
    fields: String = "day to second", precision: Int? = nil, rawTypeName: String = "interval"
  ) {
    self.fields = fields
    self.precision = precision
    self.rawTypeName = rawTypeName
  }
}

public struct UUIDTypeDescriptor: Codable, Hashable, Sendable {
  public let physicalForm: UUIDPhysicalForm
  public let rawTypeName: String

  public init(physicalForm: UUIDPhysicalForm = .native, rawTypeName: String = "uuid") {
    self.physicalForm = physicalForm
    self.rawTypeName = rawTypeName
  }
}

public struct JSONTypeDescriptor: Codable, Hashable, Sendable {
  public let physicalForm: JSONPhysicalForm
  public let validation: String?
  public let rawTypeName: String

  public init(
    physicalForm: JSONPhysicalForm,
    validation: String? = nil,
    rawTypeName: String = "json"
  ) {
    self.physicalForm = physicalForm
    self.validation = validation
    self.rawTypeName = rawTypeName
  }
}

public struct XMLTypeDescriptor: Codable, Hashable, Sendable {
  public let physicalForm: JSONPhysicalForm
  public let validation: String?
  public let rawTypeName: String

  public init(
    physicalForm: JSONPhysicalForm = .text,
    validation: String? = nil,
    rawTypeName: String = "xml"
  ) {
    self.physicalForm = physicalForm
    self.validation = validation
    self.rawTypeName = rawTypeName
  }
}

public struct BinaryTypeDescriptor: Codable, Hashable, Sendable {
  public let isLargeObject: Bool
  public let isInline: Bool
  public let logicalLength: Int64?
  public let locatorLifetime: BinaryLocatorLifetime
  public let rawTypeName: String

  public init(
    isLargeObject: Bool = false,
    isInline: Bool = true,
    logicalLength: Int64? = nil,
    locatorLifetime: BinaryLocatorLifetime = .valueOwned,
    rawTypeName: String = "binary"
  ) {
    self.isLargeObject = isLargeObject
    self.isInline = isInline
    self.logicalLength = logicalLength
    self.locatorLifetime = locatorLifetime
    self.rawTypeName = rawTypeName
  }
}

public struct EnumTypeDescriptor: Codable, Hashable, Sendable {
  public let allowedLabels: [String]
  public let baseType: String
  public let constraints: [String]
  public let rawTypeName: String

  public init(
    allowedLabels: [String],
    baseType: String = "text",
    constraints: [String] = [],
    rawTypeName: String = "enum"
  ) {
    self.allowedLabels = allowedLabels
    self.baseType = baseType
    self.constraints = constraints
    self.rawTypeName = rawTypeName
  }
}

public struct ArrayTypeDescriptor: Codable, Hashable, Sendable {
  public let elementType: String
  public let dimensions: [Int?]
  public let rawTypeName: String

  public init(elementType: String, dimensions: [Int?] = [], rawTypeName: String = "array") {
    self.elementType = elementType
    self.dimensions = dimensions
    self.rawTypeName = rawTypeName
  }
}

public struct CompositeTypeDescriptor: Codable, Hashable, Sendable {
  public let fields: [String]
  public let rawTypeName: String

  public init(fields: [String], rawTypeName: String = "composite") {
    self.fields = fields
    self.rawTypeName = rawTypeName
  }
}

public struct SpatialTypeDescriptor: Codable, Hashable, Sendable {
  public let subtype: String
  public let srid: Int?
  public let encoding: String
  public let rawTypeName: String

  public init(
    subtype: String, srid: Int? = nil, encoding: String = "WKB", rawTypeName: String = "geometry"
  ) {
    self.subtype = subtype
    self.srid = srid
    self.encoding = encoding
    self.rawTypeName = rawTypeName
  }
}

public struct NetworkTypeDescriptor: Codable, Hashable, Sendable {
  public let family: String
  public let length: Int?
  public let rawTypeName: String

  public init(family: String, length: Int? = nil, rawTypeName: String = "network") {
    self.family = family
    self.length = length
    self.rawTypeName = rawTypeName
  }
}

public struct BitStringTypeDescriptor: Codable, Hashable, Sendable {
  public let length: Int?
  public let rawTypeName: String

  public init(length: Int? = nil, rawTypeName: String = "bit") {
    self.length = length
    self.rawTypeName = rawTypeName
  }
}

public struct UnknownTypeDescriptor: Codable, Hashable, Sendable {
  public let rawTypeIdentity: String
  public let preservesLosslessBytes: Bool
  public let preservesLosslessText: Bool

  public init(
    rawTypeIdentity: String, preservesLosslessBytes: Bool = true, preservesLosslessText: Bool = true
  ) {
    self.rawTypeIdentity = rawTypeIdentity
    self.preservesLosslessBytes = preservesLosslessBytes
    self.preservesLosslessText = preservesLosslessText
  }
}

public enum NormalizedDataType: Codable, Hashable, Sendable {
  case integer(IntegerTypeDescriptor)
  case decimal(DecimalTypeDescriptor)
  case string(StringTypeDescriptor)
  case boolean(BooleanTypeDescriptor)
  case date(TemporalTypeDescriptor)
  case time(TemporalTypeDescriptor)
  case datetime(TemporalTypeDescriptor)
  case interval(IntervalTypeDescriptor)
  case uuid(UUIDTypeDescriptor)
  case json(JSONTypeDescriptor)
  case xml(XMLTypeDescriptor)
  case binary(BinaryTypeDescriptor)
  case enumeration(EnumTypeDescriptor)
  case array(ArrayTypeDescriptor)
  case composite(CompositeTypeDescriptor)
  case spatial(SpatialTypeDescriptor)
  case network(NetworkTypeDescriptor)
  case bitString(BitStringTypeDescriptor)
  case unknown(UnknownTypeDescriptor)

  public var group: NormalizedDataTypeGroup {
    switch self {
    case .integer: .integer
    case .decimal: .decimal
    case .string: .string
    case .boolean: .boolean
    case .date: .date
    case .time: .time
    case .datetime: .datetime
    case .interval: .interval
    case .uuid: .uuid
    case .json: .json
    case .xml: .xml
    case .binary: .binary
    case .enumeration: .enumeration
    case .array: .array
    case .composite: .composite
    case .spatial: .spatial
    case .network: .network
    case .bitString: .bitString
    case .unknown: .unknown
    }
  }

  public var normalizedGroup: NormalizedDataTypeGroup { group }

  public var rawTypeName: String {
    switch self {
    case .integer(let descriptor): descriptor.rawTypeName
    case .decimal(let descriptor): descriptor.rawTypeName
    case .string(let descriptor): descriptor.rawTypeName
    case .boolean(let descriptor): descriptor.rawTypeName
    case .date(let descriptor), .time(let descriptor), .datetime(let descriptor):
      descriptor.rawTypeName
    case .interval(let descriptor): descriptor.rawTypeName
    case .uuid(let descriptor): descriptor.rawTypeName
    case .json(let descriptor): descriptor.rawTypeName
    case .xml(let descriptor): descriptor.rawTypeName
    case .binary(let descriptor): descriptor.rawTypeName
    case .enumeration(let descriptor): descriptor.rawTypeName
    case .array(let descriptor): descriptor.rawTypeName
    case .composite(let descriptor): descriptor.rawTypeName
    case .spatial(let descriptor): descriptor.rawTypeName
    case .network(let descriptor): descriptor.rawTypeName
    case .bitString(let descriptor): descriptor.rawTypeName
    case .unknown(let descriptor): descriptor.rawTypeIdentity
    }
  }
}

// MARK: - Typed values and deferred metadata

public struct GridDateValue: Codable, Hashable, Sendable {
  public let year: Int
  public let month: Int
  public let day: Int

  public init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }
}

public struct GridTimeValue: Codable, Hashable, Sendable {
  public let hour: Int
  public let minute: Int
  public let second: Int
  public let nanosecond: Int

  public init(hour: Int, minute: Int, second: Int, nanosecond: Int = 0) {
    self.hour = hour
    self.minute = minute
    self.second = second
    self.nanosecond = nanosecond
  }
}

public struct GridDateTimeValue: Codable, Hashable, Sendable {
  public let epochMilliseconds: Int64
  public let timezoneOffsetMinutes: Int?
  public let timezoneName: String?

  public init(
    epochMilliseconds: Int64, timezoneOffsetMinutes: Int? = nil, timezoneName: String? = nil
  ) {
    self.epochMilliseconds = epochMilliseconds
    self.timezoneOffsetMinutes = timezoneOffsetMinutes
    self.timezoneName = timezoneName
  }
}

public struct GridIntervalValue: Codable, Hashable, Sendable {
  public let months: Int64
  public let days: Int64
  public let microseconds: Int64

  public init(months: Int64 = 0, days: Int64 = 0, microseconds: Int64 = 0) {
    self.months = months
    self.days = days
    self.microseconds = microseconds
  }
}

public struct GridCompositeField: Codable, Hashable, Sendable {
  public let name: String
  public let value: GridNormalizedValue

  public init(name: String, value: GridNormalizedValue) {
    self.name = name
    self.value = value
  }
}

public struct GridSpatialValue: Codable, Hashable, Sendable {
  public let subtype: String
  public let srid: Int?
  public let encoded: String

  public init(subtype: String, srid: Int?, encoded: String) {
    self.subtype = subtype
    self.srid = srid
    self.encoded = encoded
  }
}

public struct GridNetworkValue: Codable, Hashable, Sendable {
  public let family: String
  public let value: String

  public init(family: String, value: String) {
    self.family = family
    self.value = value
  }
}

public struct GridBitStringValue: Codable, Hashable, Sendable {
  public let bits: String

  public init(bits: String) {
    self.bits = bits
  }
}

public struct GridUnknownValue: Codable, Hashable, Sendable {
  public let rawTypeIdentity: String
  public let bytes: Data?
  public let text: String?

  public init(rawTypeIdentity: String, bytes: Data? = nil, text: String? = nil) {
    self.rawTypeIdentity = rawTypeIdentity
    self.bytes = bytes
    self.text = text
  }
}

public indirect enum GridNormalizedValue: Codable, Hashable, Sendable {
  case signedInteger(Int64)
  case unsignedInteger(UInt64)
  case decimal(Decimal)
  case floatingPoint(Double)
  case text(String)
  case boolean(Bool)
  case date(GridDateValue)
  case time(GridTimeValue)
  case datetime(GridDateTimeValue)
  case interval(GridIntervalValue)
  case uuid(UUID)
  case json(String)
  case xml(String)
  case binary(Data)
  case enumeration(String)
  case array([GridNormalizedValue])
  case composite([GridCompositeField])
  case spatial(GridSpatialValue)
  case network(GridNetworkValue)
  case bitString(GridBitStringValue)
  case unknown(GridUnknownValue)

  public var isEmptyText: Bool {
    if case .text(let value) = self { return value.isEmpty }
    return false
  }

  public var isEmptyBinary: Bool {
    if case .binary(let value) = self { return value.isEmpty }
    return false
  }

  public var approximateByteCount: Int {
    switch self {
    case .signedInteger, .unsignedInteger, .floatingPoint, .boolean: 8
    case .decimal: 16
    case .text(let value), .json(let value), .xml(let value), .enumeration(let value):
      value.utf8.count
    case .date: 12
    case .time: 16
    case .datetime: 24
    case .interval: 24
    case .uuid: 16
    case .binary(let value): value.count
    case .array(let values):
      values.reduce(0) { saturatingAdd($0, $1.approximateByteCount) }
    case .composite(let fields):
      fields.reduce(0) { saturatingAdd($0, $1.name.utf8.count + $1.value.approximateByteCount) }
    case .spatial(let value): value.encoded.utf8.count + 16
    case .network(let value): value.family.utf8.count + value.value.utf8.count
    case .bitString(let value): value.bits.utf8.count
    case .unknown(let value):
      (value.bytes?.count ?? 0) + (value.text?.utf8.count ?? 0) + value.rawTypeIdentity.utf8.count
    }
  }
}

public enum DeferredValueKind: String, Codable, Hashable, Sendable {
  case json
  case binary
}

/// Metadata for a value that is intentionally not materialized.  `logicalByteLength`
/// is a claim about the remote value; it never controls allocation in this
/// spike.  Preview is bounded to 64 KiB by the initializer.
public struct DeferredValueMetadata: Codable, Hashable, Sendable {
  public static let maximumPreviewBytes = 64 * 1_024

  public let kind: DeferredValueKind
  public let logicalByteLength: Int64
  public let locator: String
  public let preview: Data

  public init(
    kind: DeferredValueKind,
    logicalByteLength: Int64,
    locator: String,
    preview: Data = Data()
  ) {
    self.kind = kind
    self.logicalByteLength = max(0, logicalByteLength)
    self.locator = locator
    self.preview = preview.prefix(Self.maximumPreviewBytes)
  }

  public var logicalLength: Int64 { logicalByteLength }
  public var previewByteCount: Int { preview.count }
  public var isMaterialized: Bool { false }
  public var approximateByteCount: Int {
    saturatingAdd(locator.utf8.count, preview.count)
  }
}

public enum GridCellValue: Codable, Hashable, Sendable {
  case notLoaded
  case null
  case loaded(GridNormalizedValue)
  case deferred(DeferredValueMetadata)

  public var isNotLoaded: Bool {
    if case .notLoaded = self { return true }
    return false
  }

  public var isNull: Bool {
    if case .null = self { return true }
    return false
  }

  public var isDeferred: Bool {
    if case .deferred = self { return true }
    return false
  }

  public var normalizedValue: GridNormalizedValue? {
    if case .loaded(let value) = self { return value }
    return nil
  }

  public var deferredMetadata: DeferredValueMetadata? {
    if case .deferred(let metadata) = self { return metadata }
    return nil
  }

  public var approximateByteCount: Int {
    switch self {
    case .notLoaded, .null: 0
    case .loaded(let value): value.approximateByteCount
    case .deferred(let metadata): metadata.approximateByteCount
    }
  }
}

public typealias GridValue = GridCellValue

// MARK: - Schema and row records

public struct GridColumn: Codable, Hashable, Sendable {
  public let id: ColumnID
  public let ordinal: Int
  public let name: String
  public let dataType: NormalizedDataType
  public let isFrozen: Bool
  public let preferredWidth: Double
  public let isDeferred: Bool

  public init(
    id: ColumnID,
    ordinal: Int,
    name: String,
    dataType: NormalizedDataType,
    isFrozen: Bool = false,
    preferredWidth: Double = 120,
    isDeferred: Bool = false
  ) {
    self.id = id
    self.ordinal = ordinal
    self.name = name
    self.dataType = dataType
    self.isFrozen = isFrozen
    self.preferredWidth = preferredWidth
    self.isDeferred = isDeferred
  }

  public var normalizedType: NormalizedDataType { dataType }
  public var typeGroup: NormalizedDataTypeGroup { dataType.group }
}

public struct GridSchema: Codable, Hashable, Sendable {
  public let resultID: ResultID
  public let columns: [GridColumn]

  public init(resultID: ResultID, columns: [GridColumn]) {
    self.resultID = resultID
    self.columns = columns
  }

  public var columnCount: Int { columns.count }

  public func column(at ordinal: Int) -> GridColumn? {
    guard columns.indices.contains(ordinal) else { return nil }
    return columns[ordinal]
  }

  public func column(id: ColumnID) -> GridColumn? {
    columns.first { $0.id == id }
  }
}

public struct GridCell: Codable, Hashable, Sendable {
  public let id: CellID
  public let rowID: RowID
  public let columnID: ColumnID
  public let ordinal: Int
  public let dataType: NormalizedDataType
  public let value: GridCellValue

  public init(
    id: CellID,
    rowID: RowID,
    columnID: ColumnID,
    ordinal: Int,
    dataType: NormalizedDataType,
    value: GridCellValue
  ) {
    self.id = id
    self.rowID = rowID
    self.columnID = columnID
    self.ordinal = ordinal
    self.dataType = dataType
    self.value = value
  }

  public var approximateByteCount: Int {
    // Include only resident payload and a small fixed record estimate; a
    // deferred logical length is deliberately excluded.
    saturatingAdd(64, value.approximateByteCount)
  }
}

public struct GridRow: Codable, Hashable, Sendable {
  public let id: RowID
  public let logicalIndex: Int
  public let cells: [GridCell]

  public init(id: RowID, logicalIndex: Int, cells: [GridCell]) {
    self.id = id
    self.logicalIndex = logicalIndex
    self.cells = cells
  }

  public var index: Int { logicalIndex }
  public var approximateByteCount: Int {
    cells.reduce(32) { saturatingAdd($0, $1.approximateByteCount) }
  }

  public func cell(at ordinal: Int) -> GridCell? {
    guard cells.indices.contains(ordinal) else { return nil }
    return cells[ordinal]
  }
}

// MARK: - Fixture configuration and summary

public enum GridFixtureKind: String, Codable, Hashable, Sendable {
  case bf02Million
  case bf02TenMillion
  case bf03Wide
  case custom
}

public enum GridFixtureConfigurationError: Error, Codable, Equatable, Sendable,
  CustomStringConvertible
{
  case invalidRowCount(Int)
  case invalidColumnCount(Int)
  case invalidSeed
  case unsupportedKind(GridFixtureKind)

  public var description: String {
    switch self {
    case .invalidRowCount(let value): "Row count must be positive and fit in Int (got \(value))."
    case .invalidColumnCount(let value):
      "Column count must be in 1...\(GridFixtureSpec.maximumColumnCount) (got \(value))."
    case .invalidSeed: "Fixture seed must be deterministic and non-zero."
    case .unsupportedKind(let kind): "Unsupported fixture kind: \(kind.rawValue)."
    }
  }
}

public struct GridFixtureSpec: Codable, Hashable, Sendable {
  public static let maximumColumnCount = 500

  public let kind: GridFixtureKind
  public let rowCount: Int
  public let columnCount: Int
  public let seed: UInt64
  public let resultID: ResultID
  public let frozenColumnCount: Int
  public let wideTextColumnCount: Int

  public init(
    kind: GridFixtureKind = .custom,
    rowCount: Int,
    columnCount: Int,
    seed: UInt64 = 0x4441_5441_464F_5247,
    resultID: ResultID? = nil,
    frozenColumnCount: Int = 0,
    wideTextColumnCount: Int = 0
  ) throws {
    guard rowCount > 0 else { throw GridFixtureConfigurationError.invalidRowCount(rowCount) }
    guard (1...Self.maximumColumnCount).contains(columnCount) else {
      throw GridFixtureConfigurationError.invalidColumnCount(columnCount)
    }
    guard seed != 0 else { throw GridFixtureConfigurationError.invalidSeed }
    let boundedFrozen = min(max(frozenColumnCount, 0), columnCount)
    let boundedWide = min(max(wideTextColumnCount, 0), columnCount)
    self.kind = kind
    self.rowCount = rowCount
    self.columnCount = columnCount
    self.seed = seed
    self.resultID =
      resultID ?? ResultID(seed: seed, namespace: "\(kind.rawValue)-\(rowCount)-\(columnCount)")
    self.frozenColumnCount = boundedFrozen
    self.wideTextColumnCount = boundedWide
  }

  private init(
    kind: GridFixtureKind,
    rowCount: Int,
    columnCount: Int,
    seed: UInt64,
    frozenColumnCount: Int,
    wideTextColumnCount: Int
  ) {
    self.kind = kind
    self.rowCount = rowCount
    self.columnCount = columnCount
    self.seed = seed
    self.resultID = ResultID(seed: seed, namespace: "\(kind.rawValue)-\(rowCount)-\(columnCount)")
    self.frozenColumnCount = frozenColumnCount
    self.wideTextColumnCount = wideTextColumnCount
  }

  public static let bf02Million = GridFixtureSpec(
    kind: .bf02Million,
    rowCount: 1_000_000,
    columnCount: 21,
    seed: 0xBF02_0001,
    frozenColumnCount: 0,
    wideTextColumnCount: 0
  )

  public static let bf02TenMillion = GridFixtureSpec(
    kind: .bf02TenMillion,
    rowCount: 10_000_000,
    columnCount: 21,
    seed: 0xBF02_000A,
    frozenColumnCount: 0,
    wideTextColumnCount: 0
  )

  public static let bf03Wide = GridFixtureSpec(
    kind: .bf03Wide,
    rowCount: 100_000,
    columnCount: 500,
    seed: 0xBF03_0500,
    frozenColumnCount: 3,
    wideTextColumnCount: 5
  )

  public static let bf02 = bf02Million
  public static let bf03 = bf03Wide
}

public struct FixtureChecksumSummary: Codable, Hashable, Sendable {
  public let algorithm: String
  public let schemaChecksum: UInt64
  public let rowChecksum: UInt64
  public let cellChecksum: UInt64
  public let combinedChecksum: UInt64
  public let sampledRowCount: Int
  public let sampledCellCount: Int
  public let logicalRowCount: Int
  public let logicalColumnCount: Int

  public init(
    algorithm: String = "fnv1a64-grid-v1",
    schemaChecksum: UInt64,
    rowChecksum: UInt64,
    cellChecksum: UInt64,
    combinedChecksum: UInt64,
    sampledRowCount: Int,
    sampledCellCount: Int,
    logicalRowCount: Int,
    logicalColumnCount: Int
  ) {
    self.algorithm = algorithm
    self.schemaChecksum = schemaChecksum
    self.rowChecksum = rowChecksum
    self.cellChecksum = cellChecksum
    self.combinedChecksum = combinedChecksum
    self.sampledRowCount = sampledRowCount
    self.sampledCellCount = sampledCellCount
    self.logicalRowCount = logicalRowCount
    self.logicalColumnCount = logicalColumnCount
  }

  public var checksum: UInt64 { combinedChecksum }
}

public typealias GridFixtureChecksum = FixtureChecksumSummary

@inline(__always)
internal func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
  let (result, overflow) = lhs.addingReportingOverflow(rhs)
  return overflow ? Int.max : result
}
