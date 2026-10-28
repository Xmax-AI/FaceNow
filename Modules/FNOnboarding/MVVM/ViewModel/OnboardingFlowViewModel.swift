//
//  OnboardingFlowViewModel.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import AVFoundation
import Combine
import Factory

/// Derives guide presentation and coordinates explicit device-preparation actions.
@MainActor
final class OnboardingFlowViewModel: ObservableObject {

    /// The persistent preparation progress shared with home navigation.
    @Injected(\.onboardingRepo) var onboardingRepo: OnboardingRepository

    /// The shared owner of installed-extension and output-device readiness.
    @Injected(\.virtualCameraRepo) var virtualCameraRepo: VirtualCameraRepository

    /// The shared physical-input selection, without creating another capture session.
    @Injected(\.generationRepo) var generationRepo: GenerationRepository

    /// The last permission check, refreshed when the application regains focus.
    @Published private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)

    /// Whether the system camera permission prompt is awaiting an answer.
    @Published private(set) var isRequestingAccess = false

    /// Whether camera access requires an explicit settings change instead of another prompt.
    var needsCameraSettings: Bool { authorization == .denied || authorization == .restricted }

    /// Whether permission and any already-discovered physical input permit preparation.
    var cameraReady: Bool {
        authorization == .authorized
            && (!virtualCameraRepo.deviceMonitor.isStarted || !generationRepo.cameras.isEmpty)
    }

    /// Whether the actual output device is available independently of a transient properties query.
    var virtualCameraReady: Bool {
        virtualCameraRepo.isEnabled && virtualCameraRepo.isVersionCurrent && virtualCameraRepo.isDeviceReady
            && !virtualCameraRepo.isBusy && !virtualCameraRepo.requiresRestart
    }

    /// The persistent home reminder, retained after the modal is deferred.
    var reminder: String {
        if !cameraReady {
            return authorization == .authorized
                ? "No camera found. Connect a camera to continue."
                : "Camera access is required. Finish setting up FaceNow."
        }
        if !virtualCameraReady { return "Virtual Camera is not ready. Finish setup to use FaceNow in video calls." }
        return onboardingRepo.hasCompletedGuide
            ? "You're ready for video calls." : "One last step: learn how to use FaceNow in video calls."
    }

    /// The camera-specific status that never claims an undiscovered device is available.
    var cameraStatus: String {
        if isRequestingAccess { return "Waiting for camera permission…" }
        if needsCameraSettings { return "Camera access is off. Allow FaceNow in System Settings, then check again." }
        if authorization != .authorized {
            return "FaceNow needs camera access to turn your movements into live effects."
        }
        if !virtualCameraRepo.deviceMonitor.isStarted {
            return "Camera access allowed. Your input camera will be detected after Virtual Camera is enabled."
        }
        if let camera = generationRepo.cameras.first(where: { $0.id == generationRepo.cameraID }) {
            return "Camera ready · \(camera.name)"
        }
        return "No physical camera found. Connect a camera, then check again."
    }

    /// The primary action corresponding to the current preparation requirement.
    var primaryTitle: String {
        switch onboardingRepo.step {
        case .camera:
            if cameraReady { return "Continue" }
            if needsCameraSettings { return "Open System Settings" }
            return authorization == .authorized ? "Check Again" : "Allow Camera Access"
        case .virtualCamera:
            if virtualCameraReady { return "Continue" }
            if virtualCameraRepo.requiresRestart { return "Open System Settings" }
            if virtualCameraRepo.isAwaitingApproval { return "Open System Settings" }
            if virtualCameraRepo.isBusy || virtualCameraRepo.isWaitingForDevice { return "Preparing Virtual Camera…" }
            return virtualCameraRepo.isEnabled ? "Update Virtual Camera" : "Install & Enable"
        case .videoCalls: return "Done, Let's Get Started"
        }
    }

    /// Whether a system operation restricts the current explicit action.
    var primaryEnabled: Bool {
        guard !isRequestingAccess else { return false }
        if onboardingRepo.step == .videoCalls {
            return cameraReady && virtualCameraReady && !virtualCameraRepo.isRefreshing
        }
        if onboardingRepo.step == .virtualCamera {
            guard !generationRepo.settingsLocked else { return virtualCameraReady }
            return virtualCameraReady || virtualCameraRepo.isAwaitingApproval || virtualCameraRepo.requiresRestart
                || (!virtualCameraRepo.isBusy && !virtualCameraRepo.isRefreshing
                    && !virtualCameraRepo.isWaitingForDevice)
        }
        return !generationRepo.settingsLocked || cameraReady
    }

    /// Reads current permission and shared device state without installing or opening capture.
    func synchronize() {
        let current = AVCaptureDevice.authorizationStatus(for: .video)
        if current != authorization { authorization = current }
        onboardingRepo.updateReadiness(
            camera: cameraReady,
            virtualCamera: virtualCameraReady
        )
    }

    /// Rechecks requirements after returning from settings or requesting a retry.
    func refresh() {
        generationRepo.refreshCameras()
        synchronize()
        virtualCameraRepo.refresh(retryDeviceDiscovery: true)
    }

    /// Executes only the action explicitly selected in the current guide stage.
    func performPrimaryAction() async {
        let requestedStep = onboardingRepo.step
        synchronize()
        guard onboardingRepo.isPresented, onboardingRepo.step == requestedStep, primaryEnabled else { return }
        switch requestedStep {
        case .camera:
            if cameraReady {
                onboardingRepo.advance()
            } else if needsCameraSettings {
                openCameraSettings()
            } else if authorization == .notDetermined {
                isRequestingAccess = true
                _ = await AVCaptureDevice.requestAccess(for: .video)
                isRequestingAccess = false
                guard !Task.isCancelled else { return }
                generationRepo.refreshCameras()
                synchronize()
            } else {
                refresh()
            }
        case .virtualCamera:
            if virtualCameraReady {
                onboardingRepo.advance()
            } else if virtualCameraRepo.isAwaitingApproval || virtualCameraRepo.requiresRestart {
                virtualCameraRepo.openSettings()
            } else if primaryEnabled {
                virtualCameraRepo.install()
            }
        case .videoCalls:
            onboardingRepo.complete()
        }
    }

    /// Opens the camera privacy pane without attempting to modify system authorization.
    func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}
