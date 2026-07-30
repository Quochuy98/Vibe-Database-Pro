import AppKit
import Foundation

@MainActor
public final class TextKit2EditorHarness {
  public static let maximumDocumentBytes = 110 * 1_024 * 1_024
  public static let maximumReplacementBytes = 4 * 1_024
  public static let largeFileThresholdBytes = 20 * 1_024 * 1_024
  public static let accessibilityLabel = "Synthetic SQL editor feasibility fixture"
  public static let standardModeAccessibilityStatus =
    "Standard editor mode. Folding and semantic completion are available."
  public static let largeFileAccessibilityStatus =
    "Large file mode. Folding and semantic completion are unavailable."

  public let textView: NSTextView
  public let textLayoutManager: NSTextLayoutManager
  public let textContentStorage: NSTextContentStorage
  public let textStorage: NSTextStorage

  public private(set) var revision: UInt64 = 0
  public private(set) var featurePolicy = EditorFeaturePolicy(
    mode: .standard,
    foldingEnabled: true,
    semanticCompletionEnabled: true,
    maximumAnalysisUTF16Units: AnalysisLimits.viewportDefault.maximumUTF16Units,
    accessibilityStatus: standardModeAccessibilityStatus
  )
  public private(set) var decoratedSpans: [TextSpan] = []

  private let scrollView: NSScrollView
  private let hostWindow: NSWindow
  private let undoDelegate: EditorUndoDelegate
  private let fallbackObserver: TextKitFallbackObserver
  private var decoratedEnvelope: TextSpan?

  public init(viewportSize: NSSize = NSSize(width: 900, height: 640)) throws {
    _ = NSApplication.shared

    let fallbackObserver = TextKitFallbackObserver()
    let textStorage = NSTextStorage()
    let textContentStorage = NSTextContentStorage()
    textContentStorage.textStorage = textStorage
    let textLayoutManager = NSTextLayoutManager()
    textContentStorage.addTextLayoutManager(textLayoutManager)
    textContentStorage.primaryTextLayoutManager = textLayoutManager
    let textContainer = NSTextContainer(
      size: NSSize(width: viewportSize.width, height: 0)
    )
    textLayoutManager.textContainer = textContainer
    let textView = NSTextView(
      frame: NSRect(origin: .zero, size: viewportSize),
      textContainer: textContainer
    )
    guard textView.textLayoutManager === textLayoutManager else {
      throw EditorSpikeError.missingTextKit2Component("NSTextLayoutManager")
    }
    guard textView.textContentStorage === textContentStorage else {
      throw EditorSpikeError.missingTextKit2Component("NSTextContentStorage")
    }
    fallbackObserver.attach(to: textView)

    let undoDelegate = EditorUndoDelegate()
    let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: viewportSize))
    let hostWindow = NSWindow(
      contentRect: NSRect(origin: .zero, size: viewportSize),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    self.textView = textView
    self.textLayoutManager = textLayoutManager
    self.textContentStorage = textContentStorage
    self.textStorage = textStorage
    self.undoDelegate = undoDelegate
    self.scrollView = scrollView
    self.hostWindow = hostWindow
    self.fallbackObserver = fallbackObserver

    textView.delegate = undoDelegate
    textView.allowsUndo = true
    textView.isEditable = true
    textView.isSelectable = true
    textView.isRichText = false
    textView.importsGraphics = false
    textView.usesFindBar = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = false
    textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    textView.textContainerInset = NSSize(width: 8, height: 8)
    textView.minSize = NSSize(width: 0, height: viewportSize.height)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.setAccessibilityRole(.textArea)
    textView.setAccessibilityLabel(Self.accessibilityLabel)
    textView.setAccessibilityHelp(
      "\(Self.standardModeAccessibilityStatus) This disposable synthetic SQL editor does not execute queries."
    )

    textLayoutManager.limitsLayoutForSuspiciousContents = true

    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.documentView = textView
    hostWindow.isReleasedWhenClosed = false
    hostWindow.contentView = scrollView
    guard hostWindow.makeFirstResponder(textView) else {
      throw EditorSpikeError.missingTextKit2Component("NSTextView first responder")
    }
  }

  public var usesTextKit2: Bool {
    textView.textLayoutManager === textLayoutManager
      && textView.textContentStorage === textContentStorage
      && fallbackObserver.fallbackCount == 0
  }

  public var textKit1FallbackCount: Int {
    fallbackObserver.fallbackCount
  }

  public var documentUTF16Length: Int {
    textStorage.length
  }

  public var selectedSpan: TextSpan {
    TextSpan(
      location: textView.selectedRange().location,
      length: textView.selectedRange().length
    )
  }

  public var canUndo: Bool {
    undoDelegate.manager.canUndo
  }

  public var canRedo: Bool {
    undoDelegate.manager.canRedo
  }

  public func load(_ fixture: BF01Fixture) throws {
    guard fixture.byteCount <= Self.maximumDocumentBytes else {
      throw EditorSpikeError.documentLimitExceeded(
        actualBytes: fixture.byteCount,
        maximumBytes: Self.maximumDocumentBytes
      )
    }

    clearDecorations()
    undoDelegate.manager.removeAllActions()
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
      .foregroundColor: NSColor.textColor,
    ]
    textContentStorage.performEditingTransaction {
      textStorage.setAttributedString(
        NSAttributedString(string: fixture.text, attributes: attributes)
      )
    }
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    revision &+= 1
    featurePolicy = policy(forDocumentBytes: fixture.byteCount)
    textView.setAccessibilityHelp(
      "\(featurePolicy.accessibilityStatus) This disposable synthetic SQL editor does not execute queries."
    )
    ensureLayout(around: TextSpan(location: 0, length: min(512, textStorage.length)))
  }

  @discardableResult
  public func insert(_ replacement: String, at position: EditPosition) throws -> TextSpan {
    let replacementBytes = replacement.utf8.count
    guard replacementBytes <= Self.maximumReplacementBytes else {
      throw EditorSpikeError.replacementLimitExceeded(
        actualBytes: replacementBytes,
        maximumBytes: Self.maximumReplacementBytes
      )
    }

    let offset = insertionOffset(for: position)
    let insertionRange = NSRange(location: offset, length: 0)
    textView.setSelectedRange(insertionRange)
    textView.insertText(replacement, replacementRange: insertionRange)
    revision &+= 1
    clearDecorations()

    let insertedLength = (replacement as NSString).length
    let insertedSpan = TextSpan(location: offset, length: insertedLength)
    return insertedSpan
  }

  public func undo() {
    guard undoDelegate.manager.canUndo else {
      return
    }
    undoDelegate.manager.undo()
    revision &+= 1
    clearDecorations()
  }

  public func redo() {
    guard undoDelegate.manager.canRedo else {
      return
    }
    undoDelegate.manager.redo()
    revision &+= 1
    clearDecorations()
  }

  public func text(in span: TextSpan) throws -> String {
    try validate(span)
    return textStorage.attributedSubstring(from: span.nsRange).string
  }

  public func analysisSnapshot(for proposedSpan: TextSpan) throws -> AnalysisSnapshot {
    try validate(proposedSpan)
    let maximumLength = featurePolicy.maximumAnalysisUTF16Units
    let boundedLength = min(proposedSpan.length, maximumLength)
    let boundedSpan = TextSpan(location: proposedSpan.location, length: boundedLength)
    let snapshotText = textStorage.attributedSubstring(from: boundedSpan.nsRange).string
    return AnalysisSnapshot(text: snapshotText, documentSpan: boundedSpan, revision: revision)
  }

  public func visibleSpan(around location: Int, requestedLength: Int = 16_384) throws -> TextSpan {
    guard location >= 0, location <= textStorage.length else {
      throw EditorSpikeError.invalidRange(TextSpan(location: location, length: 0))
    }
    let boundedRequestedLength = min(
      max(1, requestedLength),
      featurePolicy.maximumAnalysisUTF16Units
    )
    let halfLength = boundedRequestedLength / 2
    let start = max(0, min(location - halfLength, textStorage.length - boundedRequestedLength))
    return TextSpan(
      location: start,
      length: min(boundedRequestedLength, textStorage.length - start)
    )
  }

  public func applyHighlights(_ result: AnalysisResult) throws {
    guard result.revision == revision else {
      throw EditorSpikeError.staleAnalysis(
        expectedRevision: result.revision,
        actualRevision: revision
      )
    }
    try validate(result.analyzedSpan)

    clearDecorations()
    for span in result.keywordSpans {
      try validate(span)
      guard let range = textRange(for: span) else {
        throw EditorSpikeError.invalidRange(span)
      }
      textLayoutManager.setRenderingAttributes(
        [
          .foregroundColor: NSColor.systemPurple,
          .underlineStyle: NSUnderlineStyle.single.rawValue,
        ],
        for: range
      )
    }
    decoratedEnvelope = result.analyzedSpan
    decoratedSpans = result.keywordSpans
  }

  @discardableResult
  public func prepareViewport(for position: EditPosition) throws -> TextSpan {
    let location = insertionOffset(for: position)
    try prepareViewport(around: TextSpan(location: location, length: 0))
    return try visibleSpan(around: location)
  }

  public func prepareViewport(around span: TextSpan) throws {
    try validate(span)
    let target = NSRange(location: span.location, length: min(1, span.length))
    textView.setSelectedRange(NSRange(location: span.location, length: 0))
    textView.scrollRangeToVisible(target)
    textLayoutManager.textViewportLayoutController.layoutViewport()
    scrollView.layoutSubtreeIfNeeded()
    textView.needsDisplay = true
    textView.displayIfNeeded()
  }

  public func performKeyboardSelector(_ command: EditorKeyboardSelector) -> Bool {
    let selector = NSSelectorFromString(command.rawValue)
    guard textView.responds(to: selector) else {
      return false
    }
    textView.doCommand(by: selector)
    return true
  }

  public func captureRecoveryState() -> EditorRecoveryState {
    EditorRecoveryState(selectedSpan: selectedSpan)
  }

  public func restoreRecoveryState(_ state: EditorRecoveryState) {
    let location = min(max(0, state.selectedSpan.location), textStorage.length)
    let available = textStorage.length - location
    let length = min(max(0, state.selectedSpan.length), available)
    textView.setSelectedRange(NSRange(location: location, length: length))
    ensureLayout(around: TextSpan(location: location, length: max(1, length)))
  }

  public func accessibilitySnapshot() -> AccessibilitySnapshot {
    let selection = selectedSpan
    let selectedText: String
    if selection.length <= Self.maximumReplacementBytes {
      selectedText = textStorage.attributedSubstring(from: selection.nsRange).string
    } else {
      selectedText = ""
    }
    return AccessibilitySnapshot(
      label: textView.accessibilityLabel() ?? "",
      role: textView.accessibilityRole()?.rawValue ?? "",
      help: textView.accessibilityHelp() ?? "",
      isEditable: textView.isEditable,
      isFocused: hostWindow.firstResponder === textView,
      selectedSpan: selection,
      selectedText: selectedText
    )
  }

  public func forceViewportDisplay(around span: TextSpan) throws {
    try validate(span)
    textLayoutManager.textViewportLayoutController.layoutViewport()
    scrollView.layoutSubtreeIfNeeded()
    textView.needsDisplay = true
    textView.displayIfNeeded()
  }

  private func insertionOffset(for position: EditPosition) -> Int {
    switch position {
    case .start:
      0
    case .middle:
      textStorage.length / 2
    case .end:
      textStorage.length
    }
  }

  private func policy(forDocumentBytes bytes: Int) -> EditorFeaturePolicy {
    if bytes > Self.largeFileThresholdBytes {
      return EditorFeaturePolicy(
        mode: .largeFile,
        foldingEnabled: false,
        semanticCompletionEnabled: false,
        maximumAnalysisUTF16Units: AnalysisLimits.viewportDefault.maximumUTF16Units,
        accessibilityStatus: Self.largeFileAccessibilityStatus
      )
    }
    return EditorFeaturePolicy(
      mode: .standard,
      foldingEnabled: true,
      semanticCompletionEnabled: true,
      maximumAnalysisUTF16Units: AnalysisLimits.viewportDefault.maximumUTF16Units,
      accessibilityStatus: Self.standardModeAccessibilityStatus
    )
  }

  private func validate(_ span: TextSpan) throws {
    guard span.location >= 0,
      span.length >= 0,
      span.location <= textStorage.length,
      span.length <= textStorage.length - span.location
    else {
      throw EditorSpikeError.invalidRange(span)
    }
  }

  private func textRange(for span: TextSpan) -> NSTextRange? {
    let documentStart = textContentStorage.documentRange.location
    guard let start = textContentStorage.location(documentStart, offsetBy: span.location),
      let end = textContentStorage.location(start, offsetBy: span.length)
    else {
      return nil
    }
    return NSTextRange(location: start, end: end)
  }

  private func ensureLayout(around span: TextSpan) {
    let safeLocation = min(max(0, span.location), textStorage.length)
    let available = textStorage.length - safeLocation
    let layoutLength = min(max(1, span.length), min(2_048, available))
    let layoutSpan = TextSpan(location: safeLocation, length: layoutLength)
    guard let range = textRange(for: layoutSpan) else {
      return
    }
    textLayoutManager.ensureLayout(for: range)
    scrollView.layoutSubtreeIfNeeded()
  }

  private func clearDecorations() {
    if let envelope = decoratedEnvelope,
      let range = textRange(for: envelope)
    {
      textLayoutManager.invalidateRenderingAttributes(for: range)
    }
    decoratedEnvelope = nil
    decoratedSpans = []
  }
}

@MainActor
private final class TextKitFallbackObserver: NSObject {
  private(set) var fallbackCount = 0
  private weak var textView: NSTextView?

  override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(didSwitchToTextKit1(_:)),
      name: NSTextView.didSwitchToNSLayoutManagerNotification,
      object: nil
    )
  }

  func attach(to textView: NSTextView) {
    self.textView = textView
  }

  @objc
  private func didSwitchToTextKit1(_ notification: Notification) {
    guard textView == nil || notification.object as AnyObject? === textView else {
      return
    }
    fallbackCount += 1
  }
}

@MainActor
private final class EditorUndoDelegate: NSObject, NSTextViewDelegate {
  let manager = UndoManager()

  func undoManager(for view: NSTextView) -> UndoManager? {
    manager
  }
}
