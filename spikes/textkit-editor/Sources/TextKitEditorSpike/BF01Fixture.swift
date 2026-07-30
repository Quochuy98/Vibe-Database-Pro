import CryptoKit
import Foundation

public struct BF01Fixture: Sendable {
  public static let findNeedle = "BF01_FIRST_RESULT_7D51A8C2"
  public static let nearEndNeedle = "BF01_NEAR_END_RESULT_92E4C6B1"
  public static let generatorRevision = 1

  public let text: String
  public let byteCount: Int
  public let utf16UnitCount: Int
  public let lineCount: Int
  public let statementCount: Int
  public let findNeedleSpan: TextSpan
  public let nearEndNeedleSpan: TextSpan
  public let fingerprint: String

}

public enum BF01Size: Int, CaseIterable, Codable, Sendable {
  case tenMiB = 10
  case oneHundredMiB = 100

  public var byteCount: Int {
    rawValue * 1_024 * 1_024
  }
}

public enum BF01FixtureGenerator {
  public static let statementCount = 100_000
  public static let maximumTargetBytes = BF01Size.oneHundredMiB.byteCount

  public static func make(size: BF01Size) throws -> BF01Fixture {
    try make(targetBytes: size.byteCount)
  }

  public static func make(targetBytes: Int) throws -> BF01Fixture {
    guard targetBytes > 0, targetBytes <= maximumTargetBytes else {
      throw EditorSpikeError.documentLimitExceeded(
        actualBytes: targetBytes,
        maximumBytes: maximumTargetBytes
      )
    }
    var bytes = [UInt8]()
    bytes.reserveCapacity(targetBytes)

    for index in 0..<statementCount {
      append(statement(index: index), to: &bytes)
    }

    let markerBytes = Array("-- \(BF01Fixture.findNeedle) synthetic find marker\n".utf8)
    let nearEndMarkerBytes = Array(
      "-- \(BF01Fixture.nearEndNeedle) synthetic near-end marker\n".utf8
    )
    let nearEndPadding = 4_096
    guard
      bytes.count + markerBytes.count + nearEndMarkerBytes.count + nearEndPadding
        <= targetBytes
    else {
      throw EditorSpikeError.fixtureCannotFit(
        targetBytes: targetBytes,
        requiredBytes: bytes.count + markerBytes.count + nearEndMarkerBytes.count
          + nearEndPadding
      )
    }

    let midpoint = targetBytes / 2
    if bytes.count < midpoint {
      appendFiller(to: &bytes, until: midpoint)
    }
    bytes.append(contentsOf: markerBytes)
    appendFiller(to: &bytes, until: targetBytes - nearEndMarkerBytes.count - nearEndPadding)
    bytes.append(contentsOf: nearEndMarkerBytes)
    appendFiller(to: &bytes, until: targetBytes)

    let text = String(decoding: bytes, as: UTF8.self)
    let nsText = text as NSString
    let markerRange = nsText.range(of: BF01Fixture.findNeedle)
    let nearEndMarkerRange = nsText.range(of: BF01Fixture.nearEndNeedle)
    let lineCount =
      bytes.reduce(into: 0) { count, byte in
        if byte == 0x0A {
          count += 1
        }
      } + (bytes.last == 0x0A ? 0 : 1)
    let fingerprint = sha256Hex(bytes)

    return BF01Fixture(
      text: text,
      byteCount: bytes.count,
      utf16UnitCount: nsText.length,
      lineCount: lineCount,
      statementCount: statementCount,
      findNeedleSpan: TextSpan(location: markerRange.location, length: markerRange.length),
      nearEndNeedleSpan: TextSpan(
        location: nearEndMarkerRange.location,
        length: nearEndMarkerRange.length
      ),
      fingerprint: fingerprint
    )
  }

  private static func statement(index: Int) -> String {
    let number = zeroPadded(index)
    switch index % 4 {
    case 0:
      return "SELECT \"café\", '東京' FROM \"schéma\".\"表\" WHERE id = \(number);\n"
    case 1:
      return
        "SELECT `naïve`, JSON_EXTRACT(payload, '$.値') FROM `mysql_table` LIMIT 1; -- \(number)\n"
    case 2:
      return "DO $bf$ BEGIN PERFORM \(number); END $bf$;\n"
    default:
      return "SELECT broken_\(number) FROM ; -- intentional syntax error\n"
    }
  }

  private static func zeroPadded(_ value: Int) -> String {
    let valueString = String(value)
    return String(repeating: "0", count: max(0, 6 - valueString.count)) + valueString
  }

  private static func append(_ string: String, to bytes: inout [UInt8]) {
    bytes.append(contentsOf: string.utf8)
  }

  private static func appendFiller(to bytes: inout [UInt8], until target: Int) {
    let prefix = "-- BF-01 deterministic long line: "
    let filler = prefix + String(repeating: "x", count: 4_096) + "\n"
    let fillerBytes = Array(filler.utf8)

    while bytes.count < target {
      let remaining = target - bytes.count
      bytes.append(contentsOf: fillerBytes.prefix(remaining))
    }
  }

  private static func sha256Hex(_ bytes: [UInt8]) -> String {
    var hasher = SHA256()
    bytes.withUnsafeBytes { buffer in
      hasher.update(bufferPointer: buffer)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
