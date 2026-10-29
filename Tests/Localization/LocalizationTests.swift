import Foundation
import Localization
import XCTest

final class LocalizationTests: XCTestCase {

    func testTargetLanguageIsSelectedRegardlessOfBundleDevelopmentRegion() throws {
        let fixture = try makeBundle()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        #if OVERSEA
        XCTAssertEqual(Localization.languageCode, "en")
        let expected = "Welcome"
        #else
        XCTAssertEqual(Localization.languageCode, "zh-Hans")
        let expected = "欢迎"
        #endif
        XCTAssertEqual(
            Localization.string("welcome", table: "User", defaultValue: "Fallback", bundle: fixture.bundle),
            expected
        )
    }

    func testMissingSelectedTextUsesEnglishFallbackRatherThanAnotherLanguage() throws {
        let fixture = try makeBundle()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        XCTAssertEqual(
            Localization.string(
                "other_language_only",
                table: "User",
                defaultValue: "English fallback",
                bundle: fixture.bundle
            ),
            "English fallback"
        )
    }

    func testCompleteMessagesSupportReorderedArgumentsAndCountdowns() throws {
        let fixture = try makeBundle()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        XCTAssertEqual(
            Localization.format(
                "agreement",
                table: "User",
                defaultValue: "Unused",
                arguments: ["Terms", "Privacy"],
                bundle: fixture.bundle
            ),
            Localization.languageCode == "en" ? "Privacy then Terms" : "Privacy 和 Terms"
        )
        XCTAssertEqual(
            Localization.format(
                "resend",
                table: "User",
                defaultValue: "Resend (%llds)",
                arguments: [Int64(59)],
                bundle: fixture.bundle
            ),
            Localization.languageCode == "en" ? "Resend (59s)" : "重新发送 (59秒)"
        )
    }

    private func makeBundle() throws -> (url: URL, bundle: Bundle) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "ai.xmax.localization-tests.\(UUID().uuidString)",
            "CFBundleDevelopmentRegion": Localization.languageCode == "en" ? "zh-Hans" : "en",
            "CFBundleLocalizations": ["zh-Hans", "en"],
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Info.plist"))
        var tables = [
            "en": ["welcome": "Welcome", "agreement": "%2$@ then %1$@"],
            "zh-Hans": ["welcome": "欢迎", "agreement": "%2$@ 和 %1$@", "resend": "重新发送 (%lld秒)"],
        ]
        let otherLanguage = Localization.languageCode == "en" ? "zh-Hans" : "en"
        tables[otherLanguage]?["other_language_only"] = "Must not be selected"
        for (language, strings) in tables {
            let directory = url.appendingPathComponent(language + ".lproj")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: strings, format: .xml, options: 0)
                .write(to: directory.appendingPathComponent("User.strings"))
        }
        return (url, try XCTUnwrap(Bundle(url: url)))
    }
}
