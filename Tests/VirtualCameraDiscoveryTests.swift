import XCTest
import os
@testable import CameraCore

final class VirtualCameraDiscoveryTests: XCTestCase, @unchecked Sendable {
    func testDeviceNotificationWakesDiscoveryBeforeNextPoll() async throws {
        let firstProbe = expectation(description: "Initial probe")
        let discovered = expectation(description: "Notification triggers discovery")
        let available = OSAllocatedUnfairLock(initialState: false)
        let expected = VirtualCameraDiscovery.Sink(device: 91, stream: 92)
        let task = Task {
            let result = try await VirtualCameraDiscovery.waitForSink(timeout: .seconds(15), pollInterval: .seconds(10)) {
                if available.withLock({ $0 }) { return expected }
                firstProbe.fulfill()
                return nil
            }
            discovered.fulfill()
            return result
        }
        await fulfillment(of: [firstProbe], timeout: 1)
        available.withLock { $0 = true }
        NotificationCenter.default.post(name: CameraDeviceMonitor.didChange, object: nil)
        await fulfillment(of: [discovered], timeout: 1)
        task.cancel()
        let result = try await task.value
        XCTAssertEqual(result, expected)
    }

    func testStatusRefreshDoesNotRestartReadinessAfterTimeout() {
        var policy = CameraReadinessPolicy()
        XCTAssertTrue(policy.shouldCheck(version: "17"))
        for _ in 0..<20 { XCTAssertFalse(policy.shouldCheck(version: "17")) }
        XCTAssertTrue(policy.shouldCheck(version: "17", force: true))
        XCTAssertFalse(policy.shouldCheck(version: "17"))
    }

    func testUpdateOrReactivationChecksDeviceAgain() {
        var policy = CameraReadinessPolicy()
        XCTAssertTrue(policy.shouldCheck(version: "17"))
        XCTAssertTrue(policy.shouldCheck(version: "18"))
        XCTAssertFalse(policy.shouldCheck(version: "18"))
        policy.reset()
        XCTAssertTrue(policy.shouldCheck(version: "18"))
    }

    func testDelayedSinkBecomesReadyWithoutRestart() async throws {
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let expected = VirtualCameraDiscovery.Sink(device: 42, stream: 43)
        let sink = try await VirtualCameraDiscovery.waitForSink(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            attempts.withLock { count in
                count += 1
                return count >= 3 ? expected : nil
            }
        }
        XCTAssertEqual(sink, expected)
        XCTAssertGreaterThanOrEqual(attempts.withLock { $0 }, 3)
    }

    func testReplacementRetriesTransientPropertyErrors() async throws {
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let expected = VirtualCameraDiscovery.Sink(device: 72, stream: 73)
        let sink = try await VirtualCameraDiscovery.waitForSink(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            try attempts.withLock { count in
                count += 1
                if count < 3 { throw NSError(domain: NSOSStatusErrorDomain, code: -1) }
                return expected
            }
        }
        XCTAssertEqual(sink, expected)
    }

    func testUnavailableSinkTimesOutAndCanBeRetried() async throws {
        do {
            _ = try await VirtualCameraDiscovery.waitForSink(timeout: .milliseconds(30), pollInterval: .milliseconds(10)) { nil }
            XCTFail("A missing device must not be reported ready")
        } catch VirtualCameraDiscovery.DiscoveryError.timedOut {} catch {
            XCTFail("Unexpected error: \(error)")
        }
        let expected = VirtualCameraDiscovery.Sink(device: 82, stream: 83)
        let sink = try await VirtualCameraDiscovery.waitForSink { expected }
        XCTAssertEqual(sink, expected)
    }

    func testCancellationStopsProbingAndDoesNotAcceptLateDevice() async throws {
        let probed = expectation(description: "Initial device probe")
        let state = OSAllocatedUnfairLock(initialState: (count: 0, available: false))
        let task = Task {
            try await VirtualCameraDiscovery.waitForSink(timeout: .seconds(30), pollInterval: .milliseconds(10)) {
                state.withLock { value in
                    value.count += 1
                    if value.count == 1 { probed.fulfill() }
                    return value.available ? VirtualCameraDiscovery.Sink(device: 1, stream: 2) : nil
                }
            }
        }
        await fulfillment(of: [probed], timeout: 1)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled discovery must not return a device")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let count = state.withLock { value in value.available = true; return value.count }
        NotificationCenter.default.post(name: CameraDeviceMonitor.didChange, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(state.withLock { $0.count }, count)
    }
}
