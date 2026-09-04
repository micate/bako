import Foundation
import XCTest
@testable import BakoApp

final class LocalizationTests: XCTestCase {
    func testEnglishAndSimplifiedChineseHaveMatchingKeysAndPlaceholders() throws {
        let english = try strings(for: "en")
        let simplifiedChinese = try strings(for: "zh-Hans")

        XCTAssertEqual(Set(english.keys), Set(simplifiedChinese.keys))
        for key in english.keys {
            XCTAssertEqual(
                placeholders(in: english[key] ?? ""),
                placeholders(in: simplifiedChinese[key] ?? ""),
                "Format placeholders differ for \(key)"
            )
        }
    }

    func testLocalizedStringLookupAndFormattingUsePackageResources() {
        XCTAssertNotEqual(L10n.string("menu.open"), "menu.open")
        XCTAssertFalse(L10n.string("groups.summary", Int64(2), Int64(3)).contains("%lld"))
    }

    func testLanguageResolutionFollowsSystemPreferencesBeforeEnglishFallback() {
        let chineseBundle = L10n.bundle(for: ["zh-Hans-US", "en-US"])
        let englishBundle = L10n.bundle(for: ["fr-FR", "en-US"])

        XCTAssertEqual(
            chineseBundle.localizedString(forKey: "menu.open", value: nil, table: "Localizable"),
            "打开 Bako"
        )
        XCTAssertEqual(
            englishBundle.localizedString(forKey: "menu.open", value: nil, table: "Localizable"),
            "Open Bako"
        )
    }

    private func strings(for localization: String) throws -> [String: String] {
        let actualLocalization = try XCTUnwrap(L10n.bundle.localizations.first {
            $0.caseInsensitiveCompare(localization) == .orderedSame
        })
        let stringsURL = try XCTUnwrap(L10n.bundle.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: actualLocalization
        ))
        let data = try Data(contentsOf: stringsURL)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(propertyList as? [String: String])
    }

    private func placeholders(in value: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: "%([0-9]+\\$)?(lld|@)")
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }
    }
}
