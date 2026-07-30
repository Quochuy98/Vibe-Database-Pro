import AppKit
import Foundation
import GridSpikeCore

public struct GridCellTraits: OptionSet, Hashable, Sendable {
  public let rawValue: UInt16

  public init(rawValue: UInt16) {
    self.rawValue = rawValue
  }

  public static let primaryKey = GridCellTraits(rawValue: 1 << 0)
  public static let foreignKey = GridCellTraits(rawValue: 1 << 1)
  public static let generated = GridCellTraits(rawValue: 1 << 2)
  public static let modified = GridCellTraits(rawValue: 1 << 3)
  public static let invalid = GridCellTraits(rawValue: 1 << 4)
  public static let deferred = GridCellTraits(rawValue: 1 << 5)
  public static let nullValue = GridCellTraits(rawValue: 1 << 6)
  public static let notLoaded = GridCellTraits(rawValue: 1 << 7)
}

public enum GridAppearance: String, CaseIterable, Hashable, Sendable {
  case light
  case dark
  case highContrastLight
  case highContrastDark
  case colorBlindFriendlyLight
  case colorBlindFriendlyDark
  case minimalLight
  case minimalDark

  public var isDark: Bool {
    switch self {
    case .dark, .highContrastDark, .colorBlindFriendlyDark, .minimalDark:
      true
    case .light, .highContrastLight, .colorBlindFriendlyLight, .minimalLight:
      false
    }
  }
}

public struct GridRGBA: Equatable, Hashable, Sendable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public let alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = min(max(red, 0), 1)
    self.green = min(max(green, 0), 1)
    self.blue = min(max(blue, 0), 1)
    self.alpha = min(max(alpha, 0), 1)
  }

  public init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }

  public var nsColor: NSColor {
    NSColor(
      calibratedRed: red,
      green: green,
      blue: blue,
      alpha: alpha
    )
  }

  public func contrastRatio(against background: GridRGBA) -> Double {
    let foregroundLuminance = relativeLuminance(composited(over: background))
    let backgroundLuminance = relativeLuminance(background)
    let lighter = max(foregroundLuminance, backgroundLuminance)
    let darker = min(foregroundLuminance, backgroundLuminance)
    return (lighter + 0.05) / (darker + 0.05)
  }

  private func composited(over background: GridRGBA) -> GridRGBA {
    guard alpha < 1 else {
      return self
    }
    return GridRGBA(
      red: red * alpha + background.red * (1 - alpha),
      green: green * alpha + background.green * (1 - alpha),
      blue: blue * alpha + background.blue * (1 - alpha)
    )
  }

  private func relativeLuminance(_ color: GridRGBA) -> Double {
    func linear(_ component: Double) -> Double {
      component <= 0.04045
        ? component / 12.92
        : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(color.red)
      + 0.7152 * linear(color.green)
      + 0.0722 * linear(color.blue)
  }
}

public enum GridFontWeight: String, Hashable, Sendable {
  case regular
  case medium
  case semibold
}

public enum GridNonColorIndicator: String, Hashable, Sendable {
  case none
  case primaryKey
  case foreignKey
  case generated
  case modified
  case invalid
  case deferred
  case nullValue
  case notLoaded

  public var symbolName: String? {
    switch self {
    case .none: nil
    case .primaryKey: "key.fill"
    case .foreignKey: "link"
    case .generated: "gearshape"
    case .modified: "pencil.circle.fill"
    case .invalid: "exclamationmark.triangle.fill"
    case .deferred: "arrow.down.circle"
    case .nullValue: "nosign"
    case .notLoaded: "ellipsis"
    }
  }
}

public struct GridStyleToken: Equatable, Hashable, Sendable {
  public let foreground: GridRGBA
  public let background: GridRGBA
  public let fontWeight: GridFontWeight
  public let isItalic: Bool
  public let indicator: GridNonColorIndicator
  public let tooltip: String
  public let contrastRatio: Double
  public let hasContrastWarning: Bool

  public init(
    foreground: GridRGBA,
    background: GridRGBA,
    fontWeight: GridFontWeight,
    isItalic: Bool,
    indicator: GridNonColorIndicator,
    tooltip: String
  ) {
    self.foreground = foreground
    self.background = background
    self.fontWeight = fontWeight
    self.isItalic = isItalic
    self.indicator = indicator
    self.tooltip = tooltip
    self.contrastRatio = foreground.contrastRatio(against: background)
    self.hasContrastWarning = contrastRatio < 4.5
  }
}

public struct GridStyleKey: Hashable, Sendable {
  public let appearance: GridAppearance
  public let typeGroup: NormalizedDataTypeGroup
  public let traits: GridCellTraits

  public init(
    appearance: GridAppearance,
    typeGroup: NormalizedDataTypeGroup,
    traits: GridCellTraits
  ) {
    self.appearance = appearance
    self.typeGroup = typeGroup
    self.traits = traits
  }
}

@MainActor
public final class GridThemeResolver {
  public static let maximumCachedTokens = 512

  private var cache: [GridStyleKey: GridStyleToken] = [:]
  public private(set) var paletteVersion: UInt64 = 1

  public init() {}

  public var cachedTokenCount: Int {
    cache.count
  }

  public func resolve(
    appearance: GridAppearance,
    typeGroup: NormalizedDataTypeGroup,
    traits: GridCellTraits
  ) -> GridStyleToken {
    let key = GridStyleKey(appearance: appearance, typeGroup: typeGroup, traits: traits)
    if let cached = cache[key] {
      return cached
    }

    let token = Self.makeToken(key)
    if cache.count >= Self.maximumCachedTokens {
      cache.removeAll(keepingCapacity: true)
    }
    cache[key] = token
    return token
  }

  public func changePalette() {
    paletteVersion &+= 1
    cache.removeAll(keepingCapacity: true)
  }

  public func clearCache() {
    cache.removeAll(keepingCapacity: true)
  }

  private static func makeToken(_ key: GridStyleKey) -> GridStyleToken {
    let background = key.appearance.isDark ? GridRGBA(hex: 0x1E1E1E) : GridRGBA(hex: 0xFFFFFF)
    let foreground = foregroundColor(for: key.typeGroup, appearance: key.appearance)
    let indicator = indicator(for: key.traits)
    let tooltip = tooltip(for: key.typeGroup, traits: key.traits)
    let weight: GridFontWeight = key.traits.contains(.primaryKey) ? .semibold : .regular
    let italic = key.traits.contains(.nullValue) || key.traits.contains(.notLoaded)
    return GridStyleToken(
      foreground: foreground,
      background: background,
      fontWeight: weight,
      isItalic: italic,
      indicator: indicator,
      tooltip: tooltip
    )
  }

  private static func foregroundColor(
    for group: NormalizedDataTypeGroup,
    appearance: GridAppearance
  ) -> GridRGBA {
    if appearance == .minimalLight {
      return GridRGBA(hex: 0x202020)
    }
    if appearance == .minimalDark {
      return GridRGBA(hex: 0xF0F0F0)
    }

    let light: [NormalizedDataTypeGroup: UInt32] = [
      .integer: 0x004A86,
      .decimal: 0x654600,
      .string: 0x202020,
      .boolean: 0x5C176D,
      .date: 0x6B2E00,
      .time: 0x6B2E00,
      .datetime: 0x6B2E00,
      .interval: 0x6B2E00,
      .uuid: 0x174B52,
      .json: 0x00533D,
      .xml: 0x00533D,
      .binary: 0x5A3545,
      .enumeration: 0x403C00,
      .array: 0x174B52,
      .composite: 0x174B52,
      .spatial: 0x004E5B,
      .network: 0x004E5B,
      .bitString: 0x5A3545,
      .unknown: 0x3B3B3B,
    ]
    let dark: [NormalizedDataTypeGroup: UInt32] = [
      .integer: 0x8BCBFF,
      .decimal: 0xFFD787,
      .string: 0xF0F0F0,
      .boolean: 0xE8A8FA,
      .date: 0xFFBD8C,
      .time: 0xFFBD8C,
      .datetime: 0xFFBD8C,
      .interval: 0xFFBD8C,
      .uuid: 0x9CE5E8,
      .json: 0x8BE0BB,
      .xml: 0x8BE0BB,
      .binary: 0xEAB5C9,
      .enumeration: 0xE4DD91,
      .array: 0x9CE5E8,
      .composite: 0x9CE5E8,
      .spatial: 0x8DDCE8,
      .network: 0x8DDCE8,
      .bitString: 0xEAB5C9,
      .unknown: 0xD0D0D0,
    ]
    let value =
      (appearance.isDark ? dark : light)[group] ?? (appearance.isDark ? 0xF0F0F0 : 0x202020)
    return GridRGBA(hex: value)
  }

  private static func indicator(for traits: GridCellTraits) -> GridNonColorIndicator {
    if traits.contains(.invalid) { return .invalid }
    if traits.contains(.modified) { return .modified }
    if traits.contains(.notLoaded) { return .notLoaded }
    if traits.contains(.nullValue) { return .nullValue }
    if traits.contains(.deferred) { return .deferred }
    if traits.contains(.primaryKey) { return .primaryKey }
    if traits.contains(.foreignKey) { return .foreignKey }
    if traits.contains(.generated) { return .generated }
    return .none
  }

  private static func tooltip(
    for group: NormalizedDataTypeGroup,
    traits: GridCellTraits
  ) -> String {
    var parts = [group.rawValue]
    if traits.contains(.primaryKey) { parts.append("primary key") }
    if traits.contains(.foreignKey) { parts.append("foreign key") }
    if traits.contains(.generated) { parts.append("generated") }
    if traits.contains(.modified) { parts.append("modified, not applied") }
    if traits.contains(.invalid) { parts.append("invalid value") }
    if traits.contains(.deferred) { parts.append("deferred value") }
    if traits.contains(.nullValue) { parts.append("SQL NULL") }
    if traits.contains(.notLoaded) { parts.append("not loaded") }
    return parts.joined(separator: ", ")
  }
}

public enum GridCellPresentation {
  public static func traits(for cell: GridCell, modified: Bool = false, invalid: Bool = false)
    -> GridCellTraits
  {
    var traits: GridCellTraits = []
    if cell.ordinal == 0 { traits.insert(.primaryKey) }
    if cell.ordinal == 1 { traits.insert(.foreignKey) }
    if cell.ordinal == 2 { traits.insert(.generated) }
    if modified { traits.insert(.modified) }
    if invalid { traits.insert(.invalid) }
    switch cell.value {
    case .notLoaded: traits.insert(.notLoaded)
    case .null: traits.insert(.nullValue)
    case .deferred: traits.insert(.deferred)
    case .loaded: break
    }
    return traits
  }

  public static func text(for value: GridCellValue, maximumTextScalars: Int = 512) -> String {
    switch value {
    case .notLoaded:
      "Not loaded"
    case .null:
      "NULL"
    case .deferred(let metadata):
      "Deferred \(metadata.kind.rawValue) · \(metadata.logicalByteLength) bytes"
    case .loaded(let normalized):
      boundedText(for: normalized, maximumScalars: maximumTextScalars)
    }
  }

  public static func accessibilityValue(for value: GridCellValue) -> String {
    switch value {
    case .notLoaded: "Value not loaded"
    case .null: "SQL NULL"
    case .deferred(let metadata):
      "Deferred \(metadata.kind.rawValue), \(metadata.logicalByteLength) bytes"
    case .loaded(.text(let text)) where text.isEmpty: "Empty text"
    case .loaded(.binary(let data)) where data.isEmpty: "Empty binary value"
    case .loaded(let normalized): boundedText(for: normalized, maximumScalars: 256)
    }
  }

  private static func boundedText(
    for value: GridNormalizedValue,
    maximumScalars: Int
  ) -> String {
    let text: String =
      switch value {
      case .signedInteger(let number): String(number)
      case .unsignedInteger(let number): String(number)
      case .decimal(let number): NSDecimalNumber(decimal: number).stringValue
      case .floatingPoint(let number): String(number)
      case .text(let text): text.isEmpty ? "Empty text" : text
      case .boolean(let value): value ? "True" : "False"
      case .date(let value): String(format: "%04d-%02d-%02d", value.year, value.month, value.day)
      case .time(let value):
        String(format: "%02d:%02d:%02d", value.hour, value.minute, value.second)
      case .datetime(let value): "Timestamp \(value.epochMilliseconds)"
      case .interval(let value):
        "\(value.months) months, \(value.days) days, \(value.microseconds) µs"
      case .uuid(let value): value.uuidString.lowercased()
      case .json(let value): value
      case .xml(let value): value
      case .binary(let data): data.isEmpty ? "Empty binary" : "\(data.count) bytes"
      case .enumeration(let value): value
      case .array(let values): "Array · \(values.count) values"
      case .composite(let fields): "Record · \(fields.count) fields"
      case .spatial(let value):
        "\(value.subtype) · SRID \(value.srid.map(String.init) ?? "unknown")"
      case .network(let value): "\(value.family) · \(value.value)"
      case .bitString(let value): value.bits
      case .unknown(let value): "\(value.rawTypeIdentity) · database-specific"
      }
    guard text.unicodeScalars.count > maximumScalars else {
      return text
    }
    return String(text.unicodeScalars.prefix(maximumScalars)) + "…"
  }
}
