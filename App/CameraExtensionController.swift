//
//  CameraExtensionController.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import Combine
import SystemExtensions

/// Manages explicit, user-initiated installation and removal of the bundled camera.
@MainActor
final class CameraExtensionController: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
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

    /// Activation and device publication complete at different times.
    @Published private(set) var isWaitingForDevice = false
    @Published private(set) var isDeviceReady = false
    @Published private(set) var requiresRestart = false
    private var readinessTask: Task<Void, Never>?
    private var readinessID = UUID()
    private var readinessPolicy = CameraReadinessPolicy()
    private var forceDeviceCheck = false
    private var deviceObservation: AnyCancellable?

    override init() {
        super.init()
        deviceObservation = CameraDeviceMonitor.shared.changes.sink { [weak self] in
            guard let self, !self.isBusy, !self.requiresRestart, !self.isWaitingForDevice else { return }
            // A late arrival must recover even after the previous bounded check timed out.
            if self.isEnabled {
                self.cancelDeviceWait()
                self.waitForDevice()
            } else {
                self.refresh(retryDeviceDiscovery: true)
            }
        }
    }

    /// Identifies the in-flight request so delayed delegate calls cannot overwrite newer state.
    private var pendingRequest: OSSystemExtensionRequest?
    private var pendingKind: RequestKind?
    private var propertiesRequest: OSSystemExtensionRequest?

    /// Refreshes system state without installing or activating anything.
    func refresh(retryDeviceDiscovery: Bool = false) {
        guard (!isBusy || isAwaitingApproval), propertiesRequest == nil else { return }
        forceDeviceCheck = retryDeviceDiscovery
        let request = OSSystemExtensionRequest.propertiesRequest(
            forExtensionWithIdentifier: CameraConfiguration.extensionBundleID, queue: .main
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
        submit(OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: CameraConfiguration.extensionBundleID, queue: .main
        ), kind: .activation)
    }

    /// Removes the persistent camera when explicitly requested by the user.
    func uninstall() {
        submit(OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: CameraConfiguration.extensionBundleID, queue: .main
        ), kind: .deactivation)
    }

    /// Opens the system extension settings without changing system preferences.
    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Starts a request on the main queue and keeps controls stable until it finishes.
    private func submit(_ request: OSSystemExtensionRequest, kind: RequestKind) {
        guard !isBusy, !isRefreshing else { return }
        cancelDeviceWait()
        readinessPolicy.reset()
        requiresRestart = false
        isBusy = true
        isAwaitingApproval = false
        pendingRequest = request
        pendingKind = kind
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Updates a previously installed copy when the host contains a newer build.
    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    /// Keeps the request pending while the user grants macOS approval.
    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        let identifier = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.pendingRequest.map(ObjectIdentifier.init) == identifier else { return }
            self.isAwaitingApproval = true
            self.status = "Enable FaceNow - Xmax Virtual Camera in System Settings → General → Login Items & Extensions → Camera Extensions."
        }
    }

    /// Reports request completion and checks whether the camera is enabled.
    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        let identifier = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.pendingRequest.map(ObjectIdentifier.init) == identifier else { return }
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
                self.status = "Request completed"
                self.refresh()
            }
        }
    }

    /// Reports setup failures without treating a missing extension as installed.
    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let message = error.localizedDescription
        let identifier = ObjectIdentifier(request)
        Task { @MainActor in
            if self.propertiesRequest.map(ObjectIdentifier.init) == identifier {
                self.propertiesRequest = nil
                self.isRefreshing = false
                if !self.isBusy, !self.requiresRestart { self.status = message }
                return
            }
            guard self.pendingRequest.map(ObjectIdentifier.init) == identifier else { return }
            self.pendingRequest = nil
            self.pendingKind = nil
            self.isBusy = false
            self.isAwaitingApproval = false
            self.propertiesRequest = nil
            self.isRefreshing = false
            self.status = message
        }
    }

    /// Refreshes enabled state from macOS rather than persisting a guessed install flag.
    nonisolated func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        let enabledProperties = properties.filter { $0.isEnabled && !$0.isUninstalling }
        let enabled = !enabledProperties.isEmpty
        let version = enabledProperties.map { $0.bundleVersion }.sorted().joined(separator: ",")
        let identifier = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.propertiesRequest.map(ObjectIdentifier.init) == identifier else { return }
            self.propertiesRequest = nil
            self.isRefreshing = false
            self.isEnabled = enabled
            // An already-enabled old version must not complete approval for its replacement.
            guard !self.isBusy, !self.requiresRestart else { return }
            if enabled {
                if self.readinessPolicy.shouldCheck(version: version, force: self.forceDeviceCheck) {
                    self.cancelDeviceWait()
                    self.waitForDevice()
                }
            } else {
                self.cancelDeviceWait()
                self.readinessPolicy.reset()
                self.status = "Camera extension not enabled"
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
        status = "Camera extension enabled. Waiting for the camera to become available…"
        readinessTask = Task { [weak self] in
            do {
                _ = try await VirtualCameraDiscovery.waitForSink()
                guard let self, self.readinessID == id, !Task.isCancelled else { return }
                self.isDeviceReady = true
                self.status = "Virtual camera ready"
                self.isWaitingForDevice = false
                self.readinessTask = nil
            } catch {
                guard let self, self.readinessID == id, !Task.isCancelled else { return }
                self.status = "The extension is enabled, but its camera device is unavailable. Click Refresh to retry or Update to reactivate it."
                self.isWaitingForDevice = false
                self.readinessTask = nil
            }
        }
    }

    private func cancelDeviceWait() {
        readinessID = UUID()
        readinessTask?.cancel()
        readinessTask = nil
        isWaitingForDevice = false
        isDeviceReady = false
    }

    isolated deinit { readinessTask?.cancel() }

    /// Distinguishes a status query from an operation that needs a subsequent refresh.
    private enum RequestKind { case activation, deactivation }
}
