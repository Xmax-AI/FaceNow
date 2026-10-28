//
//  ApplicationLifecycleActions.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import Carbon
import os

/// Performs explicit platform lifecycle commands without depending on business repositories.
@MainActor
enum ApplicationLifecycleActions {

    /// Asks Launch Services for a replacement process after the caller has released capture resources.
    static func launchReplacement() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(
                at: Bundle.main.bundleURL,
                configuration: configuration
            ) { application, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if application != nil {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CocoaError(.executableNotLoadable))
                }
            }
        }
    }

    /// Requests loginwindow's native restart confirmation, leaving cancellation to the user.
    static func showSystemRestartConfirmation() throws {
        var process = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kSystemProcess))
        var target = AEAddressDesc()
        var event = AppleEvent()
        var reply = AppleEvent()
        var status = OSStatus(
            AECreateDesc(
                DescType(typeProcessSerialNumber),
                &process,
                MemoryLayout<ProcessSerialNumber>.size,
                &target
            )
        )
        guard status == noErr else { throw restartFailure(status) }
        defer { AEDisposeDesc(&target) }
        status = OSStatus(
            AECreateAppleEvent(
                AEEventClass(kCoreEventClass),
                AEEventID(kAEShowRestartDialog),
                &target,
                AEReturnID(kAutoGenerateReturnID),
                AETransactionID(kAnyTransactionID),
                &event
            )
        )
        guard status == noErr else { throw restartFailure(status) }
        defer {
            AEDisposeDesc(&event)
            AEDisposeDesc(&reply)
        }
        status = AESendMessage(
            &event,
            &reply,
            AESendMode(kAENoReply | kAECanInteract),
            kAEDefaultTimeout
        )
        guard status == noErr else { throw restartFailure(status) }
    }

    /// Retains the platform status in diagnostics while giving the user an actionable manual fallback.
    private static func restartFailure(
        _ status: OSStatus
    ) -> NSError {
        Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "Application",
            category: "Lifecycle"
        ).error("System restart confirmation failed: \(status)")
        return NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Couldn’t open the restart dialog. Restart your Mac from the Apple menu."
            ]
        )
    }
}
