import XCTest
import os
@testable import CameraCore

final class CameraDiscoveryDiagnosticsTests: XCTestCase, @unchecked Sendable {
    func testPublicationWaitRetriesUntilFreshProbeSeesSink() async throws {
        let count = OSAllocatedUnfairLock(initialState: 0)
        try await CameraDiscoveryDiagnostics.waitForPublication(
            executable: URL(fileURLWithPath: "/unused"), timeout: .seconds(2),
            freshProbe: { _ in
                var sample = VirtualCameraDiscovery.Snapshot()
                if count.withLock({ $0 += 1; return $0 }) == 2 {
                    sample.sink = .init(device: 41, stream: 42)
                }
                return sample
            }
        )
        XCTAssertEqual(count.withLock { $0 }, 2)
    }

    func testPublicationWaitRejectsIncompleteOrFailedQueries() async throws {
        do {
            try await CameraDiscoveryDiagnostics.waitForPublication(
                executable: URL(fileURLWithPath: "/unused"), timeout: .zero,
                freshProbe: { _ in
                    var sample = VirtualCameraDiscovery.Snapshot()
                    sample.sink = .init(device: 41, stream: 42)
                    sample.failures = [.init(operation: "device list", object: 1, status: -1)]
                    return sample
                }
            )
            XCTFail("A failed query must not release deferred host discovery")
        } catch VirtualCameraDiscovery.DiscoveryError.timedOut {}
    }

    func testPublicationWaitCancellationRejectsLateSuccessfulProbe() async throws {
        let started = expectation(description: "Probe started")
        let task = Task {
            try await CameraDiscoveryDiagnostics.waitForPublication(
                executable: URL(fileURLWithPath: "/unused"),
                freshProbe: { _ in
                    started.fulfill()
                    try? await Task.sleep(for: .seconds(30))
                    var sample = VirtualCameraDiscovery.Snapshot()
                    sample.sink = .init(device: 41, stream: 42)
                    return sample
                }
            )
        }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        do { try await task.value; XCTFail("Cancelled publication wait must not succeed") }
        catch is CancellationError {}
    }

    func testPublicationWaitReportsChildLaunchFailure() async throws {
        do {
            try await CameraDiscoveryDiagnostics.waitForPublication(
                executable: URL(fileURLWithPath: "/nonexistent/FaceNow")
            )
            XCTFail("A child launch failure must not release host discovery")
        } catch is CancellationError { XCTFail("Unexpected cancellation") }
        catch VirtualCameraDiscovery.DiscoveryError.timedOut { XCTFail("Launch failure must not hang until timeout") }
        catch {}
    }

    func testOnlyFreshProcessSeeingSinkSuggestsStaleHost() {
        XCTAssertEqual(comparison(before: false, after: false, fresh: true).assessment, .possibleStaleHost)
    }

    func testProcessLocalIDsDoNotCauseFalseMismatch() {
        let result = comparison(before: true, after: true, fresh: true)
        XCTAssertNotEqual(result.hostAfter.sink, result.fresh?.sink)
        XCTAssertEqual(result.assessment, .bothReady)
    }

    func testHostRecoveryDuringProbeIsNotClassifiedAsStale() {
        XCTAssertEqual(comparison(before: false, after: true, fresh: true).assessment, .hostRecovered)
    }

    func testBothProcessesMissingDeviceDoesNotImplicateHostCache() {
        XCTAssertEqual(comparison(before: false, after: false, fresh: false).assessment, .bothUnavailable)
    }

    func testQueryErrorsAreInconclusive() {
        var before = snapshot(pid: 1, time: 10, ready: false)
        before.failures = [.init(operation: "device list", object: 1, status: -1)]
        let result = CameraDiscoveryDiagnostics.Comparison(
            hostBefore: before, hostAfter: snapshot(pid: 1, time: 12, ready: false),
            fresh: snapshot(pid: 2, time: 11, ready: true), probeFailure: nil
        )
        XCTAssertEqual(result.assessment, .inconclusive)
    }

    func testSameProcessOrOutOfWindowProbeCannotConfirmDifference() {
        for fresh in [snapshot(pid: 1, time: 11, ready: true), snapshot(pid: 2, time: 9, ready: true)] {
            let result = CameraDiscoveryDiagnostics.Comparison(
                hostBefore: snapshot(pid: 1, time: 10, ready: false),
                hostAfter: snapshot(pid: 1, time: 12, ready: false), fresh: fresh, probeFailure: nil
            )
            XCTAssertEqual(result.assessment, .inconclusive)
        }
    }

    func testReportIncludesAssessmentAndPreservesQueryFailures() throws {
        var sample = snapshot(pid: 2, time: 11, ready: false)
        sample.failures = [.init(operation: "output streams", object: 42, status: -123)]
        let decoded = try JSONDecoder().decode(VirtualCameraDiscovery.Snapshot.self, from: JSONEncoder().encode(sample))
        XCTAssertEqual(decoded.failures.first?.status, -123)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: comparison(before: true, after: true, fresh: true).reportData()) as? [String: Any])
        XCTAssertEqual(report["assessment"] as? String, "bothReady")
    }

    func testFreshProcessFailureIsReportedWithoutFalseCacheConclusion() async throws {
        let result = try await CameraDiscoveryDiagnostics.compare(
            executable: URL(fileURLWithPath: "/nonexistent/FaceNow"),
            hostProbe: { VirtualCameraDiscovery.Snapshot() },
            freshProbe: { _ in throw CocoaError(.executableNotLoadable) }
        )
        XCTAssertEqual(result.assessment, .inconclusive)
        XCTAssertNotNil(result.probeFailure)
    }

    func testFailedExecutableLaunchCompletesWithoutHanging() async throws {
        let result = try await CameraDiscoveryDiagnostics.compare(
            executable: URL(fileURLWithPath: "/nonexistent/FaceNow"),
            hostProbe: { VirtualCameraDiscovery.Snapshot() }
        )
        XCTAssertEqual(result.assessment, .inconclusive)
        XCTAssertNotNil(result.probeFailure)
    }

    func testCancellationDoesNotContinueSamplingHost() async throws {
        let samples = OSAllocatedUnfairLock(initialState: 0)
        let started = expectation(description: "Fresh probe started")
        let task = Task {
            try await CameraDiscoveryDiagnostics.compare(
                executable: URL(fileURLWithPath: "/unused"),
                hostProbe: {
                    samples.withLock { $0 += 1 }
                    return VirtualCameraDiscovery.Snapshot()
                },
                freshProbe: { _ in
                    started.fulfill()
                    try await Task.sleep(for: .seconds(30))
                    return VirtualCameraDiscovery.Snapshot()
                }
            )
        }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled diagnostics must stop")
        } catch is CancellationError {}
        XCTAssertEqual(samples.withLock { $0 }, 1)
    }

    private func comparison(before: Bool, after: Bool, fresh: Bool) -> CameraDiscoveryDiagnostics.Comparison {
        .init(hostBefore: snapshot(pid: 1, time: 10, ready: before), hostAfter: snapshot(pid: 1, time: 12, ready: after),
              fresh: snapshot(pid: 2, time: 11, ready: fresh), probeFailure: nil)
    }

    private func snapshot(pid: Int32, time: TimeInterval, ready: Bool) -> VirtualCameraDiscovery.Snapshot {
        var result = VirtualCameraDiscovery.Snapshot()
        result.processID = pid
        result.uptime = time
        if ready {
            result.virtualDevice = UInt32(pid * 10)
            result.outputStreams = [UInt32(pid * 10 + 1)]
            result.sink = .init(device: UInt32(pid * 10), stream: UInt32(pid * 10 + 1))
        }
        return result
    }
}
