import AppKit
import GridSpikeCore

@MainActor
public final class ReusableGridCellView: NSTableCellView {
  public static let reuseIdentifier = NSUserInterfaceItemIdentifier("dataforge.grid-spike.cell")

  private let indicatorView = NSImageView()
  private let valueField = NSTextField(labelWithString: "")

  public private(set) var representedCellID: CellID?
  public private(set) var appliedPaletteVersion: UInt64 = 0
  public private(set) var appliedStyle: GridStyleToken?

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    identifier = Self.reuseIdentifier
    wantsLayer = true

    indicatorView.translatesAutoresizingMaskIntoConstraints = false
    indicatorView.imageScaling = .scaleProportionallyDown
    indicatorView.setContentHuggingPriority(.required, for: .horizontal)
    indicatorView.widthAnchor.constraint(equalToConstant: 14).isActive = true

    valueField.translatesAutoresizingMaskIntoConstraints = false
    valueField.lineBreakMode = .byTruncatingTail
    valueField.maximumNumberOfLines = 1
    valueField.isSelectable = true
    valueField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let stack = NSStackView(views: [indicatorView, valueField])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 4
    stack.edgeInsets = NSEdgeInsets(top: 1, left: 4, bottom: 1, right: 4)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    setAccessibilityRole(.cell)
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    nil
  }

  public func configure(
    cell: GridCell,
    text: String,
    accessibilityValue: String,
    style: GridStyleToken,
    paletteVersion: UInt64,
    columnName: String
  ) {
    representedCellID = cell.id
    appliedPaletteVersion = paletteVersion
    appliedStyle = style
    valueField.stringValue = text
    valueField.textColor = style.foreground.nsColor
    valueField.font = font(for: style)
    toolTip = style.tooltip
    layer?.backgroundColor = style.background.nsColor.cgColor

    if let symbolName = style.indicator.symbolName {
      indicatorView.image = NSImage(
        systemSymbolName: symbolName, accessibilityDescription: style.tooltip)
      indicatorView.isHidden = false
    } else {
      indicatorView.image = nil
      indicatorView.isHidden = true
    }

    setAccessibilityLabel(columnName)
    setAccessibilityValue(accessibilityValue)
    setAccessibilityHelp(style.tooltip)
  }

  public override func prepareForReuse() {
    super.prepareForReuse()
    representedCellID = nil
    appliedStyle = nil
    appliedPaletteVersion = 0
    valueField.stringValue = ""
    valueField.textColor = .labelColor
    valueField.font = .systemFont(ofSize: NSFont.systemFontSize)
    indicatorView.image = nil
    indicatorView.isHidden = true
    toolTip = nil
    layer?.backgroundColor = NSColor.clear.cgColor
    setAccessibilityLabel(nil)
    setAccessibilityValue(nil)
    setAccessibilityHelp(nil)
  }

  private func font(for style: GridStyleToken) -> NSFont {
    let weight: NSFont.Weight =
      switch style.fontWeight {
      case .regular: .regular
      case .medium: .medium
      case .semibold: .semibold
      }
    let base = NSFont.monospacedSystemFont(ofSize: 12, weight: weight)
    guard style.isItalic else {
      return base
    }
    return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
  }
}
