import Foundation
import XCTest
@testable import FNVirtualCameraCore

final class CameraInstallationPreflightTests: XCTestCase {

    func testApplicationsAndEditionSubdirectoriesAllowInstallation() {
        for path in ["/Applications/FaceNow.app", "/Applications/FaceNow Overseas/FaceNow.app"] {
            XCTAssertNil(CameraInstallationPreflight.failure(
                applicationURL: URL(fileURLWithPath: path),
                extensionVersion: "52"
            ), path)
        }
    }

    func testUnsupportedLocationsAreRejectedBeforeSubmittingActivation() {
        for path in [
            "/Users/example/Downloads/FaceNow.app",
            "/Volumes/FaceNow/FaceNow.app",
            "/private/var/folders/example/AppTranslocation/FaceNow.app",
            "/Users/example/Library/Developer/Xcode/DerivedData/Build/FaceNow.app",
            "/Applications-Fake/FaceNow.app",
            "/Applications/../Downloads/FaceNow.app",
        ] {
            let failure = CameraInstallationPreflight.failure(
                applicationURL: URL(fileURLWithPath: path),
                extensionVersion: "52",
                operation: .reinstall
            )
            XCTAssertEqual(failure?.kind, .invalidLocation, path)
            XCTAssertEqual(failure?.operation, .reinstall, path)
        }
    }

    func testMissingBundleMetadataIsDistinctFromAnInvalidLocation() {
        for version: String? in [nil, "", " \n"] {
            XCTAssertEqual(CameraInstallationPreflight.failure(
                applicationURL: URL(fileURLWithPath: "/Applications/FaceNow.app"),
                extensionVersion: version
            )?.kind, .invalidBundle)
        }
    }

    func testLocationMustBeFixedBeforeBundleValidationCanContinue() {
        XCTAssertEqual(CameraInstallationPreflight.failure(
            applicationURL: URL(fileURLWithPath: "/Volumes/FaceNow/FaceNow.app"),
            extensionVersion: nil
        )?.kind, .invalidLocation)
    }
}
