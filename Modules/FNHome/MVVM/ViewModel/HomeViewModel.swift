//
//  HomeViewModel.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory
import Foundation
import XmaxSDK

/// Derives home navigation and startup decisions from shared business repositories.
@MainActor
final class HomeViewModel {

    /// The persisted account and SDK-key owner.
    @Injected(\.userRepo) private var userRepo: UserRepository

    /// The generation lifecycle receiving start, cleanup, and setup failures.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// The shared camera authorization and optional virtual-output readiness.
    @Injected(\.virtualCameraRepo) private var virtualCameraRepo: VirtualCameraRepository

    /// Whether account authentication should cover the mounted home content.
    var needsLogin: Bool { !userRepo.canAccessHome }

    /// Whether camera permission permits entry to the generation workspace.
    var canStart: Bool { virtualCameraRepo.canStartSession }

    /// Whether generation startup should display the landing-page progress state.
    var isStarting: Bool { generationRepo.isBusy && !generationRepo.isClosing }

    /// Whether the API-key editor must preserve the active generation credential.
    var settingsLocked: Bool { generationRepo.settingsLocked || generationRepo.isClosing }

    /// The current startup restriction displayed by the landing page.
    var startUnavailableMessage: String {
        virtualCameraRepo.startUnavailableMessage
    }

    /// Opens local capture after validating permission; cloud generation validates its own credentials.
    func startCamera(
        preset: RealtimeCameraPreset,
        reference: GenerationReference,
        requestedAt: UInt64
    ) async {
        virtualCameraRepo.synchronizeReadiness()
        guard canStart else {
            generationRepo.showSetupError(startUnavailableMessage)
            return
        }
        await generationRepo.start(
            preset: preset,
            initialReference: reference,
            requestedAt: requestedAt
        )
    }

    /// Waits for generation cleanup before clearing the account and returning to sign-in.
    func signOut() async {
        await generationRepo.close()
        do {
            try await userRepo.signOut()
        } catch { generationRepo.showSetupError(error.localizedDescription) }
    }
}
