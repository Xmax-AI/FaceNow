//
//  UpdateInstallationGate.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Resumes a user-requested update exactly once after the host releases its media resources.
@MainActor
final class UpdateInstallationGate {

    /// Reads live application availability without retaining business state.
    private let canInstall: () -> Bool

    /// The Sparkle continuation retained only while installation is postponed.
    private var installation: (() -> Void)?

    /// Whether an installation is waiting for the host to become idle.
    var isPostponed: Bool { installation != nil }

    /// Uses the composition root's current media and extension availability.
    init(
        canInstall: @escaping () -> Bool
    ) {
        self.canInstall = canInstall
    }

    /// Retains the continuation only when active media or camera operations prevent installation.
    func postponeIfNeeded(
        _ install: @escaping () -> Void
    ) -> Bool {
        guard !canInstall() else { return false }
        installation = install
        return true
    }

    /// Consumes the continuation before invoking it to tolerate synchronous state notifications.
    func resumeIfPossible() {
        guard canInstall(), let install = installation else { return }
        installation = nil
        install()
    }

    /// Drops obsolete update work after cancellation, failure, or application shutdown.
    func cancel() {
        installation = nil
    }
}
