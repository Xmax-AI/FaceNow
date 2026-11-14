import XCTest
@testable import CameraCore

@MainActor
final class AppShutdownCoordinatorTests: XCTestCase {

    func testExitWatchdogRunsWhileMainThreadIsBlocked() {
        let fired = DispatchSemaphore(value: 0)
        let watchdog = AppExitWatchdog(timeout: .milliseconds(20)) { fired.signal() }
        // Reproduces a synchronous SDK termination observer blocking AppKit's main thread.
        XCTAssertEqual(
            fired.wait(timeout: .now() + .seconds(1)),
            .success
        )
        withExtendedLifetime(watchdog) {}
    }

    func testCleanupCompletionDoesNotDisarmFinalExitDeadline() async {
        let coordinator = AppShutdownCoordinator()
        let cleaned = expectation(description: "Cleanup finished")
        let finalDeadline = expectation(description: "Independent final deadline remains armed")
        let watchdog = AppExitWatchdog(timeout: .milliseconds(100)) { finalDeadline.fulfill() }
        defer { withExtendedLifetime(watchdog) {} }
        coordinator.start(
            cleanup: {},
            completion: { timedOut in
                XCTAssertFalse(timedOut)
                cleaned.fulfill()
            }
        )
        await fulfillment(
            of: [cleaned, finalDeadline],
            timeout: 2,
            enforceOrder: true
        )
    }

    func testBlockedCleanupAllowsExitAtDeadlineAndLateCompletionDoesNotReplyTwice() async {
        let coordinator = AppShutdownCoordinator()
        let started = expectation(description: "Cleanup started")
        let exit = expectation(description: "Exit allowed despite blocked cleanup")
        let returned = expectation(description: "Late cleanup returned")
        var continuation: CheckedContinuation<Void, Never>?
        var results: [Bool] = []
        coordinator.start(
            timeout: .milliseconds(30),
            cleanup: {
                await withCheckedContinuation {
                    continuation = $0
                    started.fulfill()
                }
                returned.fulfill()
            },
            completion: { timedOut in
                results.append(timedOut)
                exit.fulfill()
            }
        )
        await fulfillment(
            of: [started, exit],
            timeout: 2
        )
        XCTAssertEqual(
            results,
            [true]
        )
        continuation?.resume()
        await fulfillment(
            of: [returned],
            timeout: 2
        )
        await Task.yield()
        XCTAssertEqual(
            results,
            [true]
        )
    }

    func testNormalCleanupRepliesOnceAndRepeatedQuitDoesNotStartAnotherCleanup() async {
        let coordinator = AppShutdownCoordinator()
        let exit = expectation(description: "Normal cleanup completed")
        var cleanups = 0
        var results: [Bool] = []
        coordinator.start(
            timeout: .milliseconds(50),
            cleanup: { cleanups += 1 },
            completion: {
                results.append($0)
                exit.fulfill()
            }
        )
        coordinator.start(
            cleanup: { XCTFail("Repeated quit must share cleanup") },
            completion: { _ in
                XCTFail("Repeated quit must not reply twice")
            }
        )
        await fulfillment(
            of: [exit],
            timeout: 2
        )
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(
            cleanups,
            1
        )
        XCTAssertEqual(
            results,
            [false]
        )
    }
}
