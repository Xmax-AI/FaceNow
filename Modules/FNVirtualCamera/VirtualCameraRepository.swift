//
//  VirtualCameraRepository.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory
import AppKit
import Combine
import SystemExtensions
import os

/// Manages explicit, user-initiated installation and removal of the bundled camera.
@MainActor
final class VirtualCameraRepository: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {

    /// The sole generated-frame transport shared with generation.
    let output = VirtualCameraOutput()

    /// The shared device publisher used by generation and extension readiness.
    let deviceMonitor = VirtualCameraDeviceMonitor.shared

    /// The current system response displayed beside setup controls.
    @Published private(set) var status = "Not checked"

    /// Whether the system is processing a request or waiting for approval.
    @Published private(set) var isBusy = false

    /// User approval is a pending action rather than indeterminate processing.
    @Published private(set) var isAwaitingApproval = false

    /// Status queries are independent of a pending activation request.
    @Published private(set) var isRefreshing = false

    /// Whether an enabled matching extension was found by the system.
    @Published private(set) var isEnabled = false

    /// Whether the enabled extension matches the bundled build version.
    @Published private(set) var isVersionCurrent = false

    /// The system must expose the bundled extension before capture can start.
    var canStartSession: Bool {
        isEnabled && isVersionCurrent && isDeviceReady && !isBusy && !isRefreshing && !requiresRestart
    }

    /// The current reason capture cannot start through the virtual camera.
    var startUnavailableMessage: String {
        if requiresRestart { return "Restart your Mac to finish camera extension setup." }
        if isAwaitingApproval { return "Approve the FaceNow camera extension in System Settings." }
        if isBusy || isRefreshing { return "Camera extension setup is still in progress." }
        if !isEnabled { return "Install and enable Virtual Camera before starting the camera." }
        if !isVersionCurrent { return "Update Virtual Camera to match this version of FaceNow." }
        return status
    }

    /// Activation and device publication complete at different times.
    @Published private(set) var isWaitingForDevice = false

    /// Whether the published virtual device exposes a usable producer sink.
    @Published private(set) var isDeviceReady = false

    /// Whether system extension removal or replacement still requires a restart.
    @Published private(set) var requiresRestart = false

    /// The bounded device-publication and sink-discovery operation.
    private var readinessTask: Task<Void, Never>?

    /// Rejects delayed completion from superseded device-readiness checks.
    private var readinessID = UUID()

    /// Tracks which extension version has already received a bounded readiness check.
    private var readinessPolicy = VirtualCameraReadinessPolicy()

    /// Whether an explicit refresh should recheck a previously observed extension version.
    private var forceDeviceCheck = false

    /// Retains device-publication notifications without opening capture streams.
    private var deviceObservation: AnyCancellable?

    /// The optional host-versus-helper discovery comparison task.
    private var diagnosticTask: Task<Void, Never>?

    /// Rejects delayed results from cancelled discovery comparisons.
    private var diagnosticID = UUID()

    /// Whether an opt-in activation diagnostic is waiting for readiness evaluation.
    private var diagnoseAfterReadiness = false

    /// Defers host discovery while an explicit activation diagnostic is requested.
    private var deferDiscoveryUntilActivation = VirtualCameraDiagnostics.activationRequested

    /// Reports extension-state and discovery diagnostics without reading video frames.
    private let logger = Logger(
        subsystem: VirtualCameraConfiguration.appBundleID,
        category: "DiscoveryComparison"
    )

    /// Observes device publication while leaving extension activation to explicit user actions.
    override init() {
        super.init()
        deviceObservation = VirtualCameraDeviceMonitor.shared.changes.sink { [weak self] in
            guard let self, !self.isBusy, !self.requiresRestart, !self.isWaitingForDevice else { return }
            // A late arrival must recover even after the previous bounded check timed out.
            if self.isEnabled {
                self.cancelDeviceWait()
                self.waitForDevice()
            } else {
                self.refresh(
                    retryDeviceDiscovery: true,
                    preservingFailure: true
                )
            }
        }
    }

    /// Identifies the in-flight request so delayed delegate calls cannot overwrite newer state.
    private var pendingRequest: OSSystemExtensionRequest?

    /// The activation or deactivation operation associated with the current request.
    private var pendingKind: RequestKind?

    /// The independent in-flight system extension properties query.
    private var propertiesRequest: OSSystemExtensionRequest?

    /// Background device/property refreshes must not erase the result of an explicit user request.
    private var requestFailureMessage: String?

    /// The extension build version embedded in the current application bundle.
    private var bundledExtensionVersion: String? {
        let url = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Library/SystemExtensions/\(VirtualCameraConfiguration.extensionBundleID).systemextension"
        )
        return Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// Refreshes system state without installing or activating anything.
    func refresh(
        retryDeviceDiscovery: Bool = false,
        preservingFailure: Bool = false
    ) {
        guard (!isBusy || isAwaitingApproval), propertiesRequest == nil else { return }
        if !preservingFailure { requestFailureMessage = nil }
        forceDeviceCheck = retryDeviceDiscovery
        let request = OSSystemExtensionRequest.propertiesRequest(
            forExtensionWithIdentifier: VirtualCameraConfiguration.extensionBundleID,
            queue: .main
        )
        propertiesRequest = request
        isRefreshing = true
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Asks macOS to activate the extension packaged inside the application.
    func install() {
        guard Bundle.main.bundleURL.resolvingSymlinksInPath().path.hasPrefix("/Applications/") else {
            status = "Move FaceNow to /Applications before installing the extension."
            return
        }
        submit(
            OSSystemExtensionRequest.activationRequest(
                forExtensionWithIdentifier: VirtualCameraConfiguration.extensionBundleID,
                queue: .main
            ),
            kind: .activation
        )
    }

    /// Removes the persistent camera when explicitly requested by the user.
    func uninstall() {
        submit(
            OSSystemExtensionRequest.deactivationRequest(
                forExtensionWithIdentifier: VirtualCameraConfiguration.extensionBundleID,
                queue: .main
            ),
            kind: .deactivation
        )
    }

    /// Opens the system extension settings without changing system preferences.
    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Starts a request on the main queue and keeps controls stable until it finishes.
    private func submit(
        _ request: OSSystemExtensionRequest,
        kind: RequestKind
    ) {
        guard !isBusy, !isRefreshing else { return }
        cancelDiscoveryComparison()
        cancelDeviceWait()
        readinessPolicy.reset()
        requestFailureMessage = nil
        requiresRestart = false
        isBusy = true
        isAwaitingApproval = false
        pendingRequest = request
        pendingKind = kind
        status = kind == .deactivation ? "Removing virtual camera…" : "Installing camera extension…"
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Updates a previously installed copy when the host contains a newer build.
    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    /// Keeps the request pending while the user grants macOS approval.
    nonisolated func requestNeedsUserApproval(
        _ request: OSSystemExtensionRequest
    ) {
        let identifier = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.pendingRequest.map(ObjectIdentifier.init) == identifier else { return }
            self.isAwaitingApproval = true
            self.status =
                "Enable FaceNow - Xmax Virtual Camera in System Settings → General → Login Items & Extensions → Camera Extensions."
        }
    }

    /// Reports request completion and checks whether the camera is enabled.
    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        let identifier = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.pendingRequest.map(ObjectIdentifier.init) == identifier else { return }
            let activated = self.pendingKind == .activation && result == .completed
            if activated {
                self.deferDiscoveryUntilActivation = false
                self.logger.notice("Camera activation completed before starting deferred discovery")
            }
            self.pendingRequest = nil
            self.pendingKind = nil
            self.isBusy = false
            self.isAwaitingApproval = false
            self.propertiesRequest = nil
            self.isRefreshing = false
            self.requiresRestart = result == .willCompleteAfterReboot
            if self.requiresRestart {
                self.cancelDeviceWait()
                self.status = "Restart your Mac to finish camera extension setup."
            } else {
                self.diagnoseAfterReadiness = activated && VirtualCameraDiagnostics.activationRequested
                self.status = "Request completed"
                self.refresh()
            }
        }
    }

    /// Reports setup failures without treating a missing extension as installed.
    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        didFailWithError error: Error
    ) {
        let message = error.localizedDescription
        let systemError = error as NSError
        let errorDomain = systemError.domain
        let errorCode = systemError.code
        let identifier = ObjectIdentifier(request)
        Task { @MainActor in
            if self.propertiesRequest.map(ObjectIdentifier.init) == identifier {
                self.propertiesRequest = nil
                self.isRefreshing = false
                if !self.isBusy, !self.requiresRestart { self.status = self.requestFailureMessage ?? message }
                return
            }
            guard self.pendingRequest.map(ObjectIdentifier.init) == identifier else { return }
            let removal = self.pendingKind == .deactivation
            let failure: String
            self.logger.error(
                "Camera extension request failed: \(errorDomain, privacy: .public) (\(errorCode)): \(message, privacy: .public)"
            )
            if removal, errorDomain == OSSystemExtensionErrorDomain,
                errorCode == OSSystemExtensionError.Code.extensionNotFound.rawValue
            {
                failure =
                    "Removal failed: macOS could not match the installed camera to this app. Click Update, then Remove, or remove it in System Settings."
            } else {
                failure = "\(removal ? "Removal" : "Installation") failed: \(message)"
            }
            self.pendingRequest = nil
            self.pendingKind = nil
            self.isBusy = false
            self.isAwaitingApproval = false
            self.propertiesRequest = nil
            self.isRefreshing = false
            self.requestFailureMessage = failure
            self.status = failure
            self.refresh(preservingFailure: true)
        }
    }

    /// Refreshes enabled state from macOS rather than persisting a guessed install flag.
    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        foundProperties properties: [OSSystemExtensionProperties]
    ) {
        let records = properties.map {
            VirtualCameraInstallationState.Record(
                version: $0.bundleVersion,
                isEnabled: $0.isEnabled,
                isUninstalling: $0.isUninstalling
            )
        }
        let identifier = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.propertiesRequest.map(ObjectIdentifier.init) == identifier else { return }
            self.propertiesRequest = nil
            self.isRefreshing = false
            let installation = VirtualCameraInstallationState(
                records: records,
                bundledVersion: self.bundledExtensionVersion
            )
            let enabled = installation.isEnabled
            let current = installation.isVersionCurrent
            let version = installation.enabledVersions.sorted().joined(separator: ",")
            self.isEnabled = enabled
            self.isVersionCurrent = current
            // A verified current enabled version supersedes an older restart requirement.
            if current { self.requiresRestart = false }
            // An already-enabled old version must not complete approval for its replacement.
            guard !self.isBusy, !self.requiresRestart else { return }
            if installation.requiresRestartForRemoval {
                self.cancelDeviceWait()
                self.requiresRestart = true
                self.status = "Restart your Mac to finish removing the previous camera extension."
                return
            }
            if enabled, !current {
                self.cancelDeviceWait()
                self.status = self.requestFailureMessage ?? "Update Virtual Camera to match this version of FaceNow."
                return
            }
            if enabled {
                if self.deferDiscoveryUntilActivation {
                    self.status =
                        self.requestFailureMessage ?? "Camera extension enabled. Click Update to test activation."
                    return
                }
                if self.readinessPolicy.shouldCheck(
                    version: version,
                    force: self.forceDeviceCheck
                ) {
                    self.cancelDeviceWait()
                    self.waitForDevice()
                }
            } else {
                self.cancelDiscoveryComparison()
                self.cancelDeviceWait()
                self.readinessPolicy.reset()
                self.status = self.requestFailureMessage ?? "Camera extension not enabled"
            }
            self.forceDeviceCheck = false
        }
    }

    /// Checks the actual CMIO sink after activation, rather than equating enabled with usable.
    private func waitForDevice() {
        guard readinessTask == nil else { return }
        let id = UUID()
        readinessID = id
        isDeviceReady = false
        isWaitingForDevice = true
        status = requestFailureMessage ?? "Camera extension enabled. Waiting for the camera to become available…"
        readinessTask = Task { [weak self] in
            do {
                if !VirtualCameraDeviceMonitor.shared.isStarted {
                    let executable = try VirtualCameraDiagnostics.helperExecutable()
                    try await VirtualCameraDiagnostics.waitForPublication(executable: executable)
                    guard let self, self.readinessID == id, !Task.isCancelled else { return }
                    self.logger.notice("Fresh process confirmed camera publication before host discovery startup")
                    VirtualCameraDeviceMonitor.shared.start()
                }
                _ = try await VirtualCameraDiscovery.waitForSink()
                guard let self, self.readinessID == id, !Task.isCancelled else { return }
                self.logger.notice("Virtual camera sink discovered after enabled-state verification")
                self.isDeviceReady = true
                self.status = self.requestFailureMessage ?? "Virtual camera ready"
                self.isWaitingForDevice = false
                self.readinessTask = nil
                self.compareDiscoveryIfRequested()
            } catch {
                guard let self, self.readinessID == id, !Task.isCancelled else { return }
                var message = "Camera not ready: \(error.localizedDescription) Click Refresh to retry."
                if VirtualCameraDeviceMonitor.shared.isStarted,
                    let executable = try? VirtualCameraDiagnostics.helperExecutable(),
                    let comparison = try? await VirtualCameraDiagnostics.compare(executable: executable),
                    comparison.assessment == .possibleStaleHost
                {
                    message =
                        "macOS has refreshed the camera, but FaceNow still has the previous device list. Quit and reopen FaceNow to continue."
                }
                guard self.readinessID == id, !Task.isCancelled else { return }
                self.status = self.requestFailureMessage ?? message
                self.logger.error("Camera readiness failed: \(message, privacy: .public)")
                self.isWaitingForDevice = false
                self.readinessTask = nil
                self.compareDiscoveryIfRequested()
            }
        }
    }

    /// Invalidates readiness work before clearing the published device-ready state.
    private func cancelDeviceWait() {
        readinessID = UUID()
        readinessTask?.cancel()
        readinessTask = nil
        isWaitingForDevice = false
        isDeviceReady = false
    }

    /// Invalidates and cancels the pending optional discovery diagnostic.
    private func cancelDiscoveryComparison() {
        diagnosticID = UUID()
        diagnoseAfterReadiness = false
        diagnosticTask?.cancel()
        diagnosticTask = nil
    }

    /// Opt-in diagnostics leave normal startup and the user's camera stream unchanged.
    private func compareDiscoveryIfRequested() {
        guard diagnoseAfterReadiness, diagnosticTask == nil else { return }
        diagnoseAfterReadiness = false
        let id = UUID()
        diagnosticID = id
        diagnosticTask = Task { [weak self] in
            do {
                let executable = try VirtualCameraDiagnostics.helperExecutable()
                let comparison = try await VirtualCameraDiagnostics.compare(executable: executable)
                guard let self, self.diagnosticID == id, !Task.isCancelled else { return }
                let report = String(
                    decoding: try comparison.reportData(),
                    as: UTF8.self
                )
                self.logger.notice("Camera discovery comparison: \(report, privacy: .public)")
                self.diagnosticTask = nil
            } catch {
                guard let self, self.diagnosticID == id, !Task.isCancelled else { return }
                self.logger.error("Camera discovery comparison failed: \(error.localizedDescription, privacy: .public)")
                self.diagnosticTask = nil
            }
        }
    }

    /// Cancels device-readiness and diagnostic tasks when the extension owner is released.
    isolated deinit {
        readinessTask?.cancel()
        diagnosticTask?.cancel()
    }

    /// Distinguishes a status query from an operation that needs a subsequent refresh.
    private enum RequestKind {

        /// Installs or replaces the bundled virtual-camera extension.
        case activation

        /// Removes the virtual-camera extension from the system.
        case deactivation
    }
}

extension Container {

    /// The shared VirtualCamera repository registered for this container.
    @MainActor
    var virtualCameraRepo: Factory<VirtualCameraRepository> {
        Factory(self) { @MainActor in VirtualCameraRepository() }.singleton
    }
}
