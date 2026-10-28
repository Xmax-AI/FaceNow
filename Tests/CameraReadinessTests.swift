import XCTest
@testable import FNVirtualCameraCore

final class CameraReadinessTests: XCTestCase {

    func testUnknownInstallationAndInputStayCheckingAfterPermissionIsGranted() {
        XCTAssertEqual(resolve(VirtualCameraReadinessSnapshot()), .checking(.extensionStatus))
        var installed = currentExtension()
        installed.isDeviceReady = true
        XCTAssertEqual(resolve(installed, input: .checking(.inputDiscovery)), .checking(.inputDiscovery))
    }

    func testPermissionIssuesTakePriorityAndPromptIsNotAnUnavailableFailure() {
        let reasons: [(CameraAuthorization, CameraPermissionReason)] = [
            (.notRequested, .notRequested), (.denied, .denied), (.restricted, .restricted),
        ]
        for (authorization, reason) in reasons {
            XCTAssertEqual(
                CameraReadiness.resolve(
                    authorization: authorization,
                    virtualCamera: .unavailable(.virtualCameraNotInstalled),
                    inputCamera: .checking(.inputDiscovery)
                ),
                .permissionRequired(reason)
            )
        }
        XCTAssertEqual(
            CameraReadiness.resolve(
                authorization: .requesting,
                virtualCamera: .ready,
                inputCamera: .ready
            ),
            .checking(.permission)
        )
    }

    func testInstalledDisabledAndOutdatedExtensionsHaveDistinctReasons() {
        var snapshot = VirtualCameraReadinessSnapshot()
        snapshot.hasChecked = true
        XCTAssertEqual(resolve(snapshot), .unavailable(.virtualCameraNotInstalled))
        snapshot.isInstalled = true
        XCTAssertEqual(resolve(snapshot), .unavailable(.virtualCameraDisabled))
        snapshot.isEnabled = true
        XCTAssertEqual(resolve(snapshot), .unavailable(.versionMismatch))
    }

    func testBackgroundQueriesAndRechecksRetainConfirmedReadiness() {
        var snapshot = currentExtension()
        snapshot.isDeviceReady = true
        snapshot.isRefreshing = true
        snapshot.isWaitingForDevice = true
        snapshot.queryFailure = CameraOperationFailure(operation: .checkStatus, diagnosticMessage: "Temporary system query failure")
        XCTAssertEqual(resolve(snapshot), .ready)
    }

    func testExplicitOperationsApprovalAndRestartBlockEvenAnOldReadyDevice() {
        var snapshot = currentExtension()
        snapshot.isDeviceReady = true
        snapshot.operation = .installation
        XCTAssertEqual(resolve(snapshot), .checking(.installation))
        snapshot.isAwaitingApproval = true
        XCTAssertEqual(resolve(snapshot), .unavailable(.approvalRequired))
        snapshot.requiresRestart = true
        XCTAssertEqual(resolve(snapshot), .unavailable(.restartRequired))
    }

    func testPhysicalCameraLossIsNotReportedAsAnExtensionFailure() {
        var snapshot = currentExtension()
        snapshot.isDeviceReady = true
        XCTAssertEqual(resolve(snapshot, input: .unavailable(.noInputCamera)), .unavailable(.noInputCamera))
        XCTAssertEqual(
            resolve(snapshot, input: .unavailable(.selectedInputDisconnected)),
            .unavailable(.selectedInputDisconnected)
        )
        XCTAssertEqual(resolve(snapshot, input: .ready), .ready)
    }

    func testPublicationWaitTimeoutAndLateRecoveryFollowTheActualDeviceResult() {
        var snapshot = currentExtension()
        snapshot.isWaitingForDevice = true
        XCTAssertEqual(resolve(snapshot), .checking(.devicePublication))
        snapshot.isWaitingForDevice = false
        snapshot.failure = .devicePublicationTimedOut
        XCTAssertEqual(resolve(snapshot), .unavailable(.devicePublicationTimedOut))
        snapshot.failure = nil
        snapshot.isWaitingForDevice = true
        XCTAssertEqual(resolve(snapshot), .checking(.devicePublication))
        snapshot.isWaitingForDevice = false
        snapshot.isDeviceReady = true
        XCTAssertEqual(resolve(snapshot), .ready)
    }

    func testWarningsExistOnlyForConfirmedBlockedStates() {
        XCTAssertNil(CameraReadiness.checking(.extensionStatus).unavailableMessage)
        XCTAssertNil(CameraReadiness.ready.unavailableMessage)
        XCTAssertNotNil(CameraReadiness.permissionRequired(.denied).unavailableMessage)
        XCTAssertNotNil(CameraReadiness.unavailable(.virtualCameraNotInstalled).unavailableMessage)
    }

    func testQueryFailureIsActionableBeforeAnyInstallationSnapshotExists() {
        var snapshot = VirtualCameraReadinessSnapshot()
        snapshot.queryFailure = CameraOperationFailure(operation: .checkStatus, diagnosticMessage: "Cannot read system extension properties")
        XCTAssertEqual(resolve(snapshot), .unavailable(.operationFailed(snapshot.queryFailure!)))
    }

    private func currentExtension() -> VirtualCameraReadinessSnapshot {
        VirtualCameraReadinessSnapshot(
            hasChecked: true,
            isInstalled: true,
            isEnabled: true,
            isVersionCurrent: true
        )
    }

    private func resolve(
        _ snapshot: VirtualCameraReadinessSnapshot,
        input: CameraAvailability = .ready
    ) -> CameraReadiness {
        CameraReadiness.resolve(
            authorization: .authorized,
            virtualCamera: snapshot.availability,
            inputCamera: input
        )
    }
}
