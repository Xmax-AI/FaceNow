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

    /// Whether an enabled matching extension was found by the system.
    @Published private(set) var isEnabled = false

    /// Identifies the in-flight request so delayed delegate calls cannot overwrite newer state.
    private var pendingRequest: OSSystemExtensionRequest?
    private var pendingKind: RequestKind?

    /// Refreshes system state without installing or activating anything.
    func refresh() {
        guard !isBusy else { return }
        submit(OSSystemExtensionRequest.propertiesRequest(
            forExtensionWithIdentifier: CameraConfiguration.extensionBundleID, queue: .main
        ), kind: .properties)
    }

    /// Asks macOS to activate the extension packaged inside the application.
    func install() {
        guard Bundle.main.bundleURL.resolvingSymlinksInPath().path.hasPrefix("/Applications/") else {
            status = "Move Xmax Camera to /Applications before installing the extension."
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
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Starts a request on the main queue and keeps controls stable until it finishes.
    private func submit(_ request: OSSystemExtensionRequest, kind: RequestKind) {
        guard !isBusy else { return }
        isBusy = true
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
            self.status = "Approval required in System Settings → Camera Extensions."
        }
    }

    /// Reports request completion and checks whether the camera is enabled.
    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        let identifier = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.pendingRequest.map(ObjectIdentifier.init) == identifier,
                  self.pendingKind != .properties else { return }
            self.pendingRequest = nil
            self.pendingKind = nil
            self.isBusy = false
            self.status = result == .completed ? "Request completed" : "Restart required to finish setup"
            if result == .completed { self.refresh() }
        }
    }

    /// Reports setup failures without treating a missing extension as installed.
    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let message = error.localizedDescription
        let identifier = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.pendingRequest.map(ObjectIdentifier.init) == identifier else { return }
            self.pendingRequest = nil
            self.pendingKind = nil
            self.isBusy = false
            self.status = message
        }
    }

    /// Refreshes enabled state from macOS rather than persisting a guessed install flag.
    nonisolated func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        let enabled = properties.contains { $0.isEnabled && !$0.isUninstalling }
        let identifier = ObjectIdentifier(request)
        Task { @MainActor in
            guard self.pendingRequest.map(ObjectIdentifier.init) == identifier else { return }
            self.pendingRequest = nil
            self.pendingKind = nil
            self.isBusy = false
            self.isEnabled = enabled
            self.status = enabled ? "Camera extension enabled" : "Camera extension not enabled"
        }
    }

    /// Distinguishes a status query from an operation that needs a subsequent refresh.
    private enum RequestKind { case properties, activation, deactivation }
}
