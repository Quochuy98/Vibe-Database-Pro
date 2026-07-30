import Foundation

public enum EditorSpikeError: Error, Equatable, Sendable {
  case analysisLimitExceeded(actualUTF16Units: Int, maximumUTF16Units: Int)
  case documentLimitExceeded(actualBytes: Int, maximumBytes: Int)
  case emptyFindNeedle
  case findDocumentLimitExceeded(actualUTF16Units: Int, maximumUTF16Units: Int)
  case findNeedleLimitExceeded(actualUTF16Units: Int, maximumUTF16Units: Int)
  case fixtureCannotFit(targetBytes: Int, requiredBytes: Int)
  case invalidRange(TextSpan)
  case missingTextKit2Component(String)
  case replacementLimitExceeded(actualBytes: Int, maximumBytes: Int)
  case staleAnalysis(expectedRevision: UInt64, actualRevision: UInt64)
}

extension EditorSpikeError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .analysisLimitExceeded(let actual, let maximum):
      "Analysis input has \(actual) UTF-16 units; maximum is \(maximum)."
    case .documentLimitExceeded(let actual, let maximum):
      "Document has \(actual) bytes; maximum is \(maximum)."
    case .emptyFindNeedle:
      "Find text must not be empty."
    case .findDocumentLimitExceeded(let actual, let maximum):
      "Find document has \(actual) UTF-16 units; maximum is \(maximum)."
    case .findNeedleLimitExceeded(let actual, let maximum):
      "Find text has \(actual) UTF-16 units; maximum is \(maximum)."
    case .fixtureCannotFit(let target, let required):
      "BF-01 target has \(target) bytes but requires at least \(required)."
    case .invalidRange(let range):
      "Text range {\(range.location), \(range.length)} is outside the document."
    case .missingTextKit2Component(let component):
      "TextKit 2 did not provide required component: \(component)."
    case .replacementLimitExceeded(let actual, let maximum):
      "Replacement has \(actual) bytes; maximum is \(maximum)."
    case .staleAnalysis(let expected, let actual):
      "Analysis revision \(expected) is stale; editor revision is \(actual)."
    }
  }
}

public struct TextSpan: Codable, Equatable, Hashable, Sendable {
  public let location: Int
  public let length: Int

  public init(location: Int, length: Int) {
    self.location = location
    self.length = length
  }

  public var upperBound: Int {
    location + length
  }

  public var nsRange: NSRange {
    NSRange(location: location, length: length)
  }
}

public enum EditPosition: String, CaseIterable, Codable, Sendable {
  case start
  case middle
  case end
}

public enum EditorKeyboardSelector: String, CaseIterable, Codable, Sendable {
  case moveToBeginningOfDocument = "moveToBeginningOfDocument:"
  case moveToEndOfDocument = "moveToEndOfDocument:"
}

public enum EditorMode: String, Codable, Equatable, Sendable {
  case standard
  case largeFile
}

public struct EditorFeaturePolicy: Codable, Equatable, Sendable {
  public let mode: EditorMode
  public let foldingEnabled: Bool
  public let semanticCompletionEnabled: Bool
  public let maximumAnalysisUTF16Units: Int
  public let accessibilityStatus: String

  public init(
    mode: EditorMode,
    foldingEnabled: Bool,
    semanticCompletionEnabled: Bool,
    maximumAnalysisUTF16Units: Int,
    accessibilityStatus: String
  ) {
    self.mode = mode
    self.foldingEnabled = foldingEnabled
    self.semanticCompletionEnabled = semanticCompletionEnabled
    self.maximumAnalysisUTF16Units = maximumAnalysisUTF16Units
    self.accessibilityStatus = accessibilityStatus
  }
}

public struct AnalysisSnapshot: Equatable, Sendable {
  public let text: String
  public let documentSpan: TextSpan
  public let revision: UInt64

  public init(text: String, documentSpan: TextSpan, revision: UInt64) {
    self.text = text
    self.documentSpan = documentSpan
    self.revision = revision
  }
}

public struct AnalysisResult: Equatable, Sendable {
  public let analyzedSpan: TextSpan
  public let keywordSpans: [TextSpan]
  public let revision: UInt64
  public let inputUTF16Units: Int
  public let hitOutputLimit: Bool

  public init(
    analyzedSpan: TextSpan,
    keywordSpans: [TextSpan],
    revision: UInt64,
    inputUTF16Units: Int,
    hitOutputLimit: Bool
  ) {
    self.analyzedSpan = analyzedSpan
    self.keywordSpans = keywordSpans
    self.revision = revision
    self.inputUTF16Units = inputUTF16Units
    self.hitOutputLimit = hitOutputLimit
  }
}

public struct AnalysisLimits: Equatable, Sendable {
  public static let maximumAllowedUTF16Units = 65_536
  public static let maximumAllowedMatches = 1_024
  public static let maximumCancellationCheckStride = 1_024
  public static let viewportDefault = AnalysisLimits(
    maximumUTF16Units: maximumAllowedUTF16Units,
    maximumMatches: maximumAllowedMatches,
    cancellationCheckStride: 256
  )

  public let maximumUTF16Units: Int
  public let maximumMatches: Int
  public let cancellationCheckStride: Int

  public init(
    maximumUTF16Units: Int,
    maximumMatches: Int,
    cancellationCheckStride: Int
  ) {
    precondition(maximumUTF16Units > 0)
    precondition(maximumMatches > 0)
    precondition(cancellationCheckStride > 0)
    precondition(maximumUTF16Units <= Self.maximumAllowedUTF16Units)
    precondition(maximumMatches <= Self.maximumAllowedMatches)
    precondition(cancellationCheckStride <= Self.maximumCancellationCheckStride)
    self.maximumUTF16Units = maximumUTF16Units
    self.maximumMatches = maximumMatches
    self.cancellationCheckStride = cancellationCheckStride
  }
}

public struct FindLimits: Equatable, Sendable {
  public static let maximumAllowedDocumentUTF16Units = 115 * 1_024 * 1_024
  public static let maximumAllowedNeedleUTF16Units = 1_024
  public static let maximumSearchChunkUTF16Units = 16 * 1_024 * 1_024
  public static let largeSQLDefault = FindLimits(
    maximumDocumentUTF16Units: maximumAllowedDocumentUTF16Units,
    maximumNeedleUTF16Units: maximumAllowedNeedleUTF16Units,
    searchChunkUTF16Units: 4 * 1_024 * 1_024
  )

  public let maximumDocumentUTF16Units: Int
  public let maximumNeedleUTF16Units: Int
  public let searchChunkUTF16Units: Int

  public init(
    maximumDocumentUTF16Units: Int,
    maximumNeedleUTF16Units: Int,
    searchChunkUTF16Units: Int
  ) {
    precondition(maximumDocumentUTF16Units > 0)
    precondition(maximumNeedleUTF16Units > 0)
    precondition(searchChunkUTF16Units > 0)
    precondition(maximumDocumentUTF16Units <= Self.maximumAllowedDocumentUTF16Units)
    precondition(maximumNeedleUTF16Units <= Self.maximumAllowedNeedleUTF16Units)
    precondition(searchChunkUTF16Units <= Self.maximumSearchChunkUTF16Units)
    self.maximumDocumentUTF16Units = maximumDocumentUTF16Units
    self.maximumNeedleUTF16Units = maximumNeedleUTF16Units
    self.searchChunkUTF16Units = searchChunkUTF16Units
  }
}

public struct EditorRecoveryState: Codable, Equatable, Sendable {
  public let selectedSpan: TextSpan

  public init(selectedSpan: TextSpan) {
    self.selectedSpan = selectedSpan
  }
}

public struct AccessibilitySnapshot: Codable, Equatable, Sendable {
  public let label: String
  public let role: String
  public let help: String
  public let isEditable: Bool
  public let isFocused: Bool
  public let selectedSpan: TextSpan
  public let selectedText: String

  public init(
    label: String,
    role: String,
    help: String,
    isEditable: Bool,
    isFocused: Bool,
    selectedSpan: TextSpan,
    selectedText: String
  ) {
    self.label = label
    self.role = role
    self.help = help
    self.isEditable = isEditable
    self.isFocused = isFocused
    self.selectedSpan = selectedSpan
    self.selectedText = selectedText
  }
}
