import Foundation
import XCTest
@testable import FNUser

@MainActor
final class UserRepositoryTests: XCTestCase {

    func testRestoresTheExistingPreferenceWithoutChangingItsContents() async {
        withDefaults { defaults in
            defaults.set(
                "  saved-key\n",
                forKey: "xmax.camera.apiKey"
            )
            let user = UserRepository(defaults: defaults)
            XCTAssertEqual(
                user.apiKey,
                "  saved-key\n"
            )
            XCTAssertTrue(user.hasAPIKey)
        }
    }

    func testCredentialChangesAreVisibleToANewSettingsOwner() async {
        withDefaults { defaults in
            let user = UserRepository(defaults: defaults)
            user.apiKey = "replacement-key"
            let restored = UserRepository(defaults: defaults)
            XCTAssertEqual(
                restored.apiKey,
                "replacement-key"
            )
            XCTAssertTrue(restored.hasAPIKey)
        }
    }

    func testClearingTheCredentialPersistsAnUnavailableState() async {
        withDefaults { defaults in
            defaults.set(
                "saved-key",
                forKey: "xmax.camera.apiKey"
            )
            let user = UserRepository(defaults: defaults)
            user.apiKey = ""
            let restored = UserRepository(defaults: defaults)
            XCTAssertEqual(
                restored.apiKey,
                ""
            )
            XCTAssertFalse(restored.hasAPIKey)
        }
    }

    func testWhitespaceIsUnavailableWithoutRewritingTheStoredValue() async {
        withDefaults { defaults in
            let user = UserRepository(defaults: defaults)
            user.apiKey = " \n\t"
            XCTAssertFalse(user.hasAPIKey)
            XCTAssertEqual(
                defaults.string(forKey: "xmax.camera.apiKey"),
                " \n\t"
            )
        }
    }

    private func withDefaults(
        _ body: (UserDefaults) -> Void
    ) {
        let suite = "FaceNow.FNUserRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
