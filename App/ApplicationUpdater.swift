//
//  ApplicationUpdater.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import Sparkle
import os

/// Owns Sparkle's UI and postpones a requested relaunch while the camera is in use.
@MainActor
final class ApplicationUpdater: NSObject, SPUUpdaterDelegate, NSMenuItemValidation {

    /// Validated build-time configuration; absent settings leave Sparkle completely stopped.
    private let configuration: UpdateConfiguration?

    /// Coordinates installation using the composition root's live resource availability.
    private let installationGate: UpdateInstallationGate

    /// The retained standard driver, created only after complete configuration is available.
    private var controller: SPUStandardUpdaterController?

    /// Reports configuration state without logging credentials or update URLs.
    private let logger = Logger(
        subsystem: "com.xmax.meeting.camera",
        category: "Updates"
    )

    /// Creates the update owner without starting network work or opening UI.
    init(
        canInstall: @escaping () -> Bool
    ) {
        configuration = UpdateConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])
        installationGate = UpdateInstallationGate(canInstall: canInstall)
        super.init()
    }

    /// Starts the standard updater only when the appcast and signing key have been configured.
    func start() {
        guard controller == nil else { return }
        guard configuration != nil else {
            logger.info("Automatic updates are disabled because release configuration is incomplete")
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.controller = controller
        controller.startUpdater()
    }

    /// Performs an explicit update check or explains why this build has no update service.
    @objc func checkForUpdates(
        _ sender: Any?
    ) {
        guard let controller else {
            showInformation(
                title: UpdateStrings.unavailable,
                message: UpdateStrings.unavailableDetails
            )
            return
        }
        controller.checkForUpdates(sender)
    }

    /// Keeps an unconfigured menu actionable while reflecting Sparkle's in-flight check state.
    func validateMenuItem(
        _ menuItem: NSMenuItem
    ) -> Bool {
        controller?.updater.canCheckForUpdates ?? true
    }

    /// Retries a postponed relaunch when committed media or camera state changes.
    func resumeInstallationIfPossible() {
        installationGate.resumeIfPossible()
    }

    /// Releases postponed callbacks before the application's normal bounded cleanup begins.
    func shutdown() {
        installationGate.cancel()
    }

    /// Defers a user-requested relaunch without stopping capture or losing the downloaded update.
    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        guard installationGate.postponeIfNeeded(installHandler) else { return false }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.installationGate.isPostponed else { return }
            self.showInformation(
                title: UpdateStrings.waiting,
                message: UpdateStrings.waitingDetails
            )
        }
        return true
    }

    /// Prevents a failed or cancelled update from retaining a stale relaunch callback.
    func updater(
        _ updater: SPUUpdater,
        didAbortWithError error: Error
    ) {
        installationGate.cancel()
    }

    /// Shows native information only in response to an explicit update action.
    private func showInformation(
        title: String,
        message: String
    ) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: UpdateStrings.acknowledge)
        alert.runModal()
    }
}
