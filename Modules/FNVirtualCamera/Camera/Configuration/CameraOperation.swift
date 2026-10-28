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
enum CameraOperation: Equatable, Sendable {

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

    /// Replaces an installed extension with the bundled version.
    case update

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
enum CameraOperationFailureKind: Equatable, Sendable {

    /// A system API or device connection failed.
    case system

    /// Automatic removal could not match the installed extension record.
    case missingExtensionRecord
}

/// Carries the failed command and original diagnostics to the state and logging boundaries.
struct CameraOperationFailure: Equatable, Sendable {

    /// The exact command offered by Retry.
    let operation: CameraOperation

    /// Selects an actionable fallback without parsing English error messages.
    var kind: CameraOperationFailureKind = .system

    /// The original system explanation retained for diagnostics.
    let diagnosticMessage: String
}
