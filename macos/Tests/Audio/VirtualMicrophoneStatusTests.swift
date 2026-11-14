import XCTest
@testable import VirtualMicrophoneCore

final class VirtualMicrophoneStatusTests: XCTestCase {

    func testPublishedDeviceDoesNotImplyEnabledOutput() {
        XCTAssertEqual(
            VirtualMicrophoneStatus.resolve(
                driverInstalled: true,
                deviceAvailable: true,
                enabled: false,
                hasFailure: false
            ),
            .disabled
        )
    }

    func testAvailableDeviceIsEnabledBeforeGenerationBegins() {
        XCTAssertEqual(
            VirtualMicrophoneStatus.resolve(
                driverInstalled: true,
                deviceAvailable: true,
                enabled: true,
                hasFailure: false
            ),
            .enabled
        )
    }

    func testUnavailableDeviceDoesNotBecomeEnabledFromSavedPreference() {
        for installed in [false, true] {
            XCTAssertEqual(
                VirtualMicrophoneStatus.resolve(
                    driverInstalled: installed,
                    deviceAvailable: false,
                    enabled: true,
                    hasFailure: false
                ),
                installed ? .pending : .notInstalled
            )
        }
    }

    func testFailureOverridesEnabledPreference() {
        XCTAssertEqual(
            VirtualMicrophoneStatus.resolve(
                driverInstalled: true,
                deviceAvailable: true,
                enabled: true,
                hasFailure: true
            ),
            .failed
        )
    }
}
