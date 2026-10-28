//
//  OnboardingSetupViewModel.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory

/// Derives setup control labels and availability from the virtual-camera repository.
@MainActor
final class OnboardingSetupViewModel {

    /// The extension installation and discovery owner shared with the home page.
    @Injected(\.virtualCameraRepo) private var virtualCameraRepo: VirtualCameraRepository

    /// The current system or readiness message.
    var status: String { virtualCameraRepo.status }

    /// Whether a new independent status refresh can start.
    var canRefresh: Bool {
        !virtualCameraRepo.isRefreshing && (!virtualCameraRepo.isBusy || virtualCameraRepo.isAwaitingApproval)
    }

    /// The explicit activation action shown for the current installation state.
    var installTitle: String {
        virtualCameraRepo.isEnabled
            ? OnboardingStrings.update
            : virtualCameraRepo.isAwaitingApproval
                ? OnboardingStrings.setupAwaitingApproval : OnboardingStrings.guideInstallEnable
    }

    /// Whether an installed extension exposes the removal action.
    var showsRemove: Bool { virtualCameraRepo.isEnabled }

    /// Whether discovery or a system operation needs indeterminate progress.
    var isWaiting: Bool {
        if case .checking = virtualCameraRepo.readiness { return true }
        return false
    }

    /// Whether the launch explicitly enabled the diagnostic video controls.
    var showsTestVideo: Bool { VirtualCameraDiagnostics.activationRequested }

    /// Preserves generation's settings lock while installation or queries are running.
    func canInstall(
        settingsLocked: Bool
    ) -> Bool { !settingsLocked && !virtualCameraRepo.isBusy && !virtualCameraRepo.isRefreshing }

    /// Requires a usable device and an idle generation lifecycle before diagnostic output.
    func canTestVideo(
        isBusy: Bool,
        sessionActive: Bool
    ) -> Bool { virtualCameraRepo.isDeviceReady && !isBusy && !sessionActive }
}
