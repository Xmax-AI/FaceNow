//
//  VirtualMicrophoneStatus.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// Combines driver availability and explicit output intent for every microphone status surface.
enum VirtualMicrophoneStatus: Equatable, Sendable {

    /// The audio driver is not installed or published.
    case notInstalled

    /// The driver is installed but macOS has not published the device.
    case pending

    /// The device is available, but the user has disabled output.
    case disabled

    /// The device is available and the user has enabled output, including before generation begins.
    case enabled

    /// Output has failed and requires explicit recovery.
    case failed

    /// Resolves device availability and user intent independently of generation or audio activity.
    static func resolve(
        driverInstalled: Bool,
        deviceAvailable: Bool,
        enabled: Bool,
        hasFailure: Bool
    ) -> VirtualMicrophoneStatus {
        if hasFailure { return .failed }
        guard deviceAvailable else { return driverInstalled ? .pending : .notInstalled }
        return enabled ? .enabled : .disabled
    }
}
