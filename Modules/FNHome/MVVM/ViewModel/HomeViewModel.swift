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

/// Derives home navigation and startup decisions from shared business repositories.
@MainActor
final class HomeViewModel {

    /// The persisted account and SDK-key owner.
    @Injected(\.userRepo) private var userRepo: UserRepository

    /// The generation lifecycle receiving start, cleanup, and setup failures.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// The extension readiness required before starting generation.
    @Injected(\.virtualCameraRepo) private var virtualCameraRepo: VirtualCameraRepository

    /// Whether account authentication should cover the mounted home content.
    var needsLogin: Bool { !userRepo.canAccessHome }

    /// Whether installation readiness and account operations permit the Start action.
    var canStart: Bool {
        userRepo.canAccessHome && virtualCameraRepo.canStartSession && !userRepo.isBusy && !userRepo.isLoadingKeys
    }

    /// Whether generation startup should display the landing-page progress state.
    var isStarting: Bool { generationRepo.isBusy && !generationRepo.isClosing }

    /// Whether the API-key editor must preserve the active generation credential.
    var settingsLocked: Bool { generationRepo.settingsLocked || generationRepo.isClosing }

    /// The current startup restriction displayed by the landing page.
    var startUnavailableMessage: String {
        guard userRepo.canAccessHome else { return "Sign in before starting the camera." }
        return userRepo.isBusy || userRepo.isLoadingKeys
            ? "Please wait for the account request to finish." : virtualCameraRepo.startUnavailableMessage
    }

    /// Starts generation after validating account operations and actual extension readiness.
    func startCamera(
        requestedAt: UInt64
    ) async {
        guard canStart else {
            generationRepo.showSetupError(startUnavailableMessage)
            return
        }
        await generationRepo.start(
            useMicrophone: false,
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
