//
//  CameraReadiness.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// Selects a preparation projection without creating another source of device facts.
enum CameraPreparationScope: Equatable, Sendable {

    /// The combined result used by the home page and final preparation completion.
    case complete

    /// Camera permission and any physical input requirements already discovered.
    case cameraInput

    /// Extension installation, approval, version, and producer publication.
    case virtualOutput
}

/// The system camera authorization observed without opening a capture session.
enum CameraAuthorization: Equatable, Sendable {

    /// Camera access has not been requested.
    case notRequested

    /// A user-initiated system permission prompt is pending.
    case requesting

    /// The user denied camera access.
    case denied

    /// System policy restricts camera access.
    case restricted

    /// The application may access video input devices.
    case authorized
}

/// The bounded preparation operation currently preventing a readiness result.
enum CameraCheckPhase: Equatable, Sendable {

    /// The current extension installation is being queried.
    case extensionStatus

    /// The system permission prompt is awaiting an answer.
    case permission

    /// The system is installing or updating the extension.
    case installation

    /// The system is removing the extension.
    case removal

    /// The enabled extension is publishing its producer device.
    case devicePublication

    /// The physical camera list has not been discovered yet.
    case inputDiscovery
}

/// The explicit reason camera authorization is unavailable.
enum CameraPermissionReason: Equatable, Sendable {

    /// The user has not answered a permission request.
    case notRequested

    /// Camera access was denied and requires a settings change.
    case denied

    /// Camera access is restricted by the operating system or device policy.
    case restricted

    /// The actionable explanation shared by the home page and startup feedback.
    var message: String {
        switch self {
        case .notRequested: CameraStrings.statusCameraAccessHasNotBeenAllowedAllowCameraAccess
        case .denied: CameraStrings.statusCameraAccessIsOffEnableFaceNowInSystemSettings
        case .restricted: CameraStrings.statusCameraAccessIsRestrictedByMacOSOrDevicePolicy
        }
    }
}

/// A confirmed device or extension condition that prevents camera startup.
enum CameraUnavailableReason: Equatable, Sendable {

    /// Discovery completed without a physical video input.
    case noInputCamera

    /// The selected physical input is no longer present.
    case selectedInputDisconnected

    /// No extension record is installed.
    case virtualCameraNotInstalled

    /// An installed extension is disabled.
    case virtualCameraDisabled

    /// The enabled extension does not match the bundled build.
    case versionMismatch

    /// The system requires the user's approval before activation can finish.
    case approvalRequired

    /// Installation or removal requires a system restart.
    case restartRequired

    /// The bounded publication check ended without a usable producer device.
    case devicePublicationTimedOut

    /// An independent helper found a device that the host's stale list cannot see.
    case reopenApplication

    /// The application must be moved before extension installation is allowed.
    case installationLocation

    /// A failed operation retains its typed retry target and original diagnostics.
    case operationFailed(CameraOperationFailure)

    /// An opt-in diagnostic is deferring publication until explicit activation.
    case activationRequired

    /// The actionable explanation shared by the home page and startup feedback.
    var message: String {
        switch self {
        case .noInputCamera: CameraStrings.statusNoPhysicalCameraWasFoundConnectACameraAnd
        case .selectedInputDisconnected: CameraStrings.statusTheSelectedCameraWasDisconnectedReconnectItOrSelect
        case .virtualCameraNotInstalled: CameraStrings.statusVirtualCameraIsNotInstalledInstallItInSetup
        case .virtualCameraDisabled: CameraStrings.statusVirtualCameraIsDisabledEnableItInSystemSettings
        case .versionMismatch: CameraStrings.statusVirtualCameraNeedsAnUpdateToMatchThisVersion
        case .approvalRequired: CameraStrings.statusApproveTheFaceNowCameraExtensionInSystemSettings
        case .restartRequired: CameraStrings.statusRestartYourMacToFinishVirtualCameraSetup
        case .devicePublicationTimedOut: CameraStrings.statusVirtualCameraDidNotBecomeAvailableInTimeCheck
        case .reopenApplication: CameraStrings.statusMacOSHasRefreshedTheCameraQuitAndReopenFaceNow
        case .installationLocation: CameraStrings.statusMoveFaceNowToApplicationsBeforeInstallingVirtualCamera
        case .operationFailed(let failure): failure.diagnosticMessage
        case .activationRequired: CameraStrings.statusActivateVirtualCameraToFinishSetup
        }
    }
}

/// The readiness of one device subsystem before authorization and input are combined.
enum CameraAvailability: Equatable, Sendable {

    /// A bounded subsystem check is pending.
    case checking(CameraCheckPhase)

    /// A confirmed subsystem condition prevents startup.
    case unavailable(CameraUnavailableReason)

    /// The subsystem satisfies its startup requirements.
    case ready

    /// Whether the subsystem currently satisfies its startup requirements.
    var isReady: Bool { self == .ready }
}

/// The single camera preparation result shared by home, onboarding, and generation.
enum CameraReadiness: Equatable, Sendable {

    /// A bounded check or explicit system operation is in progress.
    case checking(CameraCheckPhase)

    /// Camera permission requires user action.
    case permissionRequired(CameraPermissionReason)

    /// Permission is granted but a device or extension requirement is unmet.
    case unavailable(CameraUnavailableReason)

    /// Camera input and virtual output satisfy preparation requirements, independently of session state.
    case ready

    /// Whether generation may proceed to its own startup validation.
    var isReady: Bool { self == .ready }

    /// Whether permission has passed, independently of pending or unavailable device requirements.
    var isCameraAuthorized: Bool {
        switch self {
        case .permissionRequired, .checking(.permission): false
        case .checking, .unavailable, .ready: true
        }
    }

    /// The persistent home warning, absent during checking and readiness.
    var unavailableMessage: String? {
        switch self {
        case .permissionRequired(let reason): reason.message
        case .unavailable(let reason): reason.message
        case .checking, .ready: nil
        }
    }

    /// The current explanation used when an explicit Start Camera action cannot proceed.
    var message: String {
        if let unavailableMessage { return unavailableMessage }
        switch self {
        case .checking(.permission): return CameraStrings.statusWaitingForCameraPermissionPleaseAnswerTheSystemPrompt
        case .checking(.installation): return CameraStrings.statusVirtualCameraIsBeingInstalledPleaseWait
        case .checking(.removal): return CameraStrings.statusVirtualCameraIsBeingRemovedPleaseWait
        case .checking(.devicePublication):
            return CameraStrings.statusWaitingForVirtualCameraToBecomeAvailablePleaseWait
        case .checking: return CameraStrings.statusCheckingCameraSetupPleaseTryAgainInAMoment
        default: return CameraStrings.statusCameraReady
        }
    }

    /// Resolves prerequisites in order without treating undiscovered input as a missing camera.
    static func resolve(
        authorization: CameraAuthorization,
        virtualCamera: CameraAvailability,
        inputCamera: CameraAvailability
    ) -> CameraReadiness {
        switch authorization {
        case .notRequested: return .permissionRequired(.notRequested)
        case .requesting: return .checking(.permission)
        case .denied: return .permissionRequired(.denied)
        case .restricted: return .permissionRequired(.restricted)
        case .authorized: break
        }
        for availability in [virtualCamera, inputCamera] {
            switch availability {
            case .checking(let phase): return .checking(phase)
            case .unavailable(let reason): return .unavailable(reason)
            case .ready: break
            }
        }
        return .ready
    }
}

/// A committed extension snapshot whose evaluation never treats background refresh as device loss.
struct VirtualCameraReadinessSnapshot {

    /// Whether the system has returned installation records at least once.
    var hasChecked = false

    /// Whether an installed record exists, including a disabled copy.
    var isInstalled = false

    /// Whether a non-removing extension record is enabled.
    var isEnabled = false

    /// Whether the enabled record matches the bundled version.
    var isVersionCurrent = false

    /// Whether a properties query is pending independently of cached readiness.
    var isRefreshing = false

    /// The explicit activation or deactivation operation, if any.
    var operation: CameraCheckPhase?

    /// Whether the user must approve the pending extension request.
    var isAwaitingApproval = false

    /// Whether the system requires restart before preparation can finish.
    var requiresRestart = false

    /// Whether a producer sink was successfully discovered.
    var isDeviceReady = false

    /// Whether a bounded publication check is pending.
    var isWaitingForDevice = false

    /// The latest confirmed setup or device failure.
    var failure: CameraUnavailableReason?

    /// A properties query failure, used when no installation snapshot is available.
    var queryFailure: CameraOperationFailure?

    /// The extension-only readiness projected from the latest committed facts.
    var availability: CameraAvailability {
        if requiresRestart { return .unavailable(.restartRequired) }
        if isAwaitingApproval { return .unavailable(.approvalRequired) }
        if let operation { return .checking(operation) }
        if isEnabled && isVersionCurrent && isDeviceReady { return .ready }
        if let failure { return .unavailable(failure) }
        guard hasChecked else {
            return queryFailure.map { .unavailable(.operationFailed($0)) } ?? .checking(.extensionStatus)
        }
        if !isInstalled { return .unavailable(.virtualCameraNotInstalled) }
        if !isEnabled { return .unavailable(.virtualCameraDisabled) }
        if !isVersionCurrent { return .unavailable(.versionMismatch) }
        if isWaitingForDevice { return .checking(.devicePublication) }
        if isRefreshing { return .checking(.extensionStatus) }
        return .unavailable(.devicePublicationTimedOut)
    }
}
