import Foundation
import Localization
import XCTest

final class LocalizationTests: XCTestCase {

    func testEnglishIsSelectedEvenWhenTheBundleAlsoSupportsChinese() throws {
        let fixture = try makeBundle()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        XCTAssertEqual(Localization.languageCode, "en")
        XCTAssertEqual(
            Localization.string("welcome", table: "User", defaultValue: "Fallback", bundle: fixture.bundle),
            "Welcome"
        )
    }

    func testMissingEnglishTextUsesEnglishFallbackRatherThanAnotherLanguage() throws {
        let fixture = try makeBundle()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        XCTAssertEqual(
            Localization.string(
                "chinese_only",
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
            "Privacy then Terms"
        )
        XCTAssertEqual(
            Localization.format(
                "resend",
                table: "User",
                defaultValue: "Resend (%llds)",
                arguments: [Int64(59)],
                bundle: fixture.bundle
            ),
            "Resend (59s)"
        )
    }

    private func makeBundle() throws -> (url: URL, bundle: Bundle) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "ai.xmax.localization-tests.\(UUID().uuidString)",
            "CFBundleDevelopmentRegion": "zh-Hans",
            "CFBundleLocalizations": ["zh-Hans", "en"],
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Info.plist"))
        let tables = [
            "en": ["welcome": "Welcome", "agreement": "%2$@ then %1$@"],
            "zh-Hans": ["welcome": "欢迎", "chinese_only": "仅中文"],
        ]
        for (language, strings) in tables {
            let directory = url.appendingPathComponent(language + ".lproj")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: strings, format: .xml, options: 0)
                .write(to: directory.appendingPathComponent("User.strings"))
        }
        return (url, try XCTUnwrap(Bundle(url: url)))
    }
}
