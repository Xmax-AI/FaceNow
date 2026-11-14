//
//  VirtualMicrophoneSetupViewController.swift
//  FaceNow
//

import AppKit
import Factory

/// Presents explicit native setup actions while the repository owns device state and commands.
@MainActor
final class VirtualMicrophoneSetupViewController: NSViewController {

    /// The shared state and operations represented by this setup dialog.
    @Injected(\.virtualMicrophoneRepo) private var microphoneRepo: VirtualMicrophoneRepository

    /// Presents the current device state without installing anything until the user chooses an action.
    func presentSetup() {
        let installed = microphoneRepo.driverInstalled
        let ready = microphoneRepo.deviceAvailable
        let alert = NSAlert()
        alert.messageText = VirtualMicrophoneStrings.title
        switch microphoneRepo.status {
        case .notInstalled:
            alert.informativeText = VirtualMicrophoneStrings.installInstructions
        case .pending:
            alert.informativeText = VirtualMicrophoneStrings.pendingActivation
        case .disabled:
            alert.informativeText = VirtualMicrophoneStrings.instructions + "\n\n" + VirtualMicrophoneStrings.disabled
        case .enabled:
            alert.informativeText = VirtualMicrophoneStrings.instructions + "\n\n" + VirtualMicrophoneStrings.enabled
        case .failed:
            alert.informativeText = microphoneRepo.failure ?? VirtualMicrophoneStrings.failed
        }
        alert.addButton(
            withTitle: ready
                ? (microphoneRepo.enabled ? VirtualMicrophoneStrings.disable : VirtualMicrophoneStrings.enable)
                : installed ? VirtualMicrophoneStrings.checkAgain : VirtualMicrophoneStrings.install
        )
        alert.addButton(withTitle: VirtualMicrophoneStrings.cancel)
        alert.addButton(
            withTitle: installed ? VirtualMicrophoneStrings.uninstall : VirtualMicrophoneStrings.audioSettings
        )
        if installed { alert.addButton(withTitle: VirtualMicrophoneStrings.reinstall) }
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            microphoneRepo.clearFailure()
            if ready {
                microphoneRepo.setEnabled(!microphoneRepo.enabled)
            } else if installed {
                microphoneRepo.refreshDeviceAvailability()
            } else {
                microphoneRepo.installDriver()
            }
        } else if installed, response.rawValue == NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1 {
            microphoneRepo.clearFailure()
            microphoneRepo.installDriver()
        } else if response == .alertThirdButtonReturn {
            if installed {
                confirmUninstall()
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
            }
        }
    }

    /// Explains the shared driver's removal before opening the system authorization flow.
    private func confirmUninstall() {
        let alert = NSAlert()
        alert.messageText = VirtualMicrophoneStrings.uninstall
        alert.informativeText = VirtualMicrophoneStrings.uninstallInstructions
        alert.addButton(withTitle: VirtualMicrophoneStrings.uninstall)
        alert.addButton(withTitle: VirtualMicrophoneStrings.cancel)
        if alert.runModal() == .alertFirstButtonReturn { microphoneRepo.uninstallDriver() }
    }
}
