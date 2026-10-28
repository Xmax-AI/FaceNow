//
//  VirtualCameraDiagnostics.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
import os

/// Probes CMIO in an embedded helper that inherits the host's sandbox.
enum VirtualCameraDiagnostics {

    /// The bundled helper executable allowed to perform fresh-process discovery.
    static let helperName = "FaceNowCameraProbe"

    /// The helper-only argument selecting a single discovery snapshot.
    static let probeArgument = "--camera-discovery-probe"

    /// The host argument verifying launch of the embedded helper.
    static let verificationArgument = "--verify-camera-probe"

    /// The host argument comparing cached and fresh-process discovery.
    static let comparisonArgument = "--compare-camera-discovery"

    /// The opt-in argument enabling diagnostics after extension activation.
    static let activationArgument = "--diagnose-camera-activation"

    /// A local test bundle can opt in without changing the user's saved preferences.
    static var activationRequested: Bool {
        CommandLine.arguments.contains(activationArgument)
            || Bundle.main.object(forInfoDictionaryKey: "FaceNowDiagnoseCameraActivation") as? Bool == true
    }

    /// The host executable must never be relaunched as an inheriting sandbox helper.
    static func helperExecutable(
        in bundleURL: URL = Bundle.main.bundleURL
    ) throws -> URL {
        let helper = bundleURL.appendingPathComponent("Contents/Helpers/\(helperName)")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw ProbeError.missingExecutable
        }
        return helper
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

    /// Classifies discovery availability without comparing process-local CMIO identifiers.
    enum Assessment: String, Codable, Sendable {

        /// Both the host and helper expose a usable producer sink.
        case bothReady

        /// The host discovers the sink after the helper has observed publication.
        case hostRecovered

        /// Only the fresh helper observes a usable sink, suggesting stale host discovery.
        case possibleStaleHost

        /// Neither process observes a usable producer sink.
        case bothUnavailable

        /// Missing, failed, or inconsistent samples prevent a reliable comparison.
        case inconclusive
    }

    /// Retains host samples around a bounded fresh-process discovery probe.
    struct Comparison: Codable, Sendable {

        /// The host snapshot collected before starting the helper.
        let hostBefore: VirtualCameraDiscovery.Snapshot

        /// The host snapshot collected after the helper completes.
        let hostAfter: VirtualCameraDiscovery.Snapshot

        /// The independent helper snapshot, absent when launching or decoding fails.
        let fresh: VirtualCameraDiscovery.Snapshot?

        /// The helper failure description, excluding credentials and video contents.
        let probeFailure: String?

        /// The availability classification derived from process identity and sample ordering.
        var assessment: Assessment {
            guard probeFailure == nil, let fresh,
                hostBefore.processID == hostAfter.processID, fresh.processID != hostAfter.processID,
                fresh.uptime >= hostBefore.uptime, fresh.uptime <= hostAfter.uptime,
                hostBefore.failures.isEmpty, hostAfter.failures.isEmpty, fresh.failures.isEmpty
            else {
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

        /// Encodes the classification and original snapshots for diagnostic inspection.
        func reportData() throws -> Data {

            /// The serialized diagnostic classification and its source samples.
            struct Report: Encodable {

                /// The classification accompanying the captured samples.
                let assessment: Assessment

                /// The unmodified samples supporting the reported classification.
                let samples: Comparison
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(
                Report(
                    assessment: assessment,
                    samples: self
                )
            )
        }
    }

    /// Collects ordered host and helper snapshots, propagating caller cancellation.
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
        return Comparison(
            hostBefore: before,
            hostAfter: hostProbe(),
            fresh: fresh,
            probeFailure: failure
        )
    }

    /// Runs before NSApplication and the app delegate initialize any capture-related state.
    @MainActor
    static func handleCommandLine(
        sdkVersion: String? = nil
    ) -> Bool {
        let arguments = CommandLine.arguments
        let isProbe = arguments.contains(verificationArgument)
        guard isProbe || arguments.contains(comparisonArgument) else { return false }
        Task {
            do {
                let data: Data
                let executable = try helperExecutable()
                if isProbe {
                    // Exercises the real signed host -> helper launch, even without an enabled camera.
                    let sample = try await FreshProcessProbe().run(executable: executable)
                    guard sample.processID != ProcessInfo.processInfo.processIdentifier else {
                        throw ProbeError.invalidProcess
                    }

                    /// The host-to-helper verification payload emitted before AppKit starts.
                    struct Verification: Encodable {

                        /// The host identifier used to verify that the helper is a distinct process.
                        let hostProcessID: Int32

                        /// The host-linked SDK version supplied by the application entry point.
                        let sdkVersion: String?

                        /// The independent snapshot returned by the embedded executable.
                        let helper: VirtualCameraDiscovery.Snapshot
                    }
                    data = try JSONEncoder().encode(
                        Verification(
                            hostProcessID: ProcessInfo.processInfo.processIdentifier,
                            sdkVersion: sdkVersion,
                            helper: sample
                        )
                    )
                } else {
                    VirtualCameraDeviceMonitor.shared.start()
                    data = try await compare(executable: executable).reportData()
                }
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(
                    Data("Camera discovery diagnostic failed: \(error.localizedDescription)\n".utf8)
                )
                exit(EXIT_FAILURE)
            }
        }
        dispatchMain()
    }

    /// Describes executable validation, timeout, and child-process termination failures.
    private enum ProbeError: LocalizedError {

        /// The expected embedded helper is absent or not executable.
        case missingExecutable

        /// The requested executable or reported process identity is not the expected helper.
        case invalidProcess

        /// The child failed to return a snapshot within the bounded probe timeout.
        case timedOut

        /// The helper exited with the associated nonzero status.
        case exited(Int32)

        /// The helper terminated because of the associated signal status.
        case signaled(Int32)

        /// A setup-oriented description of the helper failure.
        var errorDescription: String? {
            switch self {
            case .missingExecutable: "The camera discovery helper is missing. Reinstall FaceNow."
            case .invalidProcess: "Camera discovery must run in the dedicated helper."
            case .timedOut: "The fresh camera probe exceeded its five-second deadline."
            case .exited(let status): "The fresh camera probe exited with status \(status)."
            case .signaled(let signal): "The camera discovery helper was terminated by signal \(signal)."
            }
        }
    }

    /// A probe never opens a stream or requests camera permission. Cancellation terminates only this child.
    private final class FreshProcessProbe: @unchecked Sendable {

        /// The child handle and continuation protected by the probe lock.
        private struct State {

            /// Whether cancellation, timeout, or termination has already completed this probe.
            var finished = false

            /// The child process retained only until the probe completes.
            var process: Process?

            /// The suspended caller resumed exactly once by the completion gate.
            var continuation: CheckedContinuation<VirtualCameraDiscovery.Snapshot, Error>?
        }

        /// The lock protecting completion, process ownership, and continuation handoff.
        private let state = OSAllocatedUnfairLock(initialState: State())

        /// Launches the validated helper and bounds its lifetime by cancellation and timeout.
        func run(
            executable: URL
        ) async throws -> VirtualCameraDiscovery.Snapshot {
            guard executable.lastPathComponent == VirtualCameraDiagnostics.helperName else {
                throw ProbeError.invalidProcess
            }
            return try await withTaskCancellationHandler {
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
                            let error =
                                child.terminationReason == .uncaughtSignal
                                ? ProbeError.signaled(child.terminationStatus)
                                : ProbeError.exited(child.terminationStatus)
                            self?.finish(.failure(error))
                            return
                        }
                        self?.finish(
                            Result {
                                try JSONDecoder().decode(
                                    VirtualCameraDiscovery.Snapshot.self,
                                    from: data
                                )
                            }
                        )
                    }
                    do {
                        let started = try state.withLock { value in
                            guard !value.finished else { return false }
                            value.process = process
                            value.continuation = continuation
                            try process.run()
                            return true
                        }
                        guard started else {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                    } catch {
                        finish(.failure(error))
                        return
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                        self?.finish(
                            .failure(ProbeError.timedOut),
                            terminate: true
                        )
                    }
                }
            } onCancel: {
                self.finish(
                    .failure(CancellationError()),
                    terminate: true
                )
            }
        }

        /// Resumes the caller once and optionally terminates only this probe child.
        private func finish(
            _ result: Result<VirtualCameraDiscovery.Snapshot, Error>,
            terminate: Bool = false
        ) {
            let pending = state.withLock {
                value -> (CheckedContinuation<VirtualCameraDiscovery.Snapshot, Error>?, Process?) in
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
