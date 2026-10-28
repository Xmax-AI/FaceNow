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
import AVFoundation
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

    #if DEBUG
        /// A temporary presentation choice that grants no account or generation permissions.
        private var isPreviewingHome = false

        /// Opens the development home preview for this controller's lifetime.
        func previewHome() { isPreviewingHome = true }

        /// Restores the login page when leaving the temporary preview or completing sign-in.
        func endHomePreview() { isPreviewingHome = false }
    #endif

    /// Whether account authentication should cover the mounted home content.
    var needsLogin: Bool {
        #if DEBUG
            !isPreviewingHome && !userRepo.canAccessHome
        #else
            !userRepo.canAccessHome
        #endif
    }

    /// Whether installation readiness and account operations permit the Start action.
    var canStart: Bool {
        userRepo.canAccessHome && virtualCameraRepo.canStartSession && !userRepo.isBusy && !userRepo.isLoadingKeys
            && AVCaptureDevice.authorizationStatus(for: .video) == .authorized && !generationRepo.cameras.isEmpty
    }

    /// Whether generation startup should display the landing-page progress state.
    var isStarting: Bool { generationRepo.isBusy && !generationRepo.isClosing }

    /// Whether the API-key editor must preserve the active generation credential.
    var settingsLocked: Bool { generationRepo.settingsLocked || generationRepo.isClosing }

    /// The current startup restriction displayed by the landing page.
    var startUnavailableMessage: String {
        guard userRepo.canAccessHome else { return "Sign in before starting the camera." }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return "Allow camera access in the setup guide before starting."
        }
        if virtualCameraRepo.canStartSession, generationRepo.cameras.isEmpty {
            return "Connect a camera, then check again in the setup guide."
        }
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
        #if DEBUG
            endHomePreview()
        #endif
        await generationRepo.close()
        do {
            try await userRepo.signOut()
        } catch { generationRepo.showSetupError(error.localizedDescription) }
    }
}
