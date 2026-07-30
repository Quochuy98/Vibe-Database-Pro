import Foundation

public actor BoundedSQLAnalyzer {
  private let limits: AnalysisLimits

  public init(limits: AnalysisLimits = .viewportDefault) {
    self.limits = limits
  }

  public func analyze(_ snapshot: AnalysisSnapshot) async throws -> AnalysisResult {
    try Task.checkCancellation()

    let codeUnits = Array(snapshot.text.utf16)
    guard codeUnits.count <= limits.maximumUTF16Units else {
      throw EditorSpikeError.analysisLimitExceeded(
        actualUTF16Units: codeUnits.count,
        maximumUTF16Units: limits.maximumUTF16Units
      )
    }
    guard snapshot.documentSpan.location >= 0,
      snapshot.documentSpan.length == codeUnits.count,
      snapshot.documentSpan.location <= Int.max - codeUnits.count
    else {
      throw EditorSpikeError.invalidRange(snapshot.documentSpan)
    }

    let keywords = Self.keywords
    var spans = [TextSpan]()
    spans.reserveCapacity(min(128, limits.maximumMatches))
    var index = 0

    while index < codeUnits.count {
      if index.isMultiple(of: limits.cancellationCheckStride) {
        try Task.checkCancellation()
        await Task.yield()
      }

      var matchedLength = 0
      if isBoundaryBefore(codeUnits, index: index) {
        for keyword in keywords
        where matches(keyword, in: codeUnits, at: index)
          && isBoundaryAfter(codeUnits, index: index + keyword.count)
        {
          matchedLength = keyword.count
          break
        }
      }

      if matchedLength > 0 {
        if spans.count == limits.maximumMatches {
          return AnalysisResult(
            analyzedSpan: snapshot.documentSpan,
            keywordSpans: spans,
            revision: snapshot.revision,
            inputUTF16Units: codeUnits.count,
            hitOutputLimit: true
          )
        }
        spans.append(
          TextSpan(
            location: snapshot.documentSpan.location + index,
            length: matchedLength
          )
        )
        index += matchedLength
      } else {
        index += 1
      }
    }

    try Task.checkCancellation()
    return AnalysisResult(
      analyzedSpan: snapshot.documentSpan,
      keywordSpans: spans,
      revision: snapshot.revision,
      inputUTF16Units: codeUnits.count,
      hitOutputLimit: false
    )
  }

  private static let keywords: [[UInt16]] = [
    "BEGIN", "CREATE", "DELETE", "DO", "END", "FROM", "INSERT", "SELECT", "UPDATE", "WHERE",
  ].map { Array($0.utf16) }

  private func matches(_ keyword: [UInt16], in codeUnits: [UInt16], at index: Int) -> Bool {
    guard index + keyword.count <= codeUnits.count else {
      return false
    }

    for offset in keyword.indices {
      if uppercaseASCII(codeUnits[index + offset]) != keyword[offset] {
        return false
      }
    }
    return true
  }

  private func uppercaseASCII(_ codeUnit: UInt16) -> UInt16 {
    if codeUnit >= 97, codeUnit <= 122 {
      return codeUnit - 32
    }
    return codeUnit
  }

  private func isBoundaryBefore(_ codeUnits: [UInt16], index: Int) -> Bool {
    index == 0 || !isIdentifierCodeUnit(codeUnits[index - 1])
  }

  private func isBoundaryAfter(_ codeUnits: [UInt16], index: Int) -> Bool {
    index == codeUnits.count || !isIdentifierCodeUnit(codeUnits[index])
  }

  private func isIdentifierCodeUnit(_ codeUnit: UInt16) -> Bool {
    (codeUnit >= 48 && codeUnit <= 57)
      || (codeUnit >= 65 && codeUnit <= 90)
      || (codeUnit >= 97 && codeUnit <= 122)
      || codeUnit == 95
  }
}
