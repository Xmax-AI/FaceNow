import Foundation
import XCTest
@testable import FNVirtualCameraCore

final class CameraEditionIdentityTests: XCTestCase {

    func testEditionContractMatchesPackagedExtensionAndProbe() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Configuration/DeviceIdentities.json"))
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: String]])
        #if OVERSEA
        let edition = "oversea"
        XCTAssertEqual(VirtualCameraDiagnostics.helperName, "FaceNowOverseaCameraProbe")
        #else
        let edition = "domestic"
        XCTAssertEqual(VirtualCameraDiagnostics.helperName, "FaceNowCameraProbe")
        #endif
        let selected = try XCTUnwrap(all[edition])
        XCTAssertEqual(VirtualCameraConfiguration.extensionBundleID, selected["extensionBundleID"])
        XCTAssertEqual(VirtualCameraConfiguration.appBundleID, selected["appBundleID"])
        XCTAssertEqual(VirtualCameraConfiguration.deviceName, selected["cameraName"])
        XCTAssertEqual(VirtualCameraConfiguration.deviceID.uuidString, selected["cameraDeviceID"])
        XCTAssertEqual(VirtualCameraConfiguration.sourceID.uuidString, selected["cameraSourceID"])
        XCTAssertEqual(VirtualCameraConfiguration.sinkID.uuidString, selected["cameraSinkID"])
    }

    func testBothVirtualOutputsAreExcludedFromPhysicalInputSelection() throws {
        XCTAssertTrue(VirtualCameraConfiguration.isFaceNowCamera("C1EF1269-DBA1-473B-BD21-7F3695635A01"))
        XCTAssertTrue(VirtualCameraConfiguration.isFaceNowCamera("D0A786E1-5244-44BD-84F7-3AB5DF35CB45"))
        XCTAssertFalse(VirtualCameraConfiguration.isFaceNowCamera("physical-camera-123"))
    }
}
