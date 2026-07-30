import XCTest

@testable import GridSpikeAppKit
@testable import GridSpikeCore

@MainActor
final class GridThemeTests: XCTestCase {
  func testEveryNormalizedGroupMeetsDefaultLightAndDarkContrast() {
    let resolver = GridThemeResolver()
    for appearance in GridAppearance.allCases {
      for group in NormalizedDataTypeGroup.allCases {
        let token = resolver.resolve(appearance: appearance, typeGroup: group, traits: [])
        XCTAssertGreaterThanOrEqual(
          token.contrastRatio,
          4.5,
          "appearance=\(appearance.rawValue), group=\(group.rawValue)"
        )
        XCTAssertFalse(token.hasContrastWarning)
      }
    }
  }

  func testLowContrastCustomPairProducesWarning() {
    let token = GridStyleToken(
      foreground: GridRGBA(hex: 0x777777),
      background: GridRGBA(hex: 0x888888),
      fontWeight: .regular,
      isItalic: false,
      indicator: .none,
      tooltip: "custom"
    )
    XCTAssertLessThan(token.contrastRatio, 4.5)
    XCTAssertTrue(token.hasContrastWarning)
  }

  func testTraitsAlwaysProduceNonColorIndicatorAndTooltip() {
    let resolver = GridThemeResolver()
    let cases: [(GridCellTraits, GridNonColorIndicator, String)] = [
      (.primaryKey, .primaryKey, "primary key"),
      (.foreignKey, .foreignKey, "foreign key"),
      (.generated, .generated, "generated"),
      (.modified, .modified, "modified"),
      (.invalid, .invalid, "invalid"),
      (.deferred, .deferred, "deferred"),
      (.nullValue, .nullValue, "SQL NULL"),
      (.notLoaded, .notLoaded, "not loaded"),
    ]

    for (traits, expectedIndicator, expectedTooltip) in cases {
      let token = resolver.resolve(
        appearance: .light,
        typeGroup: .string,
        traits: traits
      )
      XCTAssertEqual(token.indicator, expectedIndicator)
      XCTAssertTrue(token.tooltip.contains(expectedTooltip))
      XCTAssertNotNil(token.indicator.symbolName)
    }
  }

  func testNullEmptyTextEmptyBinaryAndNotLoadedHaveDistinctAccessibilityValues() {
    let values: [GridCellValue] = [
      .notLoaded,
      .null,
      .loaded(.text("")),
      .loaded(.binary(Data())),
    ]
    let descriptions = values.map(GridCellPresentation.accessibilityValue(for:))
    XCTAssertEqual(Set(descriptions).count, values.count)
    XCTAssertEqual(descriptions[0], "Value not loaded")
    XCTAssertEqual(descriptions[1], "SQL NULL")
    XCTAssertEqual(descriptions[2], "Empty text")
    XCTAssertEqual(descriptions[3], "Empty binary value")
  }

  func testThemeTokenCacheIsBoundedAndPaletteChangeInvalidatesOnlyTokenCache() {
    let resolver = GridThemeResolver()
    let initialVersion = resolver.paletteVersion
    for appearance in GridAppearance.allCases {
      for group in NormalizedDataTypeGroup.allCases {
        for rawTraits in UInt16(0)..<64 {
          _ = resolver.resolve(
            appearance: appearance,
            typeGroup: group,
            traits: GridCellTraits(rawValue: rawTraits)
          )
        }
      }
    }
    XCTAssertLessThanOrEqual(resolver.cachedTokenCount, GridThemeResolver.maximumCachedTokens)

    resolver.changePalette()
    XCTAssertEqual(resolver.cachedTokenCount, 0)
    XCTAssertEqual(resolver.paletteVersion, initialVersion + 1)
  }
}
