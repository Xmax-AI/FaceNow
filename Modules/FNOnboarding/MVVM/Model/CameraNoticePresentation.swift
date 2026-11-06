//
//  CameraNoticePresentation.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// Allows contextual navigation labels while preserving the same state and command definitions.
enum CameraNoticeSurface: Equatable {

    /// A compact notice may direct the user into focused guidance.
    case banner

    /// The guide already explains the issue and can offer its next concrete system action.
    case onboarding
}

/// Identifies the system pane an explicit settings action should open.
enum CameraSettingsDestination: Equatable {

    /// The camera privacy permission pane.
    case cameraPrivacy

    /// The system camera-extension configuration pane.
    case cameraExtensions
}

/// Selects focused guidance without deriving navigation from displayed text.
enum CameraHelpTopic: Equatable {

    /// Covers camera permission and physical-input preparation.
    case cameraAccess

    /// Covers extension installation, approval, and virtual-device recovery.
    case virtualCamera

    /// Explains restrictions enforced by macOS or a device administrator.
    case restrictedCameraAccess
}

/// Connects each notice button to a typed command rather than its English title.
enum CameraNoticeAction: Equatable {

    /// Requests the initial camera permission prompt.
    case requestCameraAccess

    /// Opens a specific system settings destination.
    case openSettings(CameraSettingsDestination)

    /// Opens the current list of physical cameras.
    case chooseCamera

    /// Installs the bundled camera extension.
    case installVirtualCamera

    /// Removes an obsolete extension before installing the bundled version.
    case reinstallVirtualCamera

    /// Repeats the exact failed or incomplete operation.
    case retry(CameraOperation)

    /// Rechecks a known unavailable device without repeating installation.
    case checkAgain(CameraOperation)

    /// Presents help at the relevant preparation step.
    case showHelp(CameraHelpTopic)

    /// Reveals the current application bundle for relocation.
    case revealApplication

    /// Requests orderly application cleanup and relaunch.
    case restartApplication

    /// Copies structured setup details for a failure that cannot be solved by repeating a request.
    case copyErrorDetails

    /// The shared label corresponding to the command's actual effect.
    var title: String {
        switch self {
        case .requestCameraAccess: OnboardingStrings.noticeAllowCameraAccess
        case .openSettings: OnboardingStrings.noticeOpenSystemSettings
        case .chooseCamera: OnboardingStrings.noticeChooseCamera
        case .installVirtualCamera: OnboardingStrings.install
        case .reinstallVirtualCamera: OnboardingStrings.install
        case .checkAgain: OnboardingStrings.noticeCheckAgain
        case .retry: OnboardingStrings.retry
        case .showHelp: OnboardingStrings.viewAction
        case .revealApplication: OnboardingStrings.noticeShowInFinder
        case .restartApplication: OnboardingStrings.noticeRestartFaceNow
        case .copyErrorDetails: OnboardingStrings.copyErrorDetails
        }
    }

    /// Device commands execute at the repository boundary; other actions are navigation intents.
    var operation: CameraOperation? {
        switch self {
        case .requestCameraAccess: .requestAccess
        case .installVirtualCamera: .install
        case .reinstallVirtualCamera: .reinstall
        case .retry(let operation), .checkAgain(let operation): operation
        default: nil
        }
    }
}

/// The complete value rendered by a camera notice, with no repository or task ownership.
struct CameraNoticePresentation: Equatable {

    /// The concise user-facing explanation without raw system diagnostics.
    let message: String

    /// The single command associated with the displayed notice.
    let action: CameraNoticeAction

    /// Retains the button's progress label during an explicit operation.
    var progressTitle: String? = nil

    /// Whether current business conditions allow the command to execute.
    var isEnabled = true

    /// The button's current accessible title.
    var buttonTitle: String { progressTitle ?? action.title }

    /// Whether an explicit device workflow is still running.
    var isLoading: Bool { progressTitle != nil }

    /// Maps committed state and operation context to one consistent explanation and command.
    static func make(
        readiness: CameraReadiness,
        operation: CameraOperationContext?,
        failure: CameraOperationFailure?,
        actionsLocked: Bool,
        surface: CameraNoticeSurface = .banner,
        installationFailure: CameraOperationFailure? = nil
    ) -> Self? {
        guard var notice = resolve(
            readiness: readiness,
            operation: operation,
            failure: failure,
            actionsLocked: actionsLocked,
            surface: surface
        ) else { return nil }
        if !notice.isLoading,
            notice.action.operation == .install || notice.action.operation == .reinstall,
            let installationFailure
        {
            notice = failed(installationFailure)
        }
        guard surface == .banner else { return notice }
        return Self(
            message: notice.message,
            action: .showHelp(guideTopic(for: notice, readiness: readiness, failure: failure))
        )
    }

    /// Keeps device commands and their progress inside the guide while retaining shared state copy.
    private static func resolve(
        readiness: CameraReadiness,
        operation: CameraOperationContext?,
        failure: CameraOperationFailure?,
        actionsLocked: Bool,
        surface: CameraNoticeSurface
    ) -> Self? {
        if operation == nil, readiness.isCameraAuthorized, let failure,
            failure.kind == .invalidLocation || failure.kind == .invalidBundle || failure.operation == .checkStatus
        {
            var result = failed(failure)
            result.isEnabled = !actionsLocked || result.action.operation == nil
            return result
        }
        if let operation, operation.origin == .user {
            switch readiness {
            case .permissionRequired(.denied), .permissionRequired(.restricted),
                .unavailable(.approvalRequired), .unavailable(.installationIncomplete), .unavailable(.installationLocation):
                break
            default:
                return progress(operation.kind)
            }
        }
        if let failure {
            switch readiness {
            case .ready, .checking, .unavailable(.operationFailed), .unavailable(.versionMismatch),
                .unavailable(.virtualCameraNotInstalled), .unavailable(.virtualCameraDisabled),
                .unavailable(.devicePublicationTimedOut):
                var result = failed(failure)
                result.isEnabled = !actionsLocked || result.action.operation == nil
                return result
            default:
                break
            }
        }
        var result: Self
        switch readiness {
        case .checking, .ready:
            return nil
        case .permissionRequired(.notRequested):
            result = Self(message: OnboardingStrings.noticeFaceNowNeedsAccessToYourCamera, action: .requestCameraAccess)
        case .permissionRequired(.denied):
            result = Self(
                message: OnboardingStrings.noticeCameraAccessIsOffForFaceNow,
                action: .openSettings(.cameraPrivacy)
            )
        case .permissionRequired(.restricted):
            result = Self(
                message: OnboardingStrings.noticeCameraAccessIsRestrictedByMacOSOrYourDevice,
                action: surface == .onboarding ? .openSettings(.cameraPrivacy) : .showHelp(.restrictedCameraAccess)
            )
        case .unavailable(let reason):
            switch reason {
            case .noInputCamera:
                result = Self(
                    message: OnboardingStrings.noticeNoCameraDetectedConnectACameraToContinue,
                    action: .checkAgain(.discoverInput)
                )
            case .selectedInputDisconnected:
                result = Self(
                    message: OnboardingStrings.noticeYourSelectedCameraIsDisconnected,
                    action: surface == .onboarding ? .checkAgain(.discoverInput) : .chooseCamera
                )
            case .virtualCameraNotInstalled:
                result = Self(
                    message: OnboardingStrings.noticeInstallVirtualCameraToUseFaceNowInVideoCalls,
                    action: .installVirtualCamera
                )
            case .virtualCameraDisabled:
                result = Self(
                    message: OnboardingStrings.noticeVirtualCameraIsTurnedOff,
                    action: .openSettings(.cameraExtensions)
                )
            case .versionMismatch:
                result = Self(
                    message: OnboardingStrings.noticeReinstallVirtualCamera,
                    action: .reinstallVirtualCamera
                )
            case .approvalRequired:
                result = Self(
                    message: OnboardingStrings.noticeAllowTheFaceNowCameraExtensionInSystemSettings,
                    action: .openSettings(.cameraExtensions)
                )
            case .installationIncomplete:
                result = Self(
                    message: OnboardingStrings.noticeInstallationIncomplete,
                    action: .installVirtualCamera
                )
            case .devicePublicationTimedOut:
                result = Self(
                    message: OnboardingStrings.noticeVirtualCameraNotPublished,
                    action: .openSettings(.cameraExtensions)
                )
            case .reopenApplication:
                result = Self(
                    message: OnboardingStrings.noticeRestartFaceNowToRefreshTheCameraConnection,
                    action: .restartApplication
                )
            case .installationLocation:
                result = Self(
                    message: OnboardingStrings.noticeMoveFaceNowToApplicationsToSetUpVirtualCamera,
                    action: .revealApplication
                )
            case .operationFailed(let failure):
                result = failed(failure)
            case .activationRequired:
                guard surface == .onboarding else { return nil }
                result = Self(message: OnboardingStrings.activateCamera, action: .reinstallVirtualCamera)
            }
        }
        if actionsLocked, result.action.operation != nil || result.action == .chooseCamera {
            result.isEnabled = false
        }
        return result
    }

    /// Opens the stage that owns the rendered issue, including failures on an otherwise-ready device.
    private static func guideTopic(
        for notice: Self,
        readiness: CameraReadiness,
        failure: CameraOperationFailure?
    ) -> CameraHelpTopic {
        if let operation = notice.action.operation {
            return operation.belongs(to: .cameraInput) ? .cameraAccess : .virtualCamera
        }
        switch notice.action {
        case .openSettings(.cameraPrivacy), .chooseCamera:
            return .cameraAccess
        case .showHelp(let topic):
            return topic
        case .copyErrorDetails:
            if case .unavailable(.operationFailed(let embedded)) = readiness {
                return embedded.operation.belongs(to: .cameraInput) ? .cameraAccess : .virtualCamera
            }
            return failure?.operation.belongs(to: .cameraInput) == true ? .cameraAccess : .virtualCamera
        default:
            return .virtualCamera
        }
    }

    /// Presents an explicit operation without erasing its underlying readiness facts.
    private static func progress(
        _ operation: CameraOperation
    ) -> Self {
        let title: String
        let message: String
        switch operation {
        case .requestAccess:
            title = OnboardingStrings.noticeWaiting
            message = OnboardingStrings.noticeAllowCameraAccessInTheMacOSPermissionDialog
        case .install:
            title = OnboardingStrings.noticeInstalling
            message = OnboardingStrings.noticeInstallingVirtualCamera
        case .reinstall:
            title = OnboardingStrings.reinstalling
            message = OnboardingStrings.noticeReinstallingVirtualCamera
        case .remove:
            title = OnboardingStrings.noticeRemoving
            message = OnboardingStrings.noticeRemovingVirtualCamera
        case .discoverInput:
            title = OnboardingStrings.noticeChecking
            message = OnboardingStrings.noticeCheckingAvailableCameras
        case .discoverOutput:
            title = OnboardingStrings.noticeChecking
            message = OnboardingStrings.noticeCheckingTheVirtualCameraConnection
        case .checkStatus:
            title = OnboardingStrings.noticeChecking
            message = OnboardingStrings.noticeCheckingVirtualCameraStatus
        }
        return Self(message: message, action: .retry(operation), progressTitle: title, isEnabled: false)
    }

    /// Keeps retry commands and fallback copy attached to structured failures.
    private static func failed(
        _ failure: CameraOperationFailure
    ) -> Self {
        switch failure.kind {
        case .missingExtensionRecord:
            return Self(message: OnboardingStrings.noticeManualRemoval, action: .openSettings(.cameraExtensions))
        case .authorization:
            let action: CameraNoticeAction =
                failure.operation == .install
                ? .installVirtualCamera : .openSettings(.cameraExtensions)
            return Self(message: OnboardingStrings.noticeSetupAuthorizationRequired, action: action)
        case .pendingRequest:
            return Self(
                message: OnboardingStrings.noticeSetupApprovalRequired,
                action: .openSettings(.cameraExtensions)
            )
        case .invalidLocation:
            return Self(
                message: OnboardingStrings.noticeMoveFaceNowToApplicationsToSetUpVirtualCamera,
                action: .revealApplication
            )
        case .invalidBundle:
            return Self(message: OnboardingStrings.noticeInvalidCameraBundle, action: .copyErrorDetails)
        case .systemPolicy:
            return Self(message: OnboardingStrings.noticeCameraBlockedByPolicy, action: .copyErrorDetails)
        case .recoveryExhausted:
            return Self(message: OnboardingStrings.noticeCameraRecoveryExhausted, action: .copyErrorDetails)
        case .cancelled, .interrupted:
            let action: CameraNoticeAction
            switch failure.operation {
            case .install: action = .installVirtualCamera
            case .reinstall: action = .reinstallVirtualCamera
            case .remove: action = .openSettings(.cameraExtensions)
            default: action = .checkAgain(failure.operation)
            }
            return Self(message: OnboardingStrings.noticeSetupInterrupted, action: action)
        case .system:
            if failure.operation == .checkStatus {
                return Self(message: OnboardingStrings.noticeCameraStatusCheckFailed, action: .checkAgain(.checkStatus))
            }
            if failure.operation == .remove {
                return Self(message: OnboardingStrings.noticeManualRemoval, action: .openSettings(.cameraExtensions))
            }
            return Self(message: OnboardingStrings.noticeSetupFailedWithDetails, action: .copyErrorDetails)
        }
    }
}
