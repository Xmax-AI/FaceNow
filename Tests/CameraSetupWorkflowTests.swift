import XCTest
@testable import FNVirtualCameraCore

final class CameraSetupWorkflowTests: XCTestCase {

    func testCompletedRemovalDoesNotActivateWhileAnOldRecordRemains() {
        var workflow = CameraSetupWorkflow(targetVersion: "52", phase: .removing)
        workflow.removalCompleted(needsRestart: false, bootID: "boot-a")
        XCTAssertEqual(workflow.phase, .confirmingRemoval)
        XCTAssertEqual(observe(&workflow, records: true), .manualRemoval)
        XCTAssertEqual(workflow.phase, .manualRemoval)
    }

    func testConfirmedRemovalContinuesWithInstallation() {
        var workflow = CameraSetupWorkflow(targetVersion: "52", phase: .confirmingRemoval)
        XCTAssertEqual(observe(&workflow, records: false), .install)
        XCTAssertEqual(workflow.phase, .installing)
    }

    func testReopeningAppDoesNotCountAsRequiredRemovalRestart() {
        var workflow = CameraSetupWorkflow(targetVersion: "52", phase: .removing)
        workflow.removalCompleted(needsRestart: true, bootID: "boot-a")
        for _ in 0..<4 {
            XCTAssertEqual(observe(&workflow, records: false), .waitForSystem)
            XCTAssertEqual(workflow.phase, .waitingForRemovalRestart)
        }
    }

    func testRemovalRestartResumesInstallationOnlyAfterFreshEmptyProperties() {
        var workflow = CameraSetupWorkflow(
            targetVersion: "52",
            phase: .waitingForRemovalRestart,
            restartBootID: "boot-a"
        )
        XCTAssertEqual(observe(&workflow, records: false, boot: "boot-b"), .install)
        XCTAssertEqual(workflow.phase, .installing)
    }

    func testStuckRemovalAfterRebootHasManualExitInsteadOfAnotherRebootLoop() {
        var workflow = CameraSetupWorkflow(
            targetVersion: "52",
            phase: .waitingForRemovalRestart,
            restartBootID: "boot-a"
        )
        XCTAssertEqual(observe(&workflow, records: true, removing: true, boot: "boot-b"), .manualRemoval)
        XCTAssertEqual(workflow.phase, .manualRemoval)
        for _ in 0..<3 {
            XCTAssertEqual(observe(&workflow, records: true, removing: true, boot: "boot-b"), .manualRemoval)
        }
    }

    func testRemovalScheduledBySystemRequiresRestartBeforeInstalling() {
        var workflow = CameraSetupWorkflow(targetVersion: "52", phase: .confirmingRemoval)
        XCTAssertEqual(observe(&workflow, records: true, removing: true), .waitForSystem)
        XCTAssertEqual(workflow.restartBootID, "boot-a")
    }

    func testCurrentRecordInstalledElsewhereIsVerifiedRatherThanRemovedAgain() {
        var workflow = CameraSetupWorkflow(targetVersion: "52", phase: .manualRemoval)
        XCTAssertEqual(observe(&workflow, records: true, current: true), .verify)
        XCTAssertEqual(workflow.phase, .verifying)
    }

    func testInterruptedInstallationWithNoRecordDoesNotResubmitAutomatically() {
        var workflow = CameraSetupWorkflow(targetVersion: "52", phase: .installing)
        XCTAssertEqual(observe(&workflow, records: false), .none)
        XCTAssertEqual(workflow.phase, .failed)
        XCTAssertEqual(workflow.failure?.kind, .interrupted)
        XCTAssertEqual(observe(&workflow, records: false), .none)
    }

    func testInstallationRebootBoundaryCannotBeBypassedByEnabledRecordInSameBoot() {
        var workflow = CameraSetupWorkflow(targetVersion: "52", phase: .installing)
        workflow.installationCompleted(needsRestart: true, bootID: "boot-a")
        XCTAssertEqual(observe(&workflow, records: true, current: true), .waitForSystem)
        XCTAssertEqual(observe(&workflow, records: true, current: true, boot: "boot-b"), .verify)
    }

    func testUnknownBootIdentityNeverPretendsThatRestartOccurred() {
        var workflow = CameraSetupWorkflow(
            targetVersion: "52",
            phase: .waitingForRemovalRestart,
            restartBootID: "boot-a"
        )
        XCTAssertEqual(observe(&workflow, records: false, boot: ""), .none)
        XCTAssertEqual(workflow.phase, .failed)
        XCTAssertNotNil(workflow.failure)
    }

    func testManualRemovalFinishesTheOriginalAuthorizedReinstall() {
        let failure = CameraOperationFailure(
            operation: .remove,
            kind: .authorization,
            diagnosticMessage: "Authorization denied"
        )
        var workflow = CameraSetupWorkflow(targetVersion: "52", phase: .manualRemoval, failure: failure)
        XCTAssertEqual(observe(&workflow, records: false), .install)
        XCTAssertNil(workflow.failure)
    }

    func testFailedNativeInstallNeverAutomaticallyRetriesOnBackgroundQueries() {
        let failure = CameraOperationFailure(
            operation: .install,
            kind: .invalidBundle,
            diagnosticMessage: "Bad signature"
        )
        var workflow = CameraSetupWorkflow(targetVersion: "52", phase: .failed, failure: failure)
        for _ in 0..<5 { XCTAssertEqual(observe(&workflow, records: false), .none) }
        XCTAssertEqual(workflow.failure, failure)
    }

    func testPersistenceRetainsRestartIntentAndOriginalNSErrorIdentity() throws {
        let suite = "CameraSetupWorkflowTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let failure = CameraOperationFailure.systemExtension(
            operation: .remove,
            domain: "OSSystemExtensionErrorDomain",
            code: 13,
            message: "Authorization denied"
        )
        let workflow = CameraSetupWorkflow(
            targetVersion: "52",
            phase: .waitingForRemovalRestart,
            restartBootID: "boot-a",
            failure: failure
        )
        CameraSetupWorkflow.save(workflow, to: defaults)
        XCTAssertEqual(CameraSetupWorkflow.load(from: defaults, targetVersion: "52"), workflow)
        CameraSetupWorkflow.save(nil, to: defaults)
        XCTAssertNil(CameraSetupWorkflow.load(from: defaults, targetVersion: "52"))
    }

    func testDifferentBundledVersionCancelsAnObsoleteAutomaticIntent() throws {
        let suite = "CameraSetupWorkflowTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        CameraSetupWorkflow.save(.init(targetVersion: "52", phase: .confirmingRemoval), to: defaults)
        XCTAssertNil(CameraSetupWorkflow.load(from: defaults, targetVersion: "53"))
        XCTAssertNil(CameraSetupWorkflow.load(from: defaults, targetVersion: "52"))
    }

    func testSystemErrorClassificationDoesNotOfferBlindRetryForPermanentFailures() {
        let cases: [(Int, CameraOperationFailureKind)] = [
            (2, .invalidBundle), (3, .invalidLocation), (4, .missingExtensionRecord),
            (8, .invalidBundle), (9, .invalidBundle), (10, .systemPolicy),
            (11, .cancelled), (12, .pendingRequest), (13, .authorization), (1, .system),
        ]
        for (code, expected) in cases {
            let failure = CameraOperationFailure.systemExtension(
                operation: .remove,
                domain: "OSSystemExtensionErrorDomain",
                code: code,
                message: "Original details"
            )
            XCTAssertEqual(failure.kind, expected)
            XCTAssertEqual(failure.errorCode, code)
            XCTAssertEqual(failure.diagnosticMessage, "Original details")
        }
        XCTAssertEqual(
            CameraOperationFailure.systemExtension(
                operation: .install,
                domain: "OtherDomain",
                code: 8,
                message: "Network error"
            ).kind,
            .system
        )
    }

    func testInterruptedInstallWithAnObsoleteRecordRequiresManualRemoval() {
        var workflow = CameraSetupWorkflow(targetVersion: "52", phase: .installing)
        XCTAssertEqual(observe(&workflow, records: true), .manualRemoval)
        XCTAssertEqual(workflow.failure?.operation, .remove)
    }

    func testInitialDeviceTimeoutSuggestsSettingsWithoutReinstalling() {
        let recovery = CameraDeviceRecovery(targetVersion: "52", initialBootID: "boot-a")
        XCTAssertEqual(recovery.nextStep(bootID: "boot-a", processID: 100, staleHost: false), .toggleExtension)
        XCTAssertEqual(recovery.nextStep(bootID: "boot-a", processID: 100, staleHost: true), .restartApplication)
    }

    func testFailedAppRelaunchDoesNotCountAsCompletedRecovery() {
        let recovery = CameraDeviceRecovery(targetVersion: "52", initialBootID: "boot-a", relaunchFromProcessID: 100)
        XCTAssertEqual(recovery.nextStep(bootID: "boot-a", processID: 100, staleHost: true), .restartApplication)
        XCTAssertEqual(recovery.nextStep(bootID: "boot-a", processID: 101, staleHost: true), .toggleExtension)
    }

    func testSettingsRecoveryOffersInstallRatherThanSystemRestart() {
        let recovery = CameraDeviceRecovery(targetVersion: "52", initialBootID: "boot-a", settingsOpened: true)
        XCTAssertEqual(recovery.nextStep(bootID: "boot-a", processID: 100, staleHost: false), .install)
    }

    func testRecoveryAfterBootChangeStillOffersExplicitInstall() {
        let recovery = CameraDeviceRecovery(targetVersion: "52", initialBootID: "boot-a", settingsOpened: true)
        XCTAssertEqual(recovery.nextStep(bootID: "boot-b", processID: 101, staleHost: false), .install)
        XCTAssertEqual(recovery.nextStep(bootID: "boot-b", processID: 101, staleHost: true), .install)
    }

    private func observe(
        _ workflow: inout CameraSetupWorkflow,
        records: Bool,
        current: Bool = false,
        removing: Bool = false,
        boot: String = "boot-a"
    ) -> CameraSetupWorkflow.NextAction {
        workflow.reconcile(hasRecords: records, hasCurrentRecord: current, onlyUninstalling: removing, bootID: boot)
    }
}
