import Foundation

public actor IncrementalFindService {
  private let limits: FindLimits

  public init(limits: FindLimits = .largeSQLDefault) {
    self.limits = limits
  }

  public func firstRange(in document: String, needle: String) async throws -> TextSpan? {
    try Task.checkCancellation()

    let documentText = document as NSString
    let needleCodeUnits = Array(needle.utf16)
    guard !needleCodeUnits.isEmpty else {
      throw EditorSpikeError.emptyFindNeedle
    }
    guard needleCodeUnits.count <= limits.maximumNeedleUTF16Units else {
      throw EditorSpikeError.findNeedleLimitExceeded(
        actualUTF16Units: needleCodeUnits.count,
        maximumUTF16Units: limits.maximumNeedleUTF16Units
      )
    }
    guard documentText.length <= limits.maximumDocumentUTF16Units else {
      throw EditorSpikeError.findDocumentLimitExceeded(
        actualUTF16Units: documentText.length,
        maximumUTF16Units: limits.maximumDocumentUTF16Units
      )
    }

    var chunkStart = 0
    while chunkStart < documentText.length {
      try Task.checkCancellation()

      let searchLength = min(
        documentText.length - chunkStart,
        limits.searchChunkUTF16Units + needleCodeUnits.count - 1
      )
      let searchRange = NSRange(location: chunkStart, length: searchLength)
      var chunk = [UInt16](repeating: 0, count: searchLength)
      documentText.getCharacters(&chunk, range: searchRange)
      if let localMatch = try await firstMatch(in: chunk, needle: needleCodeUnits) {
        return TextSpan(location: chunkStart + localMatch, length: needleCodeUnits.count)
      }

      chunkStart += limits.searchChunkUTF16Units
      await Task.yield()
    }

    try Task.checkCancellation()
    return nil
  }

  private func firstMatch(in haystack: [UInt16], needle: [UInt16]) async throws -> Int? {
    guard needle.count <= haystack.count else {
      return nil
    }

    var skip = [UInt16: Int]()
    if needle.count > 1 {
      for index in 0..<(needle.count - 1) {
        skip[needle[index]] = needle.count - 1 - index
      }
    }

    var cursor = 0
    var iterations = 0
    while cursor <= haystack.count - needle.count {
      if iterations.isMultiple(of: 4_096) {
        try Task.checkCancellation()
        await Task.yield()
      }

      var needleIndex = needle.count - 1
      while haystack[cursor + needleIndex] == needle[needleIndex] {
        if needleIndex == 0 {
          return cursor
        }
        needleIndex -= 1
      }

      let tail = haystack[cursor + needle.count - 1]
      cursor += skip[tail] ?? needle.count
      iterations += 1
    }
    return nil
  }
}
