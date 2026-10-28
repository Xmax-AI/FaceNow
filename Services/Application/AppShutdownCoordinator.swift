import Foundation

/// Remains armed through AppKit's final termination notifications, even if the main thread blocks.
final class AppExitWatchdog: @unchecked Sendable {

    /// The independent dispatch timer that remains active if the main thread stalls.
    private let timer: DispatchSourceTimer

    /// Arms the independent termination deadline on its dedicated serial queue.
    init(
        timeout: DispatchTimeInterval = .seconds(10),
        terminate: @escaping @Sendable () -> Void
    ) {
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "ai.xmax.camera.exit-deadline"))
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler(handler: terminate)
        timer.resume()
    }

    /// Cancels the watchdog when its owning lifetime ends.
    deinit { timer.cancel() }
}

/// Bounds application shutdown even when an SDK or network operation ignores cancellation.
@MainActor
final class AppShutdownCoordinator {

    /// The main-actor cleanup operation bounded by the deadline task.
    private var cleanupTask: Task<Void, Never>?

    /// The asynchronous deadline that completes shutdown when cleanup takes too long.
    private var deadlineTask: Task<Void, Never>?

    /// The callback consumed once by cleanup completion or timeout.
    private var completion: (@MainActor (Bool) -> Void)?

    /// Whether this coordinator has already accepted its one shutdown operation.
    private var started = false

    /// Starts one cleanup and deadline pair without blocking AppKit termination handling.
    func start(
        timeout: Duration = .seconds(8),
        cleanup: @escaping @MainActor () async -> Void,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard !started else { return }
        started = true
        self.completion = completion
        cleanupTask = Task {
            await cleanup()
            finish(timedOut: false)
        }
        deadlineTask = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            finish(timedOut: true)
        }
    }

    /// Consumes completion once and cancels both remaining coordination tasks.
    private func finish(
        timedOut: Bool
    ) {
        guard let completion else { return }
        self.completion = nil
        cleanupTask?.cancel()
        deadlineTask?.cancel()
        cleanupTask = nil
        deadlineTask = nil
        completion(timedOut)
    }
}
