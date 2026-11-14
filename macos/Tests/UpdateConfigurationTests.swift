import Foundation
import XCTest
@testable import CameraCore

final class UpdateConfigurationTests: XCTestCase {

    private let key = Data(repeating: 7, count: 32).base64EncodedString()

    func testMissingAndPartialConfigurationLeaveUpdatesDisabled() {
        XCTAssertNil(UpdateConfiguration(infoDictionary: [:]))
        XCTAssertNil(UpdateConfiguration(infoDictionary: ["SUFeedURL": "", "SUPublicEDKey": ""]))
        XCTAssertNil(UpdateConfiguration(infoDictionary: ["SUFeedURL": "https://updates.example.org/appcast.xml"]))
        XCTAssertNil(UpdateConfiguration(infoDictionary: ["SUPublicEDKey": key]))
    }

    func testConfiguredFeedRequiresHTTPSAndRejectsEmbeddedCredentials() {
        for feed in [
            "http://updates.example.org/appcast.xml",
            "file:///tmp/appcast.xml",
            "https:///appcast.xml",
            "https://user:password@updates.example.org/appcast.xml",
            "https://updates.example.org/appcast.xml#fragment",
            "$(FACENOW_UPDATE_FEED_URL)",
        ] {
            XCTAssertNil(UpdateConfiguration(infoDictionary: ["SUFeedURL": feed, "SUPublicEDKey": key]), feed)
        }
    }

    func testInvalidSigningKeysCannotEnableUpdates() {
        for invalid in ["", "REPLACE_WITH_PUBLIC_KEY", Data(repeating: 7, count: 31).base64EncodedString()] {
            XCTAssertNil(UpdateConfiguration(infoDictionary: [
                "SUFeedURL": "https://updates.example.org/appcast.xml",
                "SUPublicEDKey": invalid,
            ]))
        }
    }

    func testCompleteConfigurationPreservesTheStableFeedAndPublicKey() throws {
        let feed = "https://updates.example.org/facenow/appcast.xml"
        let configuration = try XCTUnwrap(UpdateConfiguration(infoDictionary: [
            "SUFeedURL": feed,
            "SUPublicEDKey": key,
        ]))
        XCTAssertEqual(configuration.feedURL.absoluteString, feed)
        XCTAssertEqual(configuration.publicKey, key)
    }
}
