import XCTest
@testable import CameraCore

@MainActor
final class UpdateInstallationGateTests: XCTestCase {

    func testActiveMediaPostponesInstallationAndIdleResumesOnlyOnce() async {
        var available = false
        var installations = 0
        let gate = UpdateInstallationGate { available }
        XCTAssertTrue(gate.postponeIfNeeded { installations += 1 })
        gate.resumeIfPossible()
        XCTAssertEqual(installations, 0)
        available = true
        gate.resumeIfPossible()
        gate.resumeIfPossible()
        XCTAssertEqual(installations, 1)
        XCTAssertFalse(gate.isPostponed)
    }

    func testCancellationPreventsAnOldUpdateFromInstallingAfterCaptureStops() async {
        var available = false
        let gate = UpdateInstallationGate { available }
        XCTAssertTrue(gate.postponeIfNeeded { XCTFail("Cancelled update must not resume") })
        gate.cancel()
        available = true
        gate.resumeIfPossible()
        XCTAssertFalse(gate.isPostponed)
    }

    func testIdleApplicationLeavesImmediateInstallationToSparkle() async {
        let gate = UpdateInstallationGate { true }
        XCTAssertFalse(gate.postponeIfNeeded { XCTFail("An immediate update must not be retained") })
        gate.resumeIfPossible()
        XCTAssertFalse(gate.isPostponed)
    }

    func testContinuationIsConsumedBeforeSynchronousCallbacksCanResumeAgain() async {
        var available = false
        var installations = 0
        let gate = UpdateInstallationGate { available }
        XCTAssertTrue(gate.postponeIfNeeded {
            installations += 1
            gate.resumeIfPossible()
        })
        available = true
        gate.resumeIfPossible()
        XCTAssertEqual(installations, 1)
    }
}
