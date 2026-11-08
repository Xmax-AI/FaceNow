//
//  VirtualMicrophoneStrings.swift
//  FaceNow
//

import Foundation

/// Provides edition-fixed copy for the virtual microphone's explicit setup flow.
enum VirtualMicrophoneStrings {
    /// The setup title follows the app edition’s fixed language.
    static var title: String { text("microphone.title", "Virtual Microphone") }
    /// Enables result-audio output.
    static var enable: String { text("microphone.enable", "Enable") }
    /// Disables output without closing generation.
    static var disable: String { text("microphone.disable", "Disable") }
    /// Opens the system installer.
    static var install: String { text("microphone.install", "Install") }
    /// Replaces an existing system driver after a display-name or driver update.
    static var reinstall: String { text("microphone.reinstall", "Reinstall Driver") }

    /// Closes the setup dialog.
    static var cancel: String { text("microphone.cancel", "Close") }
    /// Opens the system audio-device utility.
    static var audioSettings: String { text("microphone.settings", "Audio MIDI Setup") }
    /// Explains routing synchronized audio into meeting software.
    static var instructions: String {
        Localization.format(
            "microphone.instructions",
            table: "VirtualMicrophone",
            defaultValue: "In your meeting app, select %1$@ as the microphone to keep audio and video in sync. Local listening volume does not affect this output. When no audio is available, the microphone outputs silence.",
            arguments: [VirtualMicrophoneConfiguration.deviceName]
        )
    }
    /// Describes administrator installation and deferred device loading.
    static var installInstructions: String {
        text(
            "microphone.install_instructions",
            "Install the FaceNow audio driver with the macOS installer. Administrator authorization is required. After installation, restart your Mac if the device has not appeared, then return here to enable it. This does not change your default microphone or speakers."
        )
    }
    /// Explicitly removes only FaceNow's system audio driver through the macOS installer.
    static var uninstall: String { text("microphone.uninstall", "Uninstall Driver") }
    /// Explains removal before requesting administrator authorization.
    static var uninstallInstructions: String {
        text(
            "microphone.uninstall_instructions",
            "Uninstall the FaceNow audio driver? Administrator authorization is required. Restart your Mac after removal to unload the device. Only this FaceNow edition’s audio driver will be removed. The other edition and other audio drivers will not be changed."
        )
    }

    /// Reports the explicit output switch independently of generation or audio activity.
    static var enabled: String { text("microphone.enabled", "Enabled") }
    static var disabled: String { text("microphone.disabled", "Disabled") }

    /// Explains that installation succeeded but system device publication has not completed.
    static var pendingActivation: String {
        text(
            "microphone.pending_activation",
            "The driver is installed, but macOS has not loaded the microphone yet. Restart your Mac, then open FaceNow again. Reinstalling or reopening FaceNow alone will not reload the system audio service."
        )
    }

    /// Refreshes device publication without reinstalling or restarting system audio.
    static var checkAgain: String { text("microphone.check_again", "Check Again") }

    /// Reports a missing or unopenable installer without implying generated audio has failed.
    static var installerUnavailable: String {
        text(
            "microphone.installer_unavailable",
            "Couldn’t open the audio driver installer. Reinstall FaceNow and try again."
        )
    }

    /// Reports a recoverable audio-output failure.
    static var failed: String {
        text(
            "microphone.failed",
            "Virtual microphone output is unavailable and has been disabled. Generation and the virtual camera will continue. Check the audio driver, then enable it again."
        )
    }

    /// Reads module-owned keys from the shared catalog without following the system language.
    private static func text(
        _ key: String,
        _ fallback: String
    ) -> String {
        Localization.string(key, table: "VirtualMicrophone", defaultValue: fallback)
    }
}
