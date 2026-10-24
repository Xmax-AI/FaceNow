import Foundation

/// Remains armed through AppKit's final termination notifications, even if the main thread blocks.
final class AppExitWatchdog: @unchecked Sendable {
    private let timer: DispatchSourceTimer

    init(timeout: DispatchTimeInterval = .seconds(10), terminate: @escaping @Sendable () -> Void) {
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "ai.xmax.camera.exit-deadline"))
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler(handler: terminate)
        timer.resume()
    }

    deinit { timer.cancel() }
}

/// Bounds application shutdown even when an SDK or network operation ignores cancellation.
@MainActor
final class AppShutdownCoordinator {
    private var cleanupTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var completion: (@MainActor (Bool) -> Void)?
    private var started = false

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

    private func finish(timedOut: Bool) {
        guard let completion else { return }
        self.completion = nil
        cleanupTask?.cancel()
        deadlineTask?.cancel()
        cleanupTask = nil
        deadlineTask = nil
        completion(timedOut)
    }
}
