import Foundation
import os

/// Compares one process before and after a fresh copy of the same executable probes CMIO.
enum CameraDiscoveryDiagnostics {
    static let probeArgument = "--camera-discovery-probe"
    static let comparisonArgument = "--compare-camera-discovery"
    static let activationArgument = "--diagnose-camera-activation"

    /// A local test bundle can opt in without changing the user's saved preferences.
    static var activationRequested: Bool {
        CommandLine.arguments.contains(activationArgument) ||
        Bundle.main.object(forInfoDictionaryKey: "FaceNowDiagnoseCameraActivation") as? Bool == true
    }

    /// Wait for actual device publication without initializing the caller's CMIO hardware list.
    /// Each retry uses a new process; a probe started before publication can itself become stale.
    static func waitForPublication(
        executable: URL,
        timeout: Duration = .seconds(12),
        freshProbe: @Sendable (URL) async throws -> VirtualCameraDiscovery.Snapshot = {
            try await FreshProcessProbe().run(executable: $0)
        }
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            try Task.checkCancellation()
            let sample = try await freshProbe(executable)
            try Task.checkCancellation()
            if sample.sink != nil, sample.failures.isEmpty { return }
            guard ContinuousClock.now < deadline else { throw VirtualCameraDiscovery.DiscoveryError.timedOut }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    enum Assessment: String, Codable, Sendable {
        case bothReady, hostRecovered, possibleStaleHost, bothUnavailable, inconclusive
    }

    struct Comparison: Codable, Sendable {
        let hostBefore: VirtualCameraDiscovery.Snapshot
        let hostAfter: VirtualCameraDiscovery.Snapshot
        let fresh: VirtualCameraDiscovery.Snapshot?
        let probeFailure: String?

        var assessment: Assessment {
            guard probeFailure == nil, let fresh,
                  hostBefore.processID == hostAfter.processID, fresh.processID != hostAfter.processID,
                  fresh.uptime >= hostBefore.uptime, fresh.uptime <= hostAfter.uptime,
                  hostBefore.failures.isEmpty, hostAfter.failures.isEmpty, fresh.failures.isEmpty else {
                return .inconclusive
            }
            // CMIO numeric IDs are process-local; compare availability, not ID equality.
            if hostAfter.sink != nil, fresh.sink != nil {
                return hostBefore.sink == nil ? .hostRecovered : .bothReady
            }
            if hostBefore.sink == nil, hostAfter.sink == nil, fresh.sink != nil { return .possibleStaleHost }
            if hostBefore.sink == nil, hostAfter.sink == nil, fresh.sink == nil { return .bothUnavailable }
            return .inconclusive
        }

        func reportData() throws -> Data {
            struct Report: Encodable { let assessment: Assessment; let samples: Comparison }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(Report(assessment: assessment, samples: self))
        }
    }

    static func compare(
        executable: URL,
        hostProbe: @Sendable () -> VirtualCameraDiscovery.Snapshot = { VirtualCameraDiscovery.snapshot() },
        freshProbe: @Sendable (URL) async throws -> VirtualCameraDiscovery.Snapshot = {
            try await FreshProcessProbe().run(executable: $0)
        }
    ) async throws -> Comparison {
        try Task.checkCancellation()
        let before = hostProbe()
        let fresh: VirtualCameraDiscovery.Snapshot?
        let failure: String?
        do {
            fresh = try await freshProbe(executable)
            failure = nil
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            fresh = nil
            failure = error.localizedDescription
        }
        try Task.checkCancellation()
        return Comparison(hostBefore: before, hostAfter: hostProbe(), fresh: fresh, probeFailure: failure)
    }

    /// Runs before NSApplication and the app delegate initialize any capture-related state.
    @MainActor
    static func handleCommandLine() -> Bool {
        let arguments = CommandLine.arguments
        let isProbe = arguments.contains(probeArgument)
        guard isProbe || arguments.contains(comparisonArgument) else { return false }
        Task {
            do {
                let data: Data
                if isProbe {
                    // Give a newly initialized process a bounded window to discover the device.
                    do { _ = try await VirtualCameraDiscovery.waitForSink(timeout: .seconds(2)) } catch {}
                    data = try JSONEncoder().encode(VirtualCameraDiscovery.snapshot())
                } else {
                    CameraDeviceMonitor.shared.start()
                    guard let executable = Bundle.main.executableURL else { throw ProbeError.missingExecutable }
                    data = try await compare(executable: executable).reportData()
                }
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data("Camera discovery diagnostic failed: \(error.localizedDescription)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        dispatchMain()
    }

    private enum ProbeError: LocalizedError {
        case missingExecutable, timedOut, exited(Int32)
        var errorDescription: String? {
            switch self {
            case .missingExecutable: "Cannot locate the current app executable."
            case .timedOut: "The fresh camera probe exceeded its five-second deadline."
            case .exited(let status): "The fresh camera probe exited with status \(status)."
            }
        }
    }

    /// A probe never opens a stream or requests camera permission. Cancellation terminates only this child.
    private final class FreshProcessProbe: @unchecked Sendable {
        private struct State {
            var finished = false
            var process: Process?
            var continuation: CheckedContinuation<VirtualCameraDiscovery.Snapshot, Error>?
        }
        private let state = OSAllocatedUnfairLock(initialState: State())

        func run(executable: URL) async throws -> VirtualCameraDiscovery.Snapshot {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    let process = Process()
                    let output = Pipe()
                    process.executableURL = executable
                    process.arguments = [probeArgument]
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    process.terminationHandler = { [weak self] child in
                        let data = output.fileHandleForReading.readDataToEndOfFile()
                        guard child.terminationStatus == 0 else {
                            self?.finish(.failure(ProbeError.exited(child.terminationStatus)))
                            return
                        }
                        self?.finish(Result { try JSONDecoder().decode(VirtualCameraDiscovery.Snapshot.self, from: data) })
                    }
                    do {
                        let started = try state.withLock { value in
                            guard !value.finished else { return false }
                            value.process = process
                            value.continuation = continuation
                            try process.run()
                            return true
                        }
                        guard started else { continuation.resume(throwing: CancellationError()); return }
                    } catch {
                        finish(.failure(error))
                        return
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                        self?.finish(.failure(ProbeError.timedOut), terminate: true)
                    }
                }
            } onCancel: {
                self.finish(.failure(CancellationError()), terminate: true)
            }
        }

        private func finish(_ result: Result<VirtualCameraDiscovery.Snapshot, Error>, terminate: Bool = false) {
            let pending = state.withLock { value -> (CheckedContinuation<VirtualCameraDiscovery.Snapshot, Error>?, Process?) in
                guard !value.finished else { return (nil, nil) }
                value.finished = true
                let pending = (value.continuation, value.process)
                value.continuation = nil
                value.process = nil
                return pending
            }
            if terminate, let process = pending.1, process.isRunning { process.terminate() }
            pending.0?.resume(with: result)
        }
    }
}
