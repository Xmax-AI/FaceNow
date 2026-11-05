//
//  HomeVirtualDevicesViewModel.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Combine
import Factory

/// Projects existing device repositories into the home popover without caching readiness.
@MainActor
final class HomeVirtualDevicesViewModel {

    /// The preparation state rendered by a single device row.
    enum Status: Equatable {

        /// The camera repository is checking its current preparation state.
        case checking

        /// The device's extension or driver has not been installed.
        case notInstalled

        /// Installed device preparation requires explicit user attention.
        case needsSetup

        /// The audio driver is installed but has not been published by macOS.
        case pending

        /// The microphone output reported a recoverable failure.
        case failed

        /// The microphone is available but its explicit output switch is off.
        case disabled

        /// The virtual device is available and enabled.
        case enabled

        /// The localized state label displayed beside the status dot.
        var title: String {
            switch self {
            case .checking: HomeStrings.deviceChecking
            case .notInstalled: HomeStrings.deviceNotInstalled
            case .needsSetup: HomeStrings.deviceNeedsSetup
            case .pending: HomeStrings.devicePending
            case .failed: HomeStrings.deviceFailed
            case .disabled: VirtualMicrophoneStrings.disabled
            case .enabled: HomeStrings.deviceEnabled
            }
        }
    }

    /// Owns the single typed virtual-camera preparation result.
    @Injected(\.virtualCameraRepo) private var virtualCameraRepo: VirtualCameraRepository

    /// Owns audio-driver installation, system publication, and output errors.
    @Injected(\.virtualMicrophoneRepo) private var virtualMicrophoneRepo: VirtualMicrophoneRepository

    /// Observes both owners while leaving all business state in their repositories.
    var changes: AnyPublisher<Void, Never> {
        Publishers.Merge(
            virtualCameraRepo.objectWillChange,
            virtualMicrophoneRepo.objectWillChange
        ).eraseToAnyPublisher()
    }

    /// Uses the virtual-output projection independently of physical camera permission.
    var cameraStatus: Status {
        switch virtualCameraRepo.readiness(for: .virtualOutput) {
        case .ready: .enabled
        case .checking: .checking
        case .unavailable(.virtualCameraNotInstalled): .notInstalled
        case .permissionRequired, .unavailable: .needsSetup
        }
    }

    /// Uses the same output and installation state as the microphone setup dialog.
    var microphoneStatus: Status {
        switch virtualMicrophoneRepo.status {
        case .notInstalled: .notInstalled
        case .pending: .pending
        case .disabled: .disabled
        case .enabled: .enabled
        case .failed: .failed
        }
    }

    /// Refreshes cached system facts without requesting installation or starting capture.
    func refresh() {
        virtualCameraRepo.refresh()
        virtualMicrophoneRepo.refreshDeviceAvailability()
    }
}
