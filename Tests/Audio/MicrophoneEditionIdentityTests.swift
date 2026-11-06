import Foundation
import XCTest
@testable import VirtualMicrophoneCore

final class MicrophoneEditionIdentityTests: XCTestCase {

    func testOutputAndDriverDetectionUseThisEditionsInstallerIdentity() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Configuration/DeviceIdentities.json"))
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: String]])
        #if OVERSEA
        let edition = "oversea"
        #else
        let edition = "domestic"
        #endif
        let selected = try XCTUnwrap(all[edition])
        XCTAssertEqual(VirtualMicrophoneConfiguration.deviceUID, selected["microphoneUID"])
        XCTAssertEqual(VirtualMicrophoneConfiguration.writerDeviceUID, selected["writerUID"])
        XCTAssertEqual(VirtualMicrophoneConfiguration.deviceName, selected["microphoneName"])
        XCTAssertEqual(VirtualMicrophoneConfiguration.writerDeviceName, selected["speakerName"])
        XCTAssertEqual(VirtualMicrophoneConfiguration.driverBundleID, selected["driverBundleID"])
        XCTAssertEqual(VirtualMicrophoneConfiguration.driverFilename, selected["driverFilename"])
        XCTAssertEqual(VirtualMicrophoneConfiguration.installedInfoPath, "/Library/Audio/Plug-Ins/HAL/\(try XCTUnwrap(selected["driverFilename"]))/Contents/Info.plist")
    }
}
