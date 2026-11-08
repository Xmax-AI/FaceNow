//
//  CameraStrings.swift
//  FaceNow
//

import Foundation
#if canImport(Localization)
    import Localization
#endif

/// Provides module-owned English defaults and stable localization keys for page presentation.
enum CameraStrings {

    /// Camera preparation status or recovery message.
    static var statusCameraAccessHasNotBeenAllowedAllowCameraAccess: String {
        Localization.string(
            "status.camera_access_has_not_been_allowed_allow_camera_access",
            table: "Camera",
            defaultValue: "Camera access has not been allowed. Allow camera access in setup."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusCameraAccessIsOffEnableFaceNowInSystemSettings: String {
        Localization.string(
            "status.camera_access_is_off_enable_facenow_in_system_settings",
            table: "Camera",
            defaultValue: "Camera access is off. Enable FaceNow in System Settings → Privacy & Security → Camera."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusCameraAccessIsRestrictedByMacOSOrDevicePolicy: String {
        Localization.string(
            "status.camera_access_is_restricted_by_macos_or_device_policy",
            table: "Camera",
            defaultValue: "Camera access is restricted by macOS or device policy."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusNoPhysicalCameraWasFoundConnectACameraAnd: String {
        Localization.string(
            "status.no_physical_camera_was_found_connect_a_camera_and",
            table: "Camera",
            defaultValue: "No physical camera was found. Connect a camera and check again."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusTheSelectedCameraWasDisconnectedReconnectItOrSelect: String {
        Localization.string(
            "status.the_selected_camera_was_disconnected_reconnect_it_or_select",
            table: "Camera",
            defaultValue: "The selected camera was disconnected. Reconnect it or select another camera."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusVirtualCameraIsNotInstalledInstallItInSetup: String {
        Localization.string(
            "status.virtual_camera_is_not_installed_install_it_in_setup",
            table: "Camera",
            defaultValue: "Virtual Camera is not installed. Install it in setup."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusVirtualCameraIsDisabledEnableItInSystemSettings: String {
        Localization.string(
            "status.virtual_camera_is_disabled_enable_it_in_system_settings",
            table: "Camera",
            defaultValue: "Virtual Camera is disabled. Enable it in System Settings."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusVirtualCameraNeedsAnUpdateToMatchThisVersion: String {
        Localization.string(
            "status.virtual_camera_needs_an_update_to_match_this_version",
            table: "Camera",
            defaultValue: "Reinstall Virtual Camera to match this version of FaceNow."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusApproveTheFaceNowCameraExtensionInSystemSettings: String {
        Localization.string(
            "status.approve_the_facenow_camera_extension_in_system_settings",
            table: "Camera",
            defaultValue: "Approve the FaceNow camera extension in System Settings."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusVirtualCameraDidNotBecomeAvailableInTimeCheck: String {
        Localization.string(
            "status.virtual_camera_did_not_become_available_in_time_check",
            table: "Camera",
            defaultValue:
                "Virtual Camera is enabled but unavailable. Turn FaceNow off and back on in Camera Extensions, then return to FaceNow."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusMacOSHasRefreshedTheCameraQuitAndReopenFaceNow: String {
        Localization.string(
            "status.macos_has_refreshed_the_camera_quit_and_reopen_facenow",
            table: "Camera",
            defaultValue: "macOS has refreshed the camera. Quit and reopen FaceNow to refresh its device list."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusMoveFaceNowToApplicationsBeforeInstallingVirtualCamera: String {
        Localization.string(
            "status.move_facenow_to_applications_before_installing_virtual_camera",
            table: "Camera",
            defaultValue: "Move FaceNow to /Applications before installing Virtual Camera."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusActivateVirtualCameraToFinishSetup: String {
        Localization.string(
            "status.activate_virtual_camera_to_finish_setup",
            table: "Camera",
            defaultValue: "Activate Virtual Camera to finish setup."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusWaitingForCameraPermissionPleaseAnswerTheSystemPrompt: String {
        Localization.string(
            "status.waiting_for_camera_permission_please_answer_the_system_prompt",
            table: "Camera",
            defaultValue: "Waiting for camera permission. Please answer the system prompt."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusVirtualCameraIsBeingInstalledPleaseWait: String {
        Localization.string(
            "status.virtual_camera_is_being_installed_please_wait",
            table: "Camera",
            defaultValue: "Virtual Camera is being installed. Please wait."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusVirtualCameraIsBeingRemovedPleaseWait: String {
        Localization.string(
            "status.virtual_camera_is_being_removed_please_wait",
            table: "Camera",
            defaultValue: "Virtual Camera is being removed. Please wait."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusWaitingForVirtualCameraToBecomeAvailablePleaseWait: String {
        Localization.string(
            "status.waiting_for_virtual_camera_to_become_available_please_wait",
            table: "Camera",
            defaultValue: "Waiting for Virtual Camera to become available. Please wait."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusCheckingCameraSetupPleaseTryAgainInAMoment: String {
        Localization.string(
            "status.checking_camera_setup_please_try_again_in_a_moment",
            table: "Camera",
            defaultValue: "Checking camera setup. Please try again in a moment."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusCameraReady: String {
        Localization.string(
            "status.camera_ready",
            table: "Camera",
            defaultValue: "Camera ready"
        )
    }

    /// Camera preparation status or recovery message.
    static var statusNotChecked: String {
        Localization.string(
            "status.not_checked",
            table: "Camera",
            defaultValue: "Not checked"
        )
    }

    /// Camera preparation status or recovery message.
    static var statusMoveFaceNowToApplicationsBeforeInstallingTheExtension: String {
        Localization.string(
            "status.move_facenow_to_applications_before_installing_the_extension",
            table: "Camera",
            defaultValue: "Move FaceNow to /Applications before installing the extension."
        )
    }

    /// Separates a missing app component from an unsupported installation location.
    static var statusInvalidCameraBundle: String {
        Localization.string(
            "status.invalid_camera_bundle",
            table: "Camera",
            defaultValue: "FaceNow’s camera component is unavailable. Reinstall FaceNow before continuing."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusRemovingVirtualCamera: String {
        Localization.string(
            "status.removing_virtual_camera",
            table: "Camera",
            defaultValue: "Removing virtual camera…"
        )
    }

    /// Camera preparation status or recovery message.
    static var statusInstallingCameraExtension: String {
        Localization.string(
            "status.installing_camera_extension",
            table: "Camera",
            defaultValue: "Installing camera extension…"
        )
    }

    /// Camera preparation status or recovery message.
    static var statusEnableFaceNowXmaxVirtualCameraInSystemSettingsGeneral: String {
        Localization.format(
            "status.enable_facenow_xmax_virtual_camera_in_system_settings_general",
            table: "Camera",
            defaultValue:
                "Enable %1$@ in System Settings → General → Login Items & Extensions → Camera Extensions.",
            arguments: [VirtualCameraConfiguration.deviceName]
        )
    }

    /// Reports an incomplete native setup while keeping explicit activation available.
    static var statusInstallationIncomplete: String {
        Localization.string(
            "status.installation_incomplete",
            table: "Camera",
            defaultValue: "Virtual Camera setup is incomplete. Install it again to continue."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusRequestCompleted: String {
        Localization.string(
            "status.request_completed",
            table: "Camera",
            defaultValue: "Request completed"
        )
    }

    /// Camera preparation status or recovery message.
    static var statusUpdateVirtualCameraToMatchThisVersionOfFaceNow: String {
        Localization.string(
            "status.update_virtual_camera_to_match_this_version_of_facenow",
            table: "Camera",
            defaultValue: "Reinstall Virtual Camera to match this version of FaceNow."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusCameraExtensionEnabledClickUpdateToTestActivation: String {
        Localization.string(
            "status.camera_extension_enabled_click_update_to_test_activation",
            table: "Camera",
            defaultValue: "Camera extension enabled. Reinstall Virtual Camera to test setup."
        )
    }

    /// Camera preparation status or recovery message.
    static var statusCameraExtensionNotEnabled: String {
        Localization.string(
            "status.camera_extension_not_enabled",
            table: "Camera",
            defaultValue: "Camera extension not enabled"
        )
    }

    /// Camera preparation status or recovery message.
    static var statusCameraExtensionEnabledWaitingForTheCameraToBecome: String {
        Localization.string(
            "status.camera_extension_enabled_waiting_for_the_camera_to_become",
            table: "Camera",
            defaultValue: "Camera extension enabled. Waiting for the camera to become available…"
        )
    }

    /// Camera preparation status or recovery message.
    static var statusVirtualCameraReady: String {
        Localization.string(
            "status.virtual_camera_ready",
            table: "Camera",
            defaultValue: "Virtual camera ready"
        )
    }

    /// Camera preparation status or recovery message.
    static var statusMacOSHasRefreshedTheCameraButFaceNowStillHas: String {
        Localization.string(
            "status.macos_has_refreshed_the_camera_but_facenow_still_has",
            table: "Camera",
            defaultValue:
                "macOS has refreshed the camera, but FaceNow still has the previous device list. Quit and reopen FaceNow to continue."
        )
    }

    /// Localized page text; preserve all placeholders and product names.
    static var removalMismatch: String {
        Localization.string(
            "error.removal_mismatch",
            table: "Camera",
            defaultValue:
                "Removal failed: macOS could not match the installed camera to this app. Click Update, then Remove, or remove it in System Settings."
        )
    }
    /// Complete display message; preserve the format placeholders.
    static func removalFailed(
        message: String
    ) -> String {
        Localization.format(
            "error.removal_failed",
            table: "Camera",
            defaultValue: "Removal failed: %@",
            arguments: [message]
        )
    }

    /// Complete display message; preserve the format placeholders.
    static func installationFailed(
        message: String
    ) -> String {
        Localization.format(
            "error.installation_failed",
            table: "Camera",
            defaultValue: "Installation failed: %@",
            arguments: [message]
        )
    }

    /// Localized page text; preserve all placeholders and product names.
    static func notReady(
        message: String
    ) -> String {
        Localization.format(
            "error.not_ready",
            table: "Camera",
            defaultValue: "Camera not ready: %@ Click Refresh to retry.",
            arguments: [message]
        )
    }

}
