import Foundation

/// Measures one accepted Start click through binding the first display-ready result to the app's view.
/// Uses monotonic nanoseconds and lifecycle IDs so delayed work cannot finish a newer startup.
struct AppLaunchTiming: Equatable, Sendable {
    enum Phase: Int, CaseIterable, Sendable {
        case previousCleanup, appSetup, virtualCamera, generation, resultView

        var name: String {
            switch self {
            case .previousCleanup: "Queue and previous cleanup"
            case .appSetup: "App setup"
            case .virtualCamera: "Virtual camera"
            case .generation: "SDK camera and cloud startup"
            case .resultView: "Result view binding"
            }
        }
    }

    private var operation: UUID?
    private var startedAt: UInt64?
    private var phaseStartedAt: UInt64?
    private var finishedAt: UInt64?
    private var durations: [Phase: UInt64] = [:]
    private(set) var phase: Phase?

    mutating func begin(operation: UUID, at requestedAt: UInt64) {
        self = AppLaunchTiming()
        self.operation = operation
        startedAt = requestedAt
        phaseStartedAt = requestedAt
        phase = .previousCleanup
    }

    @discardableResult
    mutating func advance(to next: Phase, operation: UUID, at time: UInt64) -> Bool {
        guard self.operation == operation, finishedAt == nil,
              let phase, let phaseStartedAt, time >= phaseStartedAt,
              next.rawValue == phase.rawValue + 1 else { return false }
        durations[phase] = time - phaseStartedAt
        self.phaseStartedAt = time
        self.phase = next
        return true
    }

    @discardableResult
    mutating func finish(operation: UUID, at time: UInt64) -> Bool {
        guard self.operation == operation, finishedAt == nil, phase == .resultView,
              let phaseStartedAt, time >= phaseStartedAt else { return false }
        durations[.resultView] = time - phaseStartedAt
        finishedAt = time
        return true
    }

    func milliseconds(for phase: Phase) -> Double? {
        durations[phase].map { Double($0) / 1_000_000 }
    }

    var preparationMs: Double? {
        guard let phase, phase.rawValue >= Phase.generation.rawValue else { return nil }
        return Double(Phase.allCases.filter { $0.rawValue < Phase.generation.rawValue }
            .reduce(UInt64(0)) { $0 + (durations[$1] ?? 0) }) / 1_000_000
    }

    var totalMs: Double? {
        guard let startedAt, let finishedAt else { return nil }
        return Double(finishedAt - startedAt) / 1_000_000
    }

    var preparationSummary: String {
        Phase.allCases.filter { $0.rawValue < Phase.generation.rawValue }.map { phase in
            let value = milliseconds(for: phase).map { String(format: "%.1f ms", $0) } ?? "—"
            return "\(phase.name): \(value)"
        }.joined(separator: "\n")
    }

    var summary: String {
        Phase.allCases.map { phase in
            let value = milliseconds(for: phase).map { String(format: "%.1f ms", $0) } ?? "—"
            return "\(phase.name)=\(value)"
        }.joined(separator: "; ")
    }
}
