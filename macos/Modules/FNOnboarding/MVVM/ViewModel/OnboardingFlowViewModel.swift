//
//  OnboardingFlowViewModel.swift
//  FaceNow
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

    /// The shared owner of generated-audio device installation and explicit output intent.
    @Injected(\.virtualMicrophoneRepo) var virtualMicrophoneRepo: VirtualMicrophoneRepository

    /// The last permission check, refreshed when the application regains focus.
    var authorization: AVAuthorizationStatus { virtualCameraRepo.cameraAuthorization }

    /// Distinguishes a newly granted system permission from an already-authorized review entry.
    private var previousAuthorization = AVCaptureDevice.authorizationStatus(for: .video)

    /// Distinguishes a new microphone grant from an already-authorized review entry.
    private var previousMicrophoneAuthorization = AVCaptureDevice.authorizationStatus(for: .audio)

    /// Whether this guide is awaiting the shared system microphone permission request.
    @Published private(set) var isRequestingMicrophoneAccess = false

    /// The shared physical microphone permission, refreshed without starting capture.
    var microphoneAuthorization: AVAuthorizationStatus { generationRepo.microphoneAuthorization }

    /// Whether microphone access requires a change in System Settings.
    var needsMicrophoneSettings: Bool {
        microphoneAuthorization == .denied || microphoneAuthorization == .restricted
    }

    /// The microphone introduction or the system restriction that prevents authorization.
    var microphoneStepTitle: String {
        microphoneAuthorization == .restricted
            ? OnboardingStrings.microphoneRestrictedTitle : OnboardingStrings.allowMicrophoneAccess
    }

    /// Explains optional voice input without starting capture during setup.
    var microphoneStepDescription: String {
        microphoneAuthorization == .restricted
            ? OnboardingStrings.microphoneRestrictedDetail : OnboardingStrings.microphoneIntroduction
    }

    /// Gives permission instructions appropriate to the current system authorization.
    private var microphonePermissionDetail: String {
        if microphoneAuthorization == .restricted { return OnboardingStrings.microphoneRestrictedDetail }
        return needsMicrophoneSettings
            ? OnboardingStrings.microphoneSettingsDetail : OnboardingStrings.microphoneRequestDetail
    }

    /// Offers deferral for either optional audio stage without closing the guide.
    var showsAudioSkip: Bool {
        switch onboardingRepo.step {
        case .microphone: !onboardingRepo.microphoneReady
        case .virtualMicrophone: !virtualMicrophoneReady
        default: false
        }
    }

    /// Prevents skipping while permission or input configuration is still being applied.
    var canSkipAudio: Bool {
        guard showsAudioSkip else { return false }
        return !isRequestingMicrophoneAccess && generationRepo.canChangeMicrophone
    }

    /// Requires a published, enabled device; an installed bundle alone is not sufficient.
    var virtualMicrophoneReady: Bool { virtualMicrophoneRepo.status == .enabled }

    /// Explains the next explicit audio-output action using the existing device module's state.
    var virtualMicrophoneExplanation: String {
        if virtualMicrophoneRepo.deviceCheckState == .checking {
            return OnboardingStrings.virtualMicrophoneCheckingDetail
        }
        if virtualMicrophoneRepo.deviceCheckState == .timedOut, !virtualMicrophoneRepo.deviceAvailable {
            return OnboardingStrings.virtualMicrophoneCheckTimedOutDetail
        }
        let checked = virtualMicrophoneRepo.deviceCheckState == .completed
        switch virtualMicrophoneRepo.status {
        case .notInstalled:
            return checked
                ? OnboardingStrings.virtualMicrophoneCheckedNotInstalledDetail
                : OnboardingStrings.virtualMicrophoneInstallDetail
        case .pending:
            return checked
                ? OnboardingStrings.virtualMicrophoneCheckedPendingDetail
                : OnboardingStrings.virtualMicrophonePendingDetail
        case .disabled:
            return OnboardingStrings.virtualMicrophoneEnableDetail(
                microphone: VirtualMicrophoneConfiguration.deviceName
            )
        case .enabled: return OnboardingStrings.virtualMicrophoneStepReady
        case .failed: return virtualMicrophoneRepo.failure ?? VirtualMicrophoneStrings.failed
        }
    }

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

    /// Distinguishes a publication timeout from an extension that merely needs initial approval.
    var needsVirtualCameraRecovery: Bool {
        virtualCameraRepo.readiness(for: .virtualOutput) == .unavailable(.devicePublicationTimedOut)
    }

    /// Identifies only the illustrations relevant to the current preparation action.
    enum VirtualCameraGuidePage: Equatable {
        case explanation
        case permissionPrompt
        case settings
        case recoverySettings
    }

    /// Ready, waiting, and non-settings states have one explanation and no image pagination.
    var virtualCameraGuidePages: [VirtualCameraGuidePage] {
        guard let notice = cameraNotice, !notice.isLoading else { return [.explanation] }
        switch notice.action {
        case .installVirtualCamera, .reinstallVirtualCamera:
            return [.explanation, .permissionPrompt, .settings]
        case .openSettings(.cameraExtensions):
            if virtualCameraRepo.needsManualRemoval { return [.explanation] }
            return needsVirtualCameraRecovery
                ? [.explanation, .recoverySettings]
                : [.explanation, .settings]
        default:
            return [.explanation]
        }
    }

    /// The output stage reflects extension readiness independently of physical camera access.
    var virtualCameraReady: Bool { virtualCameraRepo.readiness(for: .virtualOutput).isReady }

    /// Names local installation blockers before presenting extension setup actions.
    var virtualCameraStepTitle: String {
        if cameraNotice?.action == .revealApplication { return OnboardingStrings.moveApplicationTitle }
        if hasInvalidCameraBundle { return OnboardingStrings.reinstallApplicationTitle }
        return OnboardingStrings.guideEnableVirtualCamera
    }

    /// Keeps installation guidance tied to structured failures rather than translated titles.
    private var hasInvalidCameraBundle: Bool {
        cameraNotice?.action == .copyErrorDetails
            && (virtualCameraRepo.preparationFailure?.kind == .invalidBundle
                || virtualCameraRepo.installationPreflightFailure?.kind == .invalidBundle)
    }

    /// Explains actionable local blockers without suggesting an installation can proceed yet.
    var virtualCameraStepDescription: String {
        if cameraNotice?.action == .revealApplication || hasInvalidCameraBundle {
            return cameraNotice?.message ?? OnboardingStrings.noticeInvalidCameraBundle
        }
        return OnboardingStrings.guideFaceNowUsesAVirtualCameraToBringYourChosen
    }

    /// Limits progress and failures to the subsystem explained by the current step.
    private var preparationScope: CameraPreparationScope {
        switch onboardingRepo.step {
        case .camera, .microphone, .virtualMicrophone: .cameraInput
        case .virtualCamera: .virtualOutput
        case .videoCalls: .complete
        }
    }

    /// Uses the same wording, commands, and operation progress as the home notice.
    var cameraNotice: CameraNoticePresentation? {
        guard onboardingRepo.step != .microphone, onboardingRepo.step != .virtualMicrophone else { return nil }
        return cameraStatusModel.presentation(for: preparationScope, surface: .onboarding)
    }

    /// Describes guide navigation separately from shared device and system commands.
    enum PrimaryAction: Equatable {
        case advance
        case complete
        case camera(CameraNoticeAction)
        case requestMicrophoneAccess
        case microphoneSettings
        case skipAudio
        case installVirtualMicrophone
        case enableVirtualMicrophone
        case checkVirtualMicrophone
    }

    /// Routes native settings navigation back to the home coordinator.
    enum Navigation {
        case camera(CameraNoticeAction)
        case microphoneSettings
    }

    /// Keeps the primary button's title, command, enablement, and spinner consistent.
    struct PrimaryPresentation {

        /// The title shown on the primary button.
        let title: String

        /// The command available at the current step.
        let action: PrimaryAction?

        /// Whether the step permits the command.
        var isEnabled = true

        /// Whether the button shows an operation in progress.
        var isLoading = false

        /// Whether the primary button can accept a new action.
        var canPerform: Bool { isEnabled && !isLoading }
    }

    /// Derives one primary action from shared camera facts and the current guide stage.
    var primaryPresentation: PrimaryPresentation {
        if onboardingRepo.step == .virtualMicrophone {
            if virtualMicrophoneRepo.deviceCheckState == .checking {
                return PrimaryPresentation(
                    title: OnboardingStrings.noticeChecking,
                    action: nil,
                    isEnabled: false,
                    isLoading: true
                )
            }
            if virtualMicrophoneReady {
                return PrimaryPresentation(title: OnboardingStrings.continueAction, action: .advance)
            }
            if virtualMicrophoneRepo.deviceAvailable {
                return PrimaryPresentation(title: VirtualMicrophoneStrings.enable, action: .enableVirtualMicrophone)
            }
            if virtualMicrophoneRepo.driverInstalled {
                return PrimaryPresentation(title: VirtualMicrophoneStrings.checkAgain, action: .checkVirtualMicrophone)
            }
            return PrimaryPresentation(title: VirtualMicrophoneStrings.install, action: .installVirtualMicrophone)
        }
        if onboardingRepo.step == .microphone {
            if isRequestingMicrophoneAccess {
                return PrimaryPresentation(
                    title: OnboardingStrings.noticeWaiting,
                    action: nil,
                    isEnabled: false,
                    isLoading: true
                )
            }
            if onboardingRepo.microphoneReady {
                return PrimaryPresentation(title: OnboardingStrings.continueAction, action: .advance)
            }
            return PrimaryPresentation(
                title: needsMicrophoneSettings
                    ? OnboardingStrings.noticeOpenSystemSettings : OnboardingStrings.allowMicrophoneAccess,
                action: needsMicrophoneSettings ? .microphoneSettings : .requestMicrophoneAccess
            )
        }
        if onboardingRepo.step == .videoCalls {
            return PrimaryPresentation(
                title: OnboardingStrings.finishSetup,
                action: .complete,
                isEnabled: onboardingRepo.firstIncompleteStep == .videoCalls
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

    /// A numbered instruction rendered by the guide without interpreting repository flags.
    struct Instruction {

        /// The action or milestone displayed in the timeline.
        let title: String

        /// The supporting instruction or current status.
        let detail: String
    }

    /// Explains the shared workflow without making the user pick an application inside setup.
    var videoCallInstructions: [Instruction] {
        var instructions: [Instruction] = [
            .init(
                title: OnboardingStrings.guideStartYourCamera,
                detail: OnboardingStrings.guideReturnToFaceNowClickStartCameraAndChooseYour
            ),
            .init(
                title: OnboardingStrings.videoCallsSelectTitle,
                detail: OnboardingStrings.videoCallsChooseCamera(camera: VirtualCameraConfiguration.deviceName)
            ),
        ]
        if virtualMicrophoneReady {
            instructions.append(
                .init(
                    title: OnboardingStrings.videoCallsMicrophoneTitle,
                    detail: OnboardingStrings.videoCallsMicrophoneDetail(
                        microphone: VirtualMicrophoneConfiguration.deviceName
                    )
                )
            )
        }
        instructions.append(
            .init(
                title: OnboardingStrings.videoCallsKeepRunningTitle,
                detail: OnboardingStrings.videoCallsKeepRunningDetail
            )
        )
        return instructions
    }

    /// Replaces setup illustrations once the current device requirement is satisfied.
    var isPreparationComplete: Bool {
        switch onboardingRepo.step {
        case .microphone: onboardingRepo.microphoneReady
        case .virtualMicrophone: virtualMicrophoneReady
        case .camera: cameraReady
        case .virtualCamera: virtualCameraReady
        case .videoCalls: false
        }
    }

    /// Keeps supporting instructions aligned with the exact command shown in the footer.
    var preparationInstructions: [Instruction] {
        if onboardingRepo.step == .virtualMicrophone {
            if virtualMicrophoneReady {
                return [.init(title: OnboardingStrings.continueAction, detail: virtualMicrophoneExplanation)]
            }
            return [
                .init(title: primaryPresentation.title, detail: virtualMicrophoneExplanation)
            ]
        }
        if onboardingRepo.step == .microphone {
            if onboardingRepo.microphoneReady {
                return [.init(title: OnboardingStrings.continueAction, detail: OnboardingStrings.microphoneStepReady)]
            }
            return [
                .init(
                    title: needsMicrophoneSettings
                        ? OnboardingStrings.noticeOpenSystemSettings : OnboardingStrings.allowMicrophoneAccess,
                    detail: microphonePermissionDetail
                )
            ]
        }
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
                    title: primaryPresentation.title,
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
        case .installVirtualCamera, .reinstallVirtualCamera:
            return [
                .init(
                    title: OnboardingStrings.guideInstallVirtualCamera,
                    detail: OnboardingStrings.clickPrimaryButton(notice.buttonTitle)
                )
            ] + settingsInstructions
        case .openSettings(.cameraExtensions):
            if virtualCameraRepo.needsManualRemoval {
                return [
                    .init(
                        title: OnboardingStrings.noticeOpenSystemSettings,
                        detail: OnboardingStrings.guideExplanationManualRemoval
                    )
                ]
            }
            if needsVirtualCameraRecovery {
                return [
                    settingsInstructions[0],
                    .init(
                        title: OnboardingStrings.guideRestartVirtualCamera,
                        detail: OnboardingStrings.guideToggleVirtualCamera
                    ),
                ]
            }
            return settingsInstructions
        default:
            return [.init(title: notice.buttonTitle, detail: notice.message)]
        }
    }

    /// Explains the current facts and next action wherever no setup screenshot is available.
    var preparationExplanation: String {
        if onboardingRepo.step == .virtualMicrophone { return virtualMicrophoneExplanation }
        if onboardingRepo.step == .microphone {
            if onboardingRepo.microphoneReady { return OnboardingStrings.microphoneStepReady }
            return microphonePermissionDetail
        }
        guard let notice = cameraNotice else {
            if virtualCameraRepo.readiness(for: preparationScope).isReady {
                return onboardingRepo.step == .camera
                    ? OnboardingStrings.cameraStepReady : OnboardingStrings.virtualCameraStepReady
            }
            return OnboardingStrings.guideExplanationChecking
        }
        let nextStep: String
        if notice.isLoading {
            nextStep =
                notice.action == .retry(.requestAccess)
                ? OnboardingStrings.guideChooseAllowInTheMacOSPermissionDialog
                : OnboardingStrings.guideExplanationWaiting
        } else {
            switch notice.action {
            case .installVirtualCamera:
                nextStep = OnboardingStrings.guideExplanationInstall(action: notice.buttonTitle)
            case .reinstallVirtualCamera:
                nextStep = OnboardingStrings.guideExplanationReinstall
            case .openSettings(.cameraExtensions):
                if virtualCameraRepo.needsManualRemoval {
                    nextStep = OnboardingStrings.guideExplanationManualRemoval
                } else {
                    nextStep =
                        needsVirtualCameraRecovery
                        ? OnboardingStrings.guideExplanationPublicationRecovery
                        : OnboardingStrings.guideExplanationEnableExtension
                }
            case .openSettings(.cameraPrivacy), .showHelp(.restrictedCameraAccess), .showHelp(.cameraAccess):
                nextStep =
                    isCameraRestricted
                    ? OnboardingStrings.guideIfThisMacIsManagedAskYourAdministratorTo
                    : OnboardingStrings.guideTurnOnTheSwitchNextToFaceNowUnderPrivacy
            case .showHelp(.virtualCamera):
                nextStep = OnboardingStrings.guideExplanationEnableExtension
            case .requestCameraAccess:
                nextStep = OnboardingStrings.guideExplanationRequestAccess
            case .chooseCamera, .checkAgain(.discoverInput):
                nextStep = OnboardingStrings.guideExplanationConnectCamera
            case .retry:
                nextStep = OnboardingStrings.guideExplanationRetry(action: notice.buttonTitle)
            case .checkAgain:
                nextStep = OnboardingStrings.guideExplanationCheckAgain
            case .revealApplication:
                nextStep = OnboardingStrings.guideExplanationMoveApplication
            case .restartApplication:
                nextStep = OnboardingStrings.guideExplanationRestartApplication
            case .copyErrorDetails:
                nextStep = OnboardingStrings.guideExplanationContactSupport
            }
        }
        let reason: String
        switch (notice.action, virtualCameraRepo.readiness(for: preparationScope)) {
        case (.installVirtualCamera, .unavailable(.virtualCameraNotInstalled)):
            reason = OnboardingStrings.guideExplanationNotInstalled
        case (.reinstallVirtualCamera, .unavailable(.versionMismatch)):
            reason = OnboardingStrings.guideExplanationVersionMismatch
        default:
            reason = notice.message
        }
        let diagnostics: String
        if !notice.isLoading, let failure = virtualCameraRepo.preparationFailure,
            let domain = failure.errorDomain, let code = failure.errorCode
        {
            diagnostics = "\n\n\(domain) (\(code))"
        } else {
            diagnostics = ""
        }
        return reason + "\n\n" + nextStep + diagnostics
    }

    /// Reads current permission and shared device state without installing or opening capture.
    func synchronize() {
        virtualCameraRepo.synchronizeReadiness()
        generationRepo.synchronizeMicrophoneAuthorization()
        let currentAuthorization = authorization
        let cameraAccessJustGranted = previousAuthorization != .authorized && currentAuthorization == .authorized
        let microphoneAccessJustGranted =
            previousMicrophoneAuthorization != .authorized && microphoneAuthorization == .authorized
        previousAuthorization = currentAuthorization
        previousMicrophoneAuthorization = microphoneAuthorization
        onboardingRepo.updateReadiness(
            camera: cameraReady,
            microphone: microphoneAuthorization == .authorized,
            virtualMicrophone: virtualMicrophoneReady,
            virtualCamera: virtualCameraReady,
            cameraAccessJustGranted: cameraAccessJustGranted,
            microphoneAccessJustGranted: microphoneAccessJustGranted
        )
    }

    /// Rechecks requirements after returning from settings or requesting a retry.
    func refresh() {
        generationRepo.refreshCameras()
        synchronize()
        virtualCameraRepo.refresh(retryDeviceDiscovery: true)
        virtualMicrophoneRepo.refreshDeviceAvailability()
    }

    /// Executes shared commands and returns system navigation to the modal's coordinator.
    func performPrimaryAction(
        skippingAudio: Bool = false
    ) async -> Navigation? {
        let requestedStep = onboardingRepo.step
        let requestedAction: PrimaryAction? =
            skippingAudio
            ? .skipAudio
            : primaryPresentation.action
        synchronize()
        guard onboardingRepo.isPresented, onboardingRepo.step == requestedStep, let action = requestedAction
        else { return nil }
        if skippingAudio {
            guard canSkipAudio else { return nil }
        } else {
            let presentation = primaryPresentation
            guard presentation.canPerform, presentation.action == action else { return nil }
        }
        switch action {
        case .advance:
            onboardingRepo.advance()
        case .complete:
            onboardingRepo.complete()
        case .requestMicrophoneAccess:
            isRequestingMicrophoneAccess = true
            defer { isRequestingMicrophoneAccess = false }
            _ = await generationRepo.requestMicrophoneAccess()
            guard !Task.isCancelled, onboardingRepo.isPresented, onboardingRepo.step == requestedStep else {
                return nil
            }
            synchronize()
        case .microphoneSettings:
            return .microphoneSettings
        case .skipAudio:
            await generationRepo.selectMicrophone(GenerationRepository.disabledMicrophoneID)
            guard !Task.isCancelled, onboardingRepo.isPresented, onboardingRepo.step == requestedStep,
                generationRepo.microphoneID == GenerationRepository.disabledMicrophoneID
            else { return nil }
            virtualMicrophoneRepo.setEnabled(false)
            onboardingRepo.skipAudio()
        case .installVirtualMicrophone:
            virtualMicrophoneRepo.clearFailure()
            virtualMicrophoneRepo.installDriver()
        case .enableVirtualMicrophone:
            virtualMicrophoneRepo.clearFailure()
            virtualMicrophoneRepo.setEnabled(true)
            synchronize()
        case .checkVirtualMicrophone:
            virtualMicrophoneRepo.clearFailure()
            virtualMicrophoneRepo.checkDeviceAvailability()
        case .camera(let command):
            let navigation = await cameraStatusModel.perform(
                command,
                scope: preparationScope,
                surface: .onboarding
            )
            guard !Task.isCancelled, onboardingRepo.isPresented else { return nil }
            synchronize()
            return navigation.map(Navigation.camera)
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
