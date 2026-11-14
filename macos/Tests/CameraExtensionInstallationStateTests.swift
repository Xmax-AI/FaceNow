import XCTest
@testable import CameraCore
@testable import FNVirtualCameraCore

final class CameraExtensionInstallationStateTests: XCTestCase {

    private let obsolete = VirtualCameraInstallationState.Record(
        version: "37",
        isEnabled: false,
        isUninstalling: true
    )

    func testOldRemovalRecordsDoNotBlockAnEnabledCurrentCamera() {
        let state = VirtualCameraInstallationState(
            records: [
                obsolete,
                .init(
                    version: "50",
                    isEnabled: true,
                    isUninstalling: false
                ),
            ],
            bundledVersion: "50"
        )
        XCTAssertTrue(state.isEnabled)
        XCTAssertTrue(state.isVersionCurrent)
        XCTAssertFalse(state.requiresRestartForRemoval)
    }

    func testDisabledCurrentCameraCanBeEnabledWithoutAnUnrelatedRemovalRestart() {
        let state = VirtualCameraInstallationState(
            records: [
                obsolete,
                .init(
                    version: "50",
                    isEnabled: false,
                    isUninstalling: false
                ),
            ],
            bundledVersion: "50"
        )
        XCTAssertFalse(state.isEnabled)
        XCTAssertFalse(state.isVersionCurrent)
        XCTAssertFalse(state.requiresRestartForRemoval)
    }

    func testOnlyRemovalRecordsRequireRestart() {
        let state = VirtualCameraInstallationState(
            records: [obsolete],
            bundledVersion: "50"
        )
        XCTAssertFalse(state.isEnabled)
        XCTAssertTrue(state.requiresRestartForRemoval)
    }

    func testEnabledOlderCameraDoesNotSatisfyTheBundledVersion() {
        let state = VirtualCameraInstallationState(
            records: [
                .init(
                    version: "49",
                    isEnabled: true,
                    isUninstalling: false
                )
            ],
            bundledVersion: "50"
        )
        XCTAssertTrue(state.isEnabled)
        XCTAssertFalse(state.isVersionCurrent)
        XCTAssertFalse(state.requiresRestartForRemoval)
    }

    func testFirstInstallationDoesNotRequireRestart() {
        let state = VirtualCameraInstallationState(
            records: [],
            bundledVersion: "50"
        )
        XCTAssertFalse(state.isEnabled)
        XCTAssertFalse(state.isVersionCurrent)
        XCTAssertFalse(state.requiresRestartForRemoval)
    }
}
