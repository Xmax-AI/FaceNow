//
//  AppLaunchTiming.swift
//  FaceNow
//

import Foundation

/// Measures one accepted Start click through binding the first display-ready result to the app's view.
/// Uses monotonic nanoseconds and lifecycle IDs so delayed work cannot finish a newer startup.
struct AppLaunchTiming: Equatable, Sendable {

    /// The sequential stages measured from an accepted Start action to visible result binding.
    enum Phase: Int, CaseIterable, Sendable {

        /// Time spent waiting for an earlier producer or cleanup operation.
        case previousCleanup

        /// Time spent preparing application-owned generation dependencies.
        case appSetup

        /// Time spent preparing SDK capture and obtaining a display-ready generated frame.
        case generation

        /// Time spent binding the generated result to its mounted preview.
        case resultView

        /// The diagnostic label describing the measured stage.
        var name: String {
            switch self {
            case .previousCleanup: "Queue and previous cleanup"
            case .appSetup: "App setup"
            case .generation: "SDK camera preparation and generation"
            case .resultView: "Result view binding"
            }
        }
    }

    /// The lifecycle identity allowed to advance or finish this measurement.
    private var operation: UUID?

    /// The accepted Start action time in monotonic nanoseconds.
    private var startedAt: UInt64?

    /// The current stage start in monotonic nanoseconds.
    private var phaseStartedAt: UInt64?

    /// The first completed result binding time, absent while startup is pending.
    private var finishedAt: UInt64?

    /// The completed stage durations in nanoseconds.
    private var durations: [Phase: UInt64] = [:]

    /// The currently measured stage, absent before an accepted Start action.
    private(set) var phase: Phase?

    /// Resets timing for one accepted operation at its original Start timestamp.
    mutating func begin(
        operation: UUID,
        at requestedAt: UInt64
    ) {
        self = AppLaunchTiming()
        self.operation = operation
        startedAt = requestedAt
        phaseStartedAt = requestedAt
        phase = .previousCleanup
    }

    /// Accepts only the next stage for this lifecycle with a nondecreasing timestamp.
    @discardableResult
    mutating func advance(
        to next: Phase,
        operation: UUID,
        at time: UInt64
    ) -> Bool {
        guard self.operation == operation, finishedAt == nil,
            let phase, let phaseStartedAt, time >= phaseStartedAt,
            next.rawValue == phase.rawValue + 1
        else { return false }
        durations[phase] = time - phaseStartedAt
        self.phaseStartedAt = time
        self.phase = next
        return true
    }

    /// Completes result binding once for the matching lifecycle and monotonic clock.
    @discardableResult
    mutating func finish(
        operation: UUID,
        at time: UInt64
    ) -> Bool {
        guard self.operation == operation, finishedAt == nil, phase == .resultView,
            let phaseStartedAt, time >= phaseStartedAt
        else { return false }
        durations[.resultView] = time - phaseStartedAt
        finishedAt = time
        return true
    }

    /// Returns a completed stage duration converted from nanoseconds to milliseconds.
    func milliseconds(
        for phase: Phase
    ) -> Double? {
        durations[phase].map { Double($0) / 1_000_000 }
    }

    /// The accumulated cleanup and app-setup duration, available after SDK startup begins.
    var preparationMs: Double? {
        guard let phase, phase.rawValue >= Phase.generation.rawValue else { return nil }
        return Double(
            Phase.allCases.filter { $0.rawValue < Phase.generation.rawValue }
                .reduce(UInt64(0)) { $0 + (durations[$1] ?? 0) }
        ) / 1_000_000
    }

    /// The directly measured Start-to-result duration, absent before binding completes.
    var totalMs: Double? {
        guard let startedAt, let finishedAt else { return nil }
        return Double(finishedAt - startedAt) / 1_000_000
    }

    /// The completed preparation stages formatted for diagnostics.
    var preparationSummary: String {
        Phase.allCases.filter { $0.rawValue < Phase.generation.rawValue }.map { phase in
            let value =
                milliseconds(for: phase).map {
                    String(
                        format: "%.1f ms",
                        $0
                    )
                } ?? "—"
            return "\(phase.name): \(value)"
        }.joined(separator: "\n")
    }

    /// The stage durations formatted without inventing unavailable measurements.
    var summary: String {
        Phase.allCases.map { phase in
            let value =
                milliseconds(for: phase).map {
                    String(
                        format: "%.1f ms",
                        $0
                    )
                } ?? "—"
            return "\(phase.name)=\(value)"
        }.joined(separator: "; ")
    }
}
