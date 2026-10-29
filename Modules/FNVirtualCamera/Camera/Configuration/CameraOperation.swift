//
//  CameraOperation.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Identifies the actual device operation independently of its localized button label.
enum CameraOperation: String, Codable, Equatable, Sendable {

    /// Requests the first camera permission prompt.
    case requestAccess

    /// Reads installed extension properties.
    case checkStatus

    /// Rescans physical camera inputs without opening a capture stream.
    case discoverInput

    /// Rechecks publication and the virtual producer connection.
    case discoverOutput

    /// Installs and enables the bundled camera extension.
    case install

    /// Removes an obsolete extension before installing the bundled version.
    case reinstall

    /// Removes the installed camera extension.
    case remove

    /// Keeps a guide step from displaying progress belonging to another subsystem.
    func belongs(
        to scope: CameraPreparationScope
    ) -> Bool {
        switch scope {
        case .complete: return true
        case .cameraInput: return self == .requestAccess || self == .discoverInput
        case .virtualOutput: return self != .requestAccess && self != .discoverInput
        }
    }
}

/// Explains whether progress belongs to an explicit action or a background refresh.
enum CameraOperationOrigin: Equatable, Sendable {

    /// A deliberate user action may display inline progress.
    case user

    /// Routine checks preserve the current product presentation.
    case background
}

/// Gives a device workflow a stable identity across system callbacks and device discovery.
struct CameraOperationContext: Equatable, Sendable {

    /// Rejects completion from an older workflow.
    let id = UUID()

    /// The operation that a retry must repeat.
    let kind: CameraOperation

    /// Determines whether the presentation should retain inline progress.
    let origin: CameraOperationOrigin
}

/// Preserves actionable system error categories without inspecting diagnostic strings.
enum CameraOperationFailureKind: String, Codable, Equatable, Sendable {

    /// A system API or device connection failed.
    case system

    /// Automatic removal could not match the installed extension record.
    case missingExtensionRecord

    /// User approval or administrator authorization was not granted.
    case authorization

    /// The user cancelled the native request.
    case cancelled

    /// A different system request for this extension is already pending.
    case pendingRequest

    /// The bundle signature, entitlement, or packaged extension is invalid.
    case invalidBundle

    /// macOS or management policy prohibits this extension.
    case systemPolicy

    /// The containing application must be moved to Applications.
    case invalidLocation

    /// An interrupted workflow must be reviewed rather than automatically submitted again.
    case interrupted

    /// A bounded device recovery still failed after a system restart.
    case recoveryExhausted
}

/// Carries the failed command and original diagnostics to the state and logging boundaries.
struct CameraOperationFailure: Codable, Equatable, Sendable {

    /// The actual failed stage used to choose a concrete recovery action.
    let operation: CameraOperation

    /// Selects an actionable fallback without parsing English error messages.
    var kind: CameraOperationFailureKind = .system

    /// The original system explanation retained for diagnostics.
    let diagnosticMessage: String

    /// The original NSError identity, preserved without exposing credentials or request data.
    var errorDomain: String? = nil
    var errorCode: Int? = nil

    /// Classifies stable SystemExtensions error codes independently of localized descriptions.
    static func systemExtension(
        operation: CameraOperation,
        domain: String,
        code: Int,
        message: String
    ) -> Self {
        let kind: CameraOperationFailureKind
        if domain == "OSSystemExtensionErrorDomain" {
            switch code {
            case 2, 5, 6, 7, 8, 9: kind = .invalidBundle
            case 3: kind = .invalidLocation
            case 4: kind = operation == .remove ? .missingExtensionRecord : .invalidBundle
            case 10: kind = .systemPolicy
            case 11: kind = .cancelled
            case 12: kind = .pendingRequest
            case 13: kind = .authorization
            default: kind = .system
            }
        } else {
            kind = .system
        }
        return Self(
            operation: operation,
            kind: kind,
            diagnosticMessage: message,
            errorDomain: domain,
            errorCode: code
        )
    }

}

/// Persists a user-authorized setup across native callbacks, application exits, and system restarts.
struct CameraSetupWorkflow: Codable, Equatable, Sendable {

    /// The next confirmed boundary in installation or removal.
    enum Phase: String, Codable, Sendable {
        case removing
        case confirmingRemoval
        case waitingForRemovalRestart
        case installing
        case waitingForInstallationRestart
        case verifying
        case manualRemoval
        case failed
    }

    /// The repository action permitted by the latest system observation.
    enum NextAction: Equatable {
        case install
        case verify
        case waitForSystem
        case manualRemoval
        case none
    }

    /// The bundled build that the user authorized this workflow to install.
    let targetVersion: String

    /// The current durable phase; it never implies that the device is ready.
    var phase: Phase

    /// The boot session in which macOS explicitly requested a restart.
    var restartBootID: String?

    /// Prevents a stale removal record from starting another reboot loop on later refreshes.
    var removalRestartObserved = false

    /// The structured failure retained until a new explicit operation or verified recovery.
    var failure: CameraOperationFailure?

    /// The dedicated persistence key for camera preparation, separate from onboarding exposure.
    private static let storageKey = "facenow.virtualCamera.setup.v1"

    /// Records the native removal result before a subsequent properties query can run.
    mutating func removalCompleted(
        needsRestart: Bool,
        bootID: String
    ) {
        phase = needsRestart ? .waitingForRemovalRestart : .confirmingRemoval
        restartBootID = needsRestart ? bootID : nil
    }

    /// Records installation completion independently from actual device publication.
    mutating func installationCompleted(
        needsRestart: Bool,
        bootID: String
    ) {
        phase = needsRestart ? .waitingForInstallationRestart : .verifying
        restartBootID = needsRestart ? bootID : nil
    }

    /// Chooses a continuation only from confirmed properties, never from a failed or pending query.
    mutating func reconcile(
        hasRecords: Bool,
        hasCurrentRecord: Bool,
        onlyUninstalling: Bool,
        bootID: String
    ) -> NextAction {
        var observedRestart = false
        switch phase {
        case .waitingForRemovalRestart, .waitingForInstallationRestart:
            guard let previousBoot = restartBootID, !previousBoot.isEmpty, !bootID.isEmpty else {
                phase = .failed
                failure = CameraOperationFailure(
                    operation: .checkStatus,
                    diagnosticMessage: "The macOS boot session could not be verified to resume camera setup safely."
                )
                return .none
            }
            guard previousBoot != bootID else { return .waitForSystem }
            observedRestart = true
            if phase == .waitingForRemovalRestart {
                removalRestartObserved = true
                phase = .confirmingRemoval
            } else {
                phase = .verifying
            }
            restartBootID = nil
        default:
            break
        }
        switch phase {
        case .removing, .confirmingRemoval, .manualRemoval:
            if hasCurrentRecord {
                phase = .verifying
                failure = nil
                return .verify
            }
            if !hasRecords {
                phase = .installing
                failure = nil
                return .install
            }
            if onlyUninstalling {
                if observedRestart || removalRestartObserved {
                    phase = .manualRemoval
                    return .manualRemoval
                }
                phase = .waitingForRemovalRestart
                restartBootID = bootID
                return .waitForSystem
            }
            phase = .manualRemoval
            return .manualRemoval
        case .installing, .verifying:
            if hasCurrentRecord {
                phase = .verifying
                return .verify
            }
            if hasRecords {
                if onlyUninstalling {
                    phase = .waitingForRemovalRestart
                    restartBootID = bootID
                    return .waitForSystem
                }
                phase = .manualRemoval
                failure = CameraOperationFailure(
                    operation: .remove,
                    kind: .missingExtensionRecord,
                    diagnosticMessage: "A different extension version is still registered."
                )
                return .manualRemoval
            }
            phase = .failed
            failure = CameraOperationFailure(
                operation: .install,
                kind: .interrupted,
                diagnosticMessage: "The installation ended without a matching extension record."
            )
            return .none
        case .waitingForRemovalRestart, .waitingForInstallationRestart:
            return .waitForSystem
        case .failed:
            if hasCurrentRecord {
                phase = .verifying
                return .verify
            }
            return .none
        }
    }

    /// Writes or clears the durable user intent without persisting guessed installation facts.
    static func save(
        _ workflow: Self?,
        to defaults: UserDefaults
    ) {
        if let workflow, let data = try? JSONEncoder().encode(workflow) {
            defaults.set(data, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }

    /// Restores only an intent for the currently bundled version.
    static func load(
        from defaults: UserDefaults,
        targetVersion: String
    ) -> Self? {
        guard let data = defaults.data(forKey: storageKey),
            let workflow = try? JSONDecoder().decode(Self.self, from: data),
            workflow.targetVersion == targetVersion
        else {
            defaults.removeObject(forKey: storageKey)
            return nil
        }
        return workflow
    }
}

/// Limits device-recovery suggestions across application relaunches and system restarts.
struct CameraDeviceRecovery: Codable, Equatable {

    /// The result shown after a bounded device check, without executing any system action.
    enum NextStep: Equatable {
        case restartApplication
        case toggleExtension
        case install
    }

    /// Scopes a recovery attempt to one bundled extension build.
    let targetVersion: String

    /// The system boot in which the camera first failed publication.
    let initialBootID: String

    /// Marks an explicit trip to extension settings, rather than guessing whether a switch changed.
    var settingsOpened = false

    /// Identifies the process that requested a relaunch so a cancelled/failed relaunch does not count.
    var relaunchFromProcessID: Int32?

    /// Prefers explicit activation after settings recovery without prescribing a system restart.
    func nextStep(
        bootID: String,
        processID: Int32,
        staleHost: Bool
    ) -> NextStep {
        if !initialBootID.isEmpty, !bootID.isEmpty, initialBootID != bootID { return .install }
        if staleHost, relaunchFromProcessID == nil || relaunchFromProcessID == processID {
            return .restartApplication
        }
        if settingsOpened { return .install }
        return .toggleExtension
    }
}
