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
    var authorization: AVAuthorizationStatus { virtualCameraRepo.cameraAuthorization }

    /// Distinguishes a newly granted system permission from an already-authorized review entry.
    private var previousAuthorization = AVCaptureDevice.authorizationStatus(for: .video)

    /// Whether the system camera permission prompt is awaiting an answer.
    var isRequestingAccess: Bool { virtualCameraRepo.isRequestingCameraAccess }

    /// Whether camera access requires an explicit settings change instead of another prompt.
    var needsCameraSettings: Bool { authorization == .denied || authorization == .restricted }

    /// Distinguishes administrator or system restrictions from a user-denied permission.
    var isCameraRestricted: Bool { authorization == .restricted }

    /// Names the camera help step without suggesting that policy restrictions can be granted in-app.
    var cameraStepTitle: String {
        isCameraRestricted ? OnboardingStrings.guideCameraAccessIsRestricted : OnboardingStrings.noticeAllowCameraAccess
    }

    /// Supplies focused help for restrictions while retaining the normal camera introduction.
    var cameraStepDescription: String {
        isCameraRestricted
            ? OnboardingStrings.guideReviewTheCameraRestrictionsOnThisMacBeforeContinuing
            : OnboardingStrings.guideFaceNowTurnsYourMovementsIntoYourChosenLookIn
    }

    /// Reuses the notice mapper instead of maintaining another action/state switch.
    private lazy var cameraStatusModel: CameraStatusViewModel = {
        CameraStatusViewModel()
    }()

    /// The camera stage does not depend on installation of the virtual output.
    var cameraReady: Bool { virtualCameraRepo.readiness(for: .cameraInput).isReady }

    /// The output stage reflects extension readiness independently of physical camera access.
    var virtualCameraReady: Bool { virtualCameraRepo.readiness(for: .virtualOutput).isReady }

    /// Limits progress and failures to the subsystem explained by the current step.
    private var preparationScope: CameraPreparationScope {
        switch onboardingRepo.step {
        case .camera: .cameraInput
        case .virtualCamera: .virtualOutput
        case .videoCalls: .complete
        }
    }

    /// Uses the same wording, commands, and operation progress as the home notice.
    var cameraNotice: CameraNoticePresentation? {
        cameraStatusModel.presentation(for: preparationScope, surface: .onboarding)
    }

    /// Describes guide navigation separately from shared device and system commands.
    enum PrimaryAction: Equatable {
        case advance
        case complete
        case camera(CameraNoticeAction)
    }

    /// Keeps the primary button's title, command, enablement, and spinner consistent.
    struct PrimaryPresentation {
        let title: String
        let action: PrimaryAction?
        var isEnabled = true
        var isLoading = false
    }

    /// Derives one primary action from shared camera facts and the current guide stage.
    var primaryPresentation: PrimaryPresentation {
        if onboardingRepo.step == .videoCalls {
            return PrimaryPresentation(
                title: OnboardingStrings.guideDoneLetSGetStarted,
                action: .complete,
                isEnabled: virtualCameraRepo.readiness.isReady
            )
        }
        if let notice = cameraNotice {
            return PrimaryPresentation(
                title: notice.buttonTitle,
                action: .camera(notice.action),
                isEnabled: notice.isEnabled,
                isLoading: notice.isLoading
            )
        }
        if virtualCameraRepo.readiness(for: preparationScope).isReady {
            return PrimaryPresentation(title: OnboardingStrings.continueAction, action: .advance)
        }
        return PrimaryPresentation(
            title: OnboardingStrings.noticeChecking,
            action: nil,
            isEnabled: false,
            isLoading: true
        )
    }

    /// Exposes primary control values without duplicating their state derivation.
    var primaryTitle: String { primaryPresentation.title }
    var primaryEnabled: Bool { primaryPresentation.isEnabled && !primaryPresentation.isLoading }
    var primaryLoading: Bool { primaryPresentation.isLoading }

    /// A numbered instruction rendered by the guide without interpreting repository flags.
    struct Instruction {
        let title: String
        let detail: String
    }

    /// Keeps supporting instructions aligned with the exact command shown in the footer.
    var preparationInstructions: [Instruction] {
        let notice = cameraNotice
        if onboardingRepo.step == .camera {
            if cameraReady, notice == nil {
                return [.init(title: OnboardingStrings.continueAction, detail: OnboardingStrings.cameraStepReady)]
            }
            if let notice,
                notice.isLoading
                    || (notice.action != .requestCameraAccess && notice.action != .openSettings(.cameraPrivacy))
            {
                return [.init(title: notice.buttonTitle, detail: notice.message)]
            }
            if isCameraRestricted {
                return [
                    .init(
                        title: OnboardingStrings.guideReviewCameraRestrictions,
                        detail: OnboardingStrings.guideCameraAccessIsRestrictedByMacOSOrADevice
                    ),
                    .init(
                        title: OnboardingStrings.guideAskYourAdministrator,
                        detail: OnboardingStrings.guideIfThisMacIsManagedAskYourAdministratorTo
                    ),
                ]
            }
            if needsCameraSettings {
                return [
                    .init(
                        title: OnboardingStrings.noticeOpenSystemSettings,
                        detail: OnboardingStrings.guideClickOpenSystemSettingsInTheBottomRightCorner
                    ),
                    .init(
                        title: OnboardingStrings.guideAllowFaceNow,
                        detail: OnboardingStrings.guideTurnOnTheSwitchNextToFaceNowUnderPrivacy
                    ),
                ]
            }
            return [
                .init(
                    title: OnboardingStrings.guideRequestCameraAccess,
                    detail: OnboardingStrings.guideClickAllowCameraAccessInTheBottomRightCorner
                ),
                .init(
                    title: OnboardingStrings.guideAllowFaceNow,
                    detail: OnboardingStrings.guideChooseAllowInTheMacOSPermissionDialog
                ),
            ]
        }
        guard onboardingRepo.step == .virtualCamera else { return [] }
        guard let notice else {
            return [
                .init(
                    title: primaryTitle,
                    detail: virtualCameraReady
                        ? OnboardingStrings.virtualCameraStepReady : OnboardingStrings.noticeCheckingVirtualCameraStatus
                )
            ]
        }
        guard !notice.isLoading else {
            return [.init(title: notice.buttonTitle, detail: notice.message)]
        }
        let enableInstruction: String
        if #available(macOS 15, *) {
            enableInstruction = OnboardingStrings.guideTurnOnTheSwitchNextToFaceNowUnderLogin
        } else {
            enableInstruction = OnboardingStrings.guideAllowTheFaceNowSystemExtensionUnderPrivacySecurityThen
        }
        let settingsInstructions: [Instruction] = [
            .init(
                title: OnboardingStrings.noticeOpenSystemSettings,
                detail: OnboardingStrings.guideClickOpenSystemSettingsInTheBottomRightCorner
            ),
            .init(title: OnboardingStrings.guideEnableFaceNow, detail: enableInstruction),
        ]
        switch notice.action {
        case .installVirtualCamera, .updateVirtualCamera:
            return [
                .init(
                    title: notice.action == .installVirtualCamera
                        ? OnboardingStrings.guideInstallVirtualCamera : OnboardingStrings.guideUpdateVirtualCamera,
                    detail: OnboardingStrings.clickPrimaryButton(notice.buttonTitle)
                )
            ] + settingsInstructions
        case .openSettings(.cameraExtensions):
            return settingsInstructions
        default:
            return [.init(title: notice.buttonTitle, detail: notice.message)]
        }
    }

    /// Reads current permission and shared device state without installing or opening capture.
    func synchronize() {
        virtualCameraRepo.synchronizeReadiness()
        let currentAuthorization = authorization
        let cameraAccessJustGranted = previousAuthorization != .authorized && currentAuthorization == .authorized
        previousAuthorization = currentAuthorization
        onboardingRepo.updateReadiness(
            camera: cameraReady,
            virtualCamera: virtualCameraReady,
            cameraAccessJustGranted: cameraAccessJustGranted
        )
    }

    /// Rechecks requirements after returning from settings or requesting a retry.
    func refresh() {
        generationRepo.refreshCameras()
        synchronize()
        virtualCameraRepo.refresh(retryDeviceDiscovery: true)
    }

    /// Executes shared commands and returns system navigation to the modal's coordinator.
    func performPrimaryAction() async -> CameraNoticeAction? {
        let requestedStep = onboardingRepo.step
        let requestedAction = primaryPresentation.action
        synchronize()
        guard onboardingRepo.isPresented, onboardingRepo.step == requestedStep, primaryEnabled,
            let action = requestedAction, primaryPresentation.action == action
        else { return nil }
        switch action {
        case .advance:
            onboardingRepo.advance()
        case .complete:
            onboardingRepo.complete()
        case .camera(let command):
            let navigation = await cameraStatusModel.perform(
                command,
                scope: preparationScope,
                surface: .onboarding
            )
            guard !Task.isCancelled, onboardingRepo.isPresented else { return nil }
            synchronize()
            return navigation
        }
        return nil
    }

    /// Opens the camera privacy pane without attempting to modify system authorization.
    func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}
