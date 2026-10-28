import XCTest
@testable import CameraCore

final class AppLaunchTimingTests: XCTestCase {

    func testTotalIncludesPreparationGenerationAndViewBinding() throws {
        let operation = UUID()
        var timing = AppLaunchTiming()
        timing.begin(
            operation: operation,
            at: 0
        )
        XCTAssertNil(timing.preparationMs)
        XCTAssertNil(timing.totalMs)

        for (phase, time) in [
            (AppLaunchTiming.Phase.appSetup, 100),
            (.generation, 600),
        ] {
            XCTAssertTrue(
                timing.advance(
                    to: phase,
                    operation: operation,
                    at: ns(time)
                )
            )
        }
        XCTAssertEqual(
            timing.preparationMs,
            600
        )
        XCTAssertEqual(
            timing.milliseconds(for: .appSetup),
            500
        )
        XCTAssertNil(timing.totalMs)

        XCTAssertTrue(
            timing.advance(
                to: .resultView,
                operation: operation,
                at: ns(7_800)
            )
        )
        XCTAssertEqual(
            timing.milliseconds(for: .generation),
            7_200
        )
        XCTAssertNil(
            timing.totalMs,
            "SDK completion alone must not finish the app's startup"
        )
        XCTAssertTrue(
            timing.finish(
                operation: operation,
                at: ns(7_900)
            )
        )
        XCTAssertEqual(
            timing.totalMs,
            7_900
        )
        let preparation = try XCTUnwrap(timing.preparationMs)
        let generation = try XCTUnwrap(timing.milliseconds(for: .generation))
        let view = try XCTUnwrap(timing.milliseconds(for: .resultView))
        XCTAssertEqual(
            preparation + generation + view,
            timing.totalMs
        )
    }

    func testStartClickIncludesTimeBeforeAsyncStartRuns() {
        let operation = UUID()
        var timing = AppLaunchTiming()
        timing.begin(
            operation: operation,
            at: ns(1_000)
        )
        timing.advance(
            to: .appSetup,
            operation: operation,
            at: ns(1_500)
        )
        XCTAssertEqual(
            timing.milliseconds(for: .previousCleanup),
            500
        )
    }

    func testLateCompletionCannotChangeNewStartup() {
        let old = UUID(), current = UUID()
        var timing = AppLaunchTiming()
        timing.begin(
            operation: old,
            at: 0
        )
        timing.advance(
            to: .appSetup,
            operation: old,
            at: ns(100)
        )
        timing.begin(
            operation: current,
            at: ns(200)
        )
        let snapshot = timing
        XCTAssertFalse(
            timing.advance(
                to: .appSetup,
                operation: old,
                at: ns(300)
            )
        )
        XCTAssertFalse(
            timing.finish(
                operation: old,
                at: ns(400)
            )
        )
        XCTAssertEqual(
            timing,
            snapshot
        )
        XCTAssertTrue(
            timing.advance(
                to: .appSetup,
                operation: current,
                at: ns(300)
            )
        )
        XCTAssertEqual(
            timing.milliseconds(for: .previousCleanup),
            100
        )
    }

    func testCancelledStartupCannotBeFinishedByLateViewUpdate() {
        let operation = UUID()
        var timing = completedPhases(operation: operation)
        timing = AppLaunchTiming()
        XCTAssertFalse(
            timing.finish(
                operation: operation,
                at: ns(100)
            )
        )
        XCTAssertNil(timing.totalMs)
        XCTAssertNil(timing.preparationMs)
    }

    func testRepeatedStateNotificationsDoNotResetPhaseOrFinishedTiming() {
        let operation = UUID()
        var timing = completedPhases(operation: operation)
        let pending = timing
        XCTAssertFalse(
            timing.advance(
                to: .resultView,
                operation: operation,
                at: ns(100)
            )
        )
        XCTAssertEqual(
            timing,
            pending
        )
        XCTAssertTrue(
            timing.finish(
                operation: operation,
                at: ns(100)
            )
        )
        let finished = timing
        XCTAssertFalse(
            timing.finish(
                operation: operation,
                at: ns(200)
            )
        )
        XCTAssertFalse(
            timing.advance(
                to: .generation,
                operation: operation,
                at: ns(300)
            )
        )
        XCTAssertEqual(
            timing,
            finished
        )
    }

    func testMissingOrOutOfOrderMilestonesCannotProduceTotal() {
        let operation = UUID()
        var timing = AppLaunchTiming()
        timing.begin(
            operation: operation,
            at: 0
        )
        XCTAssertFalse(
            timing.advance(
                to: .generation,
                operation: operation,
                at: ns(100)
            )
        )
        XCTAssertFalse(
            timing.finish(
                operation: operation,
                at: ns(200)
            )
        )
        XCTAssertNil(timing.totalMs)
        XCTAssertTrue(
            timing.advance(
                to: .appSetup,
                operation: operation,
                at: ns(300)
            )
        )
    }

    func testNonmonotonicEventsCannotProduceNegativeDuration() {
        let operation = UUID()
        var timing = AppLaunchTiming()
        timing.begin(
            operation: operation,
            at: ns(100)
        )
        XCTAssertFalse(
            timing.advance(
                to: .appSetup,
                operation: operation,
                at: ns(99)
            )
        )
        XCTAssertNil(timing.milliseconds(for: .previousCleanup))
        timing = completedPhases(operation: operation)
        XCTAssertFalse(
            timing.finish(
                operation: operation,
                at: 0
            )
        )
        XCTAssertNil(timing.totalMs)
    }

    func testZeroDurationIsACompletedMeasurement() {
        let operation = UUID()
        var timing = AppLaunchTiming()
        timing.begin(
            operation: operation,
            at: 0
        )
        for phase in AppLaunchTiming.Phase.allCases.dropFirst() {
            XCTAssertTrue(
                timing.advance(
                    to: phase,
                    operation: operation,
                    at: 0
                )
            )
        }
        XCTAssertTrue(
            timing.finish(
                operation: operation,
                at: 0
            )
        )
        XCTAssertEqual(
            timing.preparationMs,
            0
        )
        XCTAssertEqual(
            timing.totalMs,
            0
        )
    }

    private func completedPhases(
        operation: UUID
    ) -> AppLaunchTiming {
        var timing = AppLaunchTiming()
        timing.begin(
            operation: operation,
            at: 0
        )
        for phase in AppLaunchTiming.Phase.allCases.dropFirst() {
            timing.advance(
                to: phase,
                operation: operation,
                at: ns(phase.rawValue)
            )
        }
        return timing
    }

    private func ns(
        _ milliseconds: Int
    ) -> UInt64 { UInt64(milliseconds) * 1_000_000 }
}
