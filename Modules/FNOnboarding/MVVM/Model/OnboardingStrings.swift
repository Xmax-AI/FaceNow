//
//  OnboardingStrings.swift
//  FaceNow
//

import Foundation
#if canImport(Localization)
    import Localization
#endif

/// Provides module-owned English defaults and stable localization keys for page presentation.
enum OnboardingStrings {

    /// Describes an explicit in-progress microphone device query.
    static var virtualMicrophoneCheckingDetail: String {
        Localization.string(
            "guide.virtual_microphone_checking_detail",
            table: "Onboarding",
            defaultValue: "Checking Virtual Microphone. Please wait..."
        )
    }

    /// Confirms that a completed query still found no published device.
    static var virtualMicrophoneCheckedPendingDetail: String {
        Localization.string(
            "guide.virtual_microphone_checked_pending_detail",
            table: "Onboarding",
            defaultValue:
                "Check complete. macOS still has not detected Virtual Microphone. The driver is installed. Restart your Mac and check again, or set up audio later."
        )
    }

    /// Distinguishes a completed negative installation check from an in-progress query.
    static var virtualMicrophoneCheckedNotInstalledDetail: String {
        Localization.string(
            "guide.virtual_microphone_checked_not_installed_detail",
            table: "Onboarding",
            defaultValue:
                "Check complete. The Virtual Microphone driver was not found. Install it first, or set up audio later."
        )
    }

    /// Offers retry or deferral when system discovery takes too long.
    static var virtualMicrophoneCheckTimedOutDetail: String {
        Localization.string(
            "guide.virtual_microphone_check_timed_out_detail",
            table: "Onboarding",
            defaultValue:
                "The check timed out, so Virtual Microphone status could not be confirmed. Check again, or set up audio later."
        )
    }

    /// Describes the supplied microphone-access prompt to assistive technologies.
    static var microphonePermissionPrompt: String {
        Localization.string(
            "guide.microphone_permission_prompt",
            table: "Onboarding",
            defaultValue: "Microphone permission dialog. Choose Allow."
        )
    }

    /// Groups optional microphone permission and synchronized audio output.
    static var audioSetup: String {
        Localization.string(
            "guide.audio_setup",
            table: "Onboarding",
            defaultValue: "Audio Setup (Optional)"
        )
    }

    /// Defers the complete audio setup without leaving the video preparation flow.
    static var skipAudioSetup: String {
        Localization.string(
            "guide.skip_audio_setup",
            table: "Onboarding",
            defaultValue: "Set Up Audio Later"
        )
    }

    /// Finishes preparation without implying that camera capture has already started.
    static var finishSetup: String {
        Localization.string(
            "guide.finish_setup",
            table: "Onboarding",
            defaultValue: "Finish Setup"
        )
    }

    /// Explains administrator installation while allowing video use before audio is ready.
    static var virtualMicrophoneInstallDetail: String {
        Localization.string(
            "guide.virtual_microphone_install_detail",
            table: "Onboarding",
            defaultValue:
                "Install the FaceNow audio driver with the macOS installer. Administrator authorization is required. If the device has not appeared after installation, you can use video first and restart your Mac later to finish audio setup."
        )
    }

    /// Keeps a deferred audio-driver restart from interrupting video preparation.
    static var virtualMicrophonePendingDetail: String {
        Localization.string(
            "guide.virtual_microphone_pending_detail",
            table: "Onboarding",
            defaultValue:
                "The Virtual Microphone driver is installed but not active yet. You can use video first and restart your Mac later to finish audio setup."
        )
    }

    /// Explains the location prerequisite before offering virtual-camera installation.
    static var moveApplicationTitle: String {
        Localization.string(
            "guide.move_application_title",
            table: "Onboarding",
            defaultValue: "Move FaceNow to Applications"
        )
    }

    /// Names the recovery for a missing or invalid bundled camera component.
    static var reinstallApplicationTitle: String {
        Localization.string(
            "guide.reinstall_application_title",
            table: "Onboarding",
            defaultValue: "Reinstall FaceNow"
        )
    }

    /// Distinguishes an unavailable status check from an activation failure.
    static var noticeCameraStatusCheckFailed: String {
        Localization.string(
            "notice.camera_status_check_failed",
            table: "Onboarding",
            defaultValue: "Couldn’t check Virtual Camera. Check again, or reopen FaceNow if this continues."
        )
    }

    /// Opens the guide from any visible camera status banner.
    static var viewAction: String {
        Localization.string(
            "action.view",
            table: "Onboarding",
            defaultValue: "View"
        )
    }

    /// Explains the native administrator authorization requirement without suggesting a blind retry.
    static var noticeSetupAuthorizationRequired: String {
        Localization.string(
            "notice.setup_authorization_required",
            table: "Onboarding",
            defaultValue:
                "Administrator authorization is required to continue camera setup. Approve the macOS dialog, or review the extension in System Settings."
        )
    }

    /// Describes a typed virtual-camera installation or recovery step.
    static var reinstall: String {
        Localization.string(
            "action.reinstall",
            table: "Onboarding",
            defaultValue: "Reinstall"
        )
    }

    /// Describes a typed virtual-camera installation or recovery step.
    static var reinstalling: String {
        Localization.string(
            "notice.reinstalling",
            table: "Onboarding",
            defaultValue: "Reinstalling…"
        )
    }

    /// Describes a typed virtual-camera installation or recovery step.
    static var copyErrorDetails: String {
        Localization.string(
            "action.copy_error_details",
            table: "Onboarding",
            defaultValue: "Copy Error Details"
        )
    }

    /// Describes a typed virtual-camera installation or recovery step.
    static var noticeReinstallVirtualCamera: String {
        Localization.string(
            "notice.reinstall_virtual_camera",
            table: "Onboarding",
            defaultValue: "Reinstall Virtual Camera to use this version of FaceNow."
        )
    }

    /// Describes a typed virtual-camera installation or recovery step.
    static var noticeReinstallingVirtualCamera: String {
        Localization.string(
            "notice.reinstalling_virtual_camera",
            table: "Onboarding",
            defaultValue: "Removing the previous camera extension before installing the new version…"
        )
    }

    /// Describes a typed virtual-camera installation or recovery step.
    static var noticeManualRemoval: String {
        Localization.string(
            "notice.manual_removal",
            table: "Onboarding",
            defaultValue:
                "FaceNow couldn’t remove the previous camera extension automatically. Remove it in System Settings to continue."
        )
    }

    /// Describes a typed virtual-camera installation or recovery step.
    static var noticeSetupApprovalRequired: String {
        Localization.string(
            "notice.setup_approval_required",
            table: "Onboarding",
            defaultValue:
                "macOS is waiting for approval or another camera extension request. Review Camera Extensions in System Settings."
        )
    }

    /// Describes a typed virtual-camera installation or recovery step.
    static var noticeInvalidCameraBundle: String {
        Localization.string(
            "notice.invalid_camera_bundle",
            table: "Onboarding",
            defaultValue:
                "FaceNow’s camera component is missing or couldn’t be validated. Reinstall FaceNow, or copy the error details for support."
        )
    }

    /// Describes a typed virtual-camera installation or recovery step.
    static var noticeCameraBlockedByPolicy: String {
        Localization.string(
            "notice.camera_blocked_by_policy",
            table: "Onboarding",
            defaultValue:
                "macOS or your organization’s policy blocked the camera extension. Contact your administrator or FaceNow support."
        )
    }

    /// Describes a typed virtual-camera installation or recovery step.
    static var noticeCameraRecoveryExhausted: String {
        Localization.string(
            "notice.camera_recovery_exhausted",
            table: "Onboarding",
            defaultValue:
                "Virtual Camera is still unavailable after recovery. Copy the error details and contact support."
        )
    }

    /// Describes a typed virtual-camera installation or recovery step.
    static var noticeSetupInterrupted: String {
        Localization.string(
            "notice.setup_interrupted",
            table: "Onboarding",
            defaultValue: "Camera setup was cancelled or interrupted. Continue when you are ready."
        )
    }

    /// Describes a typed virtual-camera installation or recovery step.
    static var noticeSetupFailedWithDetails: String {
        Localization.string(
            "notice.setup_failed_with_details",
            table: "Onboarding",
            defaultValue: "Virtual Camera setup couldn’t be completed. Copy the error details and contact support."
        )
    }

    /// Describes a typed virtual-camera installation or recovery step.
    static var guideExplanationReinstall: String {
        Localization.string(
            "guide.explanation.reinstall",
            table: "Onboarding",
            defaultValue:
                "Click “Install” in the bottom-right corner. FaceNow will replace the previous camera extension and check that Virtual Camera is available."
        )
    }

    /// Describes a typed virtual-camera installation or recovery step.
    static var guideExplanationManualRemoval: String {
        Localization.string(
            "guide.explanation.manual_removal",
            table: "Onboarding",
            defaultValue:
                "Click “Open System Settings” in the bottom-right corner. In Camera Extensions, remove the previous FaceNow extension, then return to FaceNow. Installation will continue automatically once removal is confirmed."
        )
    }

    /// Describes a typed virtual-camera installation or recovery step.
    static var guideExplanationContactSupport: String {
        Localization.string(
            "guide.explanation.contact_support",
            table: "Onboarding",
            defaultValue:
                "Click “Copy Error Details” in the bottom-right corner and include the details when contacting FaceNow support."
        )
    }

    /// Explains an incomplete setup without prescribing a system restart.
    static var noticeInstallationIncomplete: String {
        Localization.string(
            "notice.installation_incomplete",
            table: "Onboarding",
            defaultValue: "Virtual Camera setup is incomplete. Install it again to continue."
        )
    }

    /// Guides recovery after macOS enables the extension without publishing its camera device.
    static var noticeVirtualCameraNotPublished: String {
        Localization.string(
            "notice.virtual_camera_not_published",
            table: "Onboarding",
            defaultValue: "Virtual Camera is enabled, but macOS has not made the camera available."
        )
    }

    /// Guides recovery after macOS enables the extension without publishing its camera device.
    static var guideRestartVirtualCamera: String {
        Localization.string(
            "guide.recovery.restart_virtual_camera",
            table: "Onboarding",
            defaultValue: "Restart Virtual Camera"
        )
    }

    /// Guides recovery after macOS enables the extension without publishing its camera device.
    static var guideToggleVirtualCamera: String {
        Localization.string(
            "guide.recovery.toggle_virtual_camera",
            table: "Onboarding",
            defaultValue:
                "In Camera Extensions, turn the switch next to FaceNow off, then back on. Return to FaceNow to check the connection automatically."
        )
    }

    /// Guides recovery after macOS enables the extension without publishing its camera device.
    static var guideExplanationPublicationRecovery: String {
        Localization.string(
            "guide.explanation.publication_recovery",
            table: "Onboarding",
            defaultValue:
                "Click “Open System Settings” in the bottom-right corner. In Camera Extensions, turn the switch next to FaceNow off, then back on. Return to FaceNow to check the connection automatically."
        )
    }

    /// Explains a setup condition and the action needed to continue.
    static var guideExplanationChecking: String {
        Localization.string(
            "guide.explanation.checking",
            table: "Onboarding",
            defaultValue:
                "FaceNow is checking whether Virtual Camera is installed, enabled, and available to video calling apps.\n\nPlease wait. This page will update automatically when the check finishes."
        )
    }

    /// Explains a setup condition and the action needed to continue.
    static var guideExplanationWaiting: String {
        Localization.string(
            "guide.explanation.waiting",
            table: "Onboarding",
            defaultValue:
                "Please wait for macOS to finish. If a permission dialog appears, follow its instructions. FaceNow will check the result automatically."
        )
    }

    /// Explains a setup condition and the action needed to continue.
    static var guideExplanationEnableExtension: String {
        Localization.string(
            "guide.explanation.enable_extension",
            table: "Onboarding",
            defaultValue:
                "Click “Open System Settings” in the bottom-right corner, turn on the switch next to FaceNow, then click “Done”. Return to FaceNow to check the connection automatically."
        )
    }

    /// Explains a setup condition and the action needed to continue.
    static var guideExplanationRequestAccess: String {
        Localization.string(
            "guide.explanation.request_access",
            table: "Onboarding",
            defaultValue:
                "Click “Allow Camera Access” in the bottom-right corner, then choose Allow in the permission dialog."
        )
    }

    /// Explains a setup condition and the action needed to continue.
    static var guideExplanationConnectCamera: String {
        Localization.string(
            "guide.explanation.connect_camera",
            table: "Onboarding",
            defaultValue:
                "Make sure your camera is connected and available, then check again using the button in the bottom-right corner."
        )
    }

    /// Explains a setup condition and the action needed to continue.
    static var guideExplanationMoveApplication: String {
        Localization.string(
            "guide.explanation.move_application",
            table: "Onboarding",
            defaultValue:
                "Click “Show in Finder” to locate the running FaceNow app. Move it to /Applications, quit this copy, then open FaceNow from Applications."
        )
    }

    /// Explains a setup condition and the action needed to continue.
    static var guideExplanationRestartApplication: String {
        Localization.string(
            "guide.explanation.restart_application",
            table: "Onboarding",
            defaultValue:
                "Click “Restart FaceNow” in the bottom-right corner to reopen the app and refresh its camera connection."
        )
    }

    /// Explains a setup condition and the action needed to continue.
    static var guideExplanationNotInstalled: String {
        Localization.string(
            "guide.explanation.not_installed",
            table: "Onboarding",
            defaultValue:
                "Virtual Camera has not been installed on this Mac. It sends your FaceNow look to video calling apps as a camera input."
        )
    }

    /// Explains a setup condition and the action needed to continue.
    static var guideExplanationVersionMismatch: String {
        Localization.string(
            "guide.explanation.version_mismatch",
            table: "Onboarding",
            defaultValue:
                "The installed Virtual Camera belongs to a different FaceNow build. Reinstall it to remove the previous extension and install the version included with this app."
        )
    }

    /// Explains how to repeat discovery without reinstalling the virtual camera.
    static var guideExplanationCheckAgain: String {
        Localization.string(
            "guide.explanation.check_again",
            table: "Onboarding",
            defaultValue:
                "Click “Check Again” in the bottom-right corner to recheck the camera. FaceNow will update this page with the result."
        )
    }

    /// Labels the previous image control in the setup walkthrough.
    static var previousGuideImage: String {
        Localization.string(
            "guide.previous_image",
            table: "Onboarding",
            defaultValue: "Previous Guide Image"
        )
    }

    /// Labels the next image control in the setup walkthrough.
    static var nextGuideImage: String {
        Localization.string(
            "guide.next_image",
            table: "Onboarding",
            defaultValue: "Next Guide Image"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeAllowCameraAccess: String {
        Localization.string(
            "notice.allow_camera_access",
            table: "Onboarding",
            defaultValue: "Allow Camera Access"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeOpenSystemSettings: String {
        Localization.string(
            "notice.open_system_settings",
            table: "Onboarding",
            defaultValue: "Open System Settings"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeChooseCamera: String {
        Localization.string(
            "notice.choose_camera",
            table: "Onboarding",
            defaultValue: "Choose Camera"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var install: String {
        Localization.string(
            "action.install",
            table: "Common",
            defaultValue: "Install"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var update: String {
        Localization.string(
            "action.update",
            table: "Common",
            defaultValue: "Update"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeCheckAgain: String {
        Localization.string(
            "notice.check_again",
            table: "Onboarding",
            defaultValue: "Check Again"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var retry: String {
        Localization.string(
            "action.retry",
            table: "Common",
            defaultValue: "Retry"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeShowInFinder: String {
        Localization.string(
            "notice.show_in_finder",
            table: "Onboarding",
            defaultValue: "Show in Finder"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeRestartFaceNow: String {
        Localization.string(
            "notice.restart_facenow",
            table: "Onboarding",
            defaultValue: "Restart FaceNow"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeFaceNowNeedsAccessToYourCamera: String {
        Localization.string(
            "notice.facenow_needs_access_to_your_camera",
            table: "Onboarding",
            defaultValue: "FaceNow needs access to your camera."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeCameraAccessIsOffForFaceNow: String {
        Localization.string(
            "notice.camera_access_is_off_for_facenow",
            table: "Onboarding",
            defaultValue: "Camera access is off for FaceNow."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeCameraAccessIsRestrictedByMacOSOrYourDevice: String {
        Localization.string(
            "notice.camera_access_is_restricted_by_macos_or_your_device",
            table: "Onboarding",
            defaultValue: "Camera access is restricted by macOS or your device administrator."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeNoCameraDetectedConnectACameraToContinue: String {
        Localization.string(
            "notice.no_camera_detected_connect_a_camera_to_continue",
            table: "Onboarding",
            defaultValue: "No camera detected. Connect a camera to continue."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeYourSelectedCameraIsDisconnected: String {
        Localization.string(
            "notice.your_selected_camera_is_disconnected",
            table: "Onboarding",
            defaultValue: "Your selected camera is disconnected."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeInstallVirtualCameraToUseFaceNowInVideoCalls: String {
        Localization.string(
            "notice.install_virtual_camera_to_use_facenow_in_video_calls",
            table: "Onboarding",
            defaultValue: "Install Virtual Camera to use FaceNow in video calls."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeVirtualCameraIsTurnedOff: String {
        Localization.string(
            "notice.virtual_camera_is_turned_off",
            table: "Onboarding",
            defaultValue: "Virtual Camera is turned off."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeAllowTheFaceNowCameraExtensionInSystemSettings: String {
        Localization.string(
            "notice.allow_the_facenow_camera_extension_in_system_settings",
            table: "Onboarding",
            defaultValue: "Allow the FaceNow camera extension in System Settings."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeRestartFaceNowToRefreshTheCameraConnection: String {
        Localization.string(
            "notice.restart_facenow_to_refresh_the_camera_connection",
            table: "Onboarding",
            defaultValue: "Restart FaceNow to refresh the camera connection."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeMoveFaceNowToApplicationsToSetUpVirtualCamera: String {
        Localization.string(
            "notice.move_facenow_to_applications_to_set_up_virtual_camera",
            table: "Onboarding",
            defaultValue: "Move FaceNow to /Applications and open it from there before installing Virtual Camera."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeWaiting: String {
        Localization.string(
            "notice.waiting",
            table: "Onboarding",
            defaultValue: "Waiting…"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeAllowCameraAccessInTheMacOSPermissionDialog: String {
        Localization.string(
            "notice.allow_camera_access_in_the_macos_permission_dialog",
            table: "Onboarding",
            defaultValue: "Allow camera access in the permission dialog."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeInstalling: String {
        Localization.string(
            "notice.installing",
            table: "Onboarding",
            defaultValue: "Installing…"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeInstallingVirtualCamera: String {
        Localization.string(
            "notice.installing_virtual_camera",
            table: "Onboarding",
            defaultValue: "Installing Virtual Camera…"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeRemoving: String {
        Localization.string(
            "notice.removing",
            table: "Onboarding",
            defaultValue: "Removing…"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeRemovingVirtualCamera: String {
        Localization.string(
            "notice.removing_virtual_camera",
            table: "Onboarding",
            defaultValue: "Removing Virtual Camera…"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeChecking: String {
        Localization.string(
            "notice.checking",
            table: "Onboarding",
            defaultValue: "Checking…"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeCheckingAvailableCameras: String {
        Localization.string(
            "notice.checking_available_cameras",
            table: "Onboarding",
            defaultValue: "Checking available cameras…"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeCheckingTheVirtualCameraConnection: String {
        Localization.string(
            "notice.checking_the_virtual_camera_connection",
            table: "Onboarding",
            defaultValue: "Checking the Virtual Camera connection…"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeCheckingVirtualCameraStatus: String {
        Localization.string(
            "notice.checking_virtual_camera_status",
            table: "Onboarding",
            defaultValue: "Checking Virtual Camera status…"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideGetReadyToUseFaceNow: String {
        Localization.string(
            "guide.get_ready_to_use_facenow",
            table: "Onboarding",
            defaultValue: "Get ready to use FaceNow"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideGetReadyForUse: String {
        Localization.string(
            "guide.get_ready_for_use",
            table: "Onboarding",
            defaultValue: "Get Ready For Use"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideCloseSetupGuide: String {
        Localization.string(
            "guide.close_setup_guide",
            table: "Onboarding",
            defaultValue: "Close setup guide"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var back: String {
        Localization.string(
            "action.back",
            table: "Common",
            defaultValue: "Back"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideReviewCameraRestrictions: String {
        Localization.string(
            "guide.review_camera_restrictions",
            table: "Onboarding",
            defaultValue: "Review Camera Restrictions"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideCameraAccessIsRestrictedByMacOSOrADevice: String {
        Localization.string(
            "guide.camera_access_is_restricted_by_macos_or_a_device",
            table: "Onboarding",
            defaultValue: "Camera access is restricted by macOS or a device-management policy."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideAskYourAdministrator: String {
        Localization.string(
            "guide.ask_your_administrator",
            table: "Onboarding",
            defaultValue: "Ask Your Administrator"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideIfThisMacIsManagedAskYourAdministratorTo: String {
        Localization.string(
            "guide.if_this_mac_is_managed_ask_your_administrator_to",
            table: "Onboarding",
            defaultValue:
                "If this Mac is managed, ask your administrator to allow camera access for FaceNow. You can review the current permissions in System Settings."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideClickOpenSystemSettingsInTheBottomRightCorner: String {
        Localization.string(
            "guide.click_open_system_settings_in_the_bottom_right_corner",
            table: "Onboarding",
            defaultValue: "Click “Open System Settings” in the bottom-right corner."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideAllowFaceNow: String {
        Localization.string(
            "guide.allow_facenow",
            table: "Onboarding",
            defaultValue: "Allow FaceNow"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideTurnOnTheSwitchNextToFaceNowUnderPrivacy: String {
        Localization.string(
            "guide.turn_on_the_switch_next_to_facenow_under_privacy",
            table: "Onboarding",
            defaultValue: "Turn on the switch next to FaceNow under Privacy & Security → Camera."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideRequestCameraAccess: String {
        Localization.string(
            "guide.request_camera_access",
            table: "Onboarding",
            defaultValue: "Request Camera Access"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideClickAllowCameraAccessInTheBottomRightCorner: String {
        Localization.string(
            "guide.click_allow_camera_access_in_the_bottom_right_corner",
            table: "Onboarding",
            defaultValue: "Click “Allow Camera Access” in the bottom-right corner."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideChooseAllowInTheMacOSPermissionDialog: String {
        Localization.string(
            "guide.choose_allow_in_the_macos_permission_dialog",
            table: "Onboarding",
            defaultValue: "Choose Allow in the permission dialog."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideEnableVirtualCamera: String {
        Localization.string(
            "guide.enable_virtual_camera",
            table: "Onboarding",
            defaultValue: "Enable Virtual Camera"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideFaceNowUsesAVirtualCameraToBringYourChosen: String {
        Localization.string(
            "guide.facenow_uses_a_virtual_camera_to_bring_your_chosen",
            table: "Onboarding",
            defaultValue: "FaceNow uses a virtual camera to bring your chosen look into video calls."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideTurnOnTheSwitchNextToFaceNowUnderLogin: String {
        Localization.string(
            "guide.turn_on_the_switch_next_to_facenow_under_login",
            table: "Onboarding",
            defaultValue:
                "In Camera Extensions, turn on the switch next to FaceNow, then click “Done”."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideAllowTheFaceNowSystemExtensionUnderPrivacySecurityThen: String {
        Localization.string(
            "guide.allow_the_facenow_system_extension_under_privacy_security_then",
            table: "Onboarding",
            defaultValue: "Allow the FaceNow system extension under Privacy & Security, then return to FaceNow."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideInstallVirtualCamera: String {
        Localization.string(
            "guide.install_virtual_camera",
            table: "Onboarding",
            defaultValue: "Install Virtual Camera"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideClickOpenSystemSettingsInTheMacOSDialog: String {
        Localization.string(
            "guide.click_open_system_settings_in_the_macos_dialog",
            table: "Onboarding",
            defaultValue: "Click “Open System Settings” in the macOS dialog."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideEnableFaceNow: String {
        Localization.string(
            "guide.enable_facenow",
            table: "Onboarding",
            defaultValue: "Enable FaceNow"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideUseFaceNowInVideoCalls: String {
        Localization.string(
            "guide.use_facenow_in_video_calls",
            table: "Onboarding",
            defaultValue: "Bring Your Look To Video Calls"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideStartYourCamera: String {
        Localization.string(
            "guide.start_your_camera",
            table: "Onboarding",
            defaultValue: "Start Your Camera"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideReturnToFaceNowClickStartCameraAndChooseYour: String {
        Localization.string(
            "guide.return_to_facenow_click_start_camera_and_choose_your",
            table: "Onboarding",
            defaultValue: "Return to FaceNow, click “Start Camera”, and choose your look."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideFaceNowSetupIllustration: String {
        Localization.string(
            "guide.facenow_setup_illustration",
            table: "Onboarding",
            defaultValue: "FaceNow setup illustration"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideCameraExtensionPermissionPromptChooseOpenSystemSettings: String {
        Localization.string(
            "guide.camera_extension_permission_prompt_choose_open_system_settings",
            table: "Onboarding",
            defaultValue: "Camera extension permission prompt. Choose Open System Settings."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideCameraExtensionsEnableFaceNowThenClickDone: String {
        Localization.string(
            "guide.camera_extensions_enable_facenow_then_click_done",
            table: "Onboarding",
            defaultValue: "Camera Extensions. Enable FaceNow, then click Done."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideTurnOnTheSwitchNextToFaceNowThenClick: String {
        Localization.string(
            "guide.turn_on_the_switch_next_to_facenow_then_click",
            table: "Onboarding",
            defaultValue: "Turn on the switch next to FaceNow, then click “Done”."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingLandingView.swift.
    static var landingStartCamera: String {
        Localization.string(
            "landing.start_camera",
            table: "Onboarding",
            defaultValue: "Start Camera"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingLandingView.swift.
    static var landingStarting: String {
        Localization.string(
            "landing.starting",
            table: "Onboarding",
            defaultValue: "Starting…"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingLandingView.swift.
    static var on: String {
        Localization.string(
            "state.on",
            table: "Common",
            defaultValue: "On"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingLandingView.swift.
    static var off: String {
        Localization.string(
            "state.off",
            table: "Common",
            defaultValue: "Off"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingLandingView.swift.
    static var termsOfUse: String {
        Localization.string(
            "legal.terms_of_use",
            table: "Common",
            defaultValue: "Terms of Use"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingLandingView.swift.
    static var privacyPolicy: String {
        Localization.string(
            "legal.privacy_policy",
            table: "Common",
            defaultValue: "Privacy Policy"
        )
    }

    /// Names the virtual camera in the guide and device menu.
    static var virtualCamera: String {
        Localization.string(
            "camera.virtual_camera",
            table: "Common",
            defaultValue: "Virtual Camera"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/ViewModel/OnboardingFlowViewModel.swift.
    static var guideCameraAccessIsRestricted: String {
        Localization.string(
            "guide.camera_access_is_restricted",
            table: "Onboarding",
            defaultValue: "Camera Access Is Restricted"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/ViewModel/OnboardingFlowViewModel.swift.
    static var guideReviewTheCameraRestrictionsOnThisMacBeforeContinuing: String {
        Localization.string(
            "guide.review_the_camera_restrictions_on_this_mac_before_continuing",
            table: "Onboarding",
            defaultValue: "Review the camera restrictions on this Mac before continuing."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/ViewModel/OnboardingFlowViewModel.swift.
    static var guideFaceNowTurnsYourMovementsIntoYourChosenLookIn: String {
        Localization.string(
            "guide.facenow_turns_your_movements_into_your_chosen_look_in",
            table: "Onboarding",
            defaultValue:
                "FaceNow uses your camera feed as input for real-time generation, mapping your expressions and movements to your selected appearance."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/ViewModel/OnboardingFlowViewModel.swift.
    static var continueAction: String {
        Localization.string(
            "action.continue",
            table: "Common",
            defaultValue: "Continue"
        )
    }

    /// Displayed text in Modules/FNOnboarding/OnboardingRepository.swift.
    static var contentCameraAccess: String {
        Localization.string(
            "content.camera_access",
            table: "Onboarding",
            defaultValue: "Camera Access"
        )
    }

    /// Displayed text in Modules/FNOnboarding/OnboardingRepository.swift.
    static var contentVideoCalls: String {
        Localization.string(
            "content.video_calls",
            table: "Onboarding",
            defaultValue: "Video Calls"
        )
    }

    /// Displayed text in Modules/FNOnboarding/OnboardingRepository.swift.
    static var contentBringYourNewLookIntoVideoCallingApps: String {
        Localization.string(
            "content.bring_your_new_look_into_video_calling_apps",
            table: "Onboarding",
            defaultValue: "Bringing Your New Look into Video Calls"
        )
    }

    /// Displayed text in Modules/FNOnboarding/OnboardingRepository.swift.
    static var contentWeAccessYourCameraInAccordanceWithOurTerms: String {
        Localization.format(
            "content.we_access_your_camera_in_accordance_with_our_terms",
            table: "Onboarding",
            defaultValue: "We access your camera and, when enabled, microphone in accordance with our %1$@ and %2$@.",
            arguments: [termsOfUse, privacyPolicy]
        )
    }

    /// Displayed text in Modules/FNOnboarding/OnboardingRepository.swift.
    static var contentCopyright2026XMAXAIPTELTDAllRightsReserved: String {
        Localization.string(
            "content.copyright_2026_xmax_ai_pte_ltd_all_rights_reserved",
            table: "Onboarding",
            defaultValue: "Copyright © 2026 XMAX.AI PTE.LTD. All rights reserved."
        )
    }

    /// Localized page text; preserve all placeholders and product names.
    static var activateCamera: String {
        Localization.string(
            "notice.activate_camera",
            table: "Onboarding",
            defaultValue: "Activate Virtual Camera to finish setup."
        )
    }

    /// Localized page text; preserve all placeholders and product names.
    static var completed: String {
        Localization.string("step.state.completed", table: "Onboarding", defaultValue: "completed")
    }

    /// Localized page text; preserve all placeholders and product names.
    static var currentStep: String {
        Localization.string("step.state.currentStep", table: "Onboarding", defaultValue: "current step")
    }

    /// Localized page text; preserve all placeholders and product names.
    static var upcoming: String {
        Localization.string("step.state.upcoming", table: "Onboarding", defaultValue: "upcoming")
    }

    /// Explains the completed camera stage during a manual review.
    static var cameraStepReady: String {
        Localization.string(
            "guide.camera_step_ready",
            table: "Onboarding",
            defaultValue: "Camera access is ready. Continue setup."
        )
    }

    /// Explains the completed output stage during a manual review.
    static var virtualCameraStepReady: String {
        Localization.string(
            "guide.virtual_camera_step_ready",
            table: "Onboarding",
            defaultValue: "Virtual Camera is ready. Continue setup."
        )
    }

    /// Third-step video-call guidance, shared with the module String Catalog.
    static var videoCallsSubtitle: String {
        Localization.string(
            "guide.video_calls.subtitle",
            table: "Onboarding",
            defaultValue: "Choose FaceNow as your camera to bring your new look into the conversation."
        )
    }

    /// Third-step video-call guidance, shared with the module String Catalog.
    static var videoCallsSelectTitle: String {
        Localization.string(
            "guide.video_calls.select_title",
            table: "Onboarding",
            defaultValue: "Select FaceNow As Your Camera"
        )
    }

    /// Third-step video-call guidance, shared with the module String Catalog.
    static var videoCallsKeepRunningTitle: String {
        Localization.string(
            "guide.video_calls.keep_running_title",
            table: "Onboarding",
            defaultValue: "Keep FaceNow Running"
        )
    }

    /// Third-step video-call guidance, shared with the module String Catalog.
    static var videoCallsKeepRunningDetail: String {
        Localization.string(
            "guide.video_calls.keep_running_detail",
            table: "Onboarding",
            defaultValue:
                "Turn on video in your call and keep FaceNow open while you talk. If the camera is missing, reopen your video calling app."
        )
    }

    /// Requests system permission without starting audio capture.
    static var allowMicrophoneAccess: String {
        Localization.string(
            "guide.allow_microphone_access",
            table: "Onboarding",
            defaultValue: "Allow Microphone Access"
        )
    }

    /// Explains optional physical microphone input.
    static var microphoneIntroduction: String {
        Localization.string(
            "guide.microphone_introduction",
            table: "Onboarding",
            defaultValue:
                "Allow FaceNow to capture your voice. You can choose an input device or turn the microphone off at any time."
        )
    }

    /// Identifies microphone access restricted by system policy.
    static var microphoneRestrictedTitle: String {
        Localization.string(
            "guide.microphone_restricted_title",
            table: "Onboarding",
            defaultValue: "Microphone Access Is Restricted"
        )
    }

    /// Explains restricted microphone access and optional continuation.
    static var microphoneRestrictedDetail: String {
        Localization.string(
            "guide.microphone_restricted_detail",
            table: "Onboarding",
            defaultValue:
                "Microphone access is restricted by macOS or your administrator. You can skip this step and continue with video."
        )
    }

    /// Explains how to enable a previously denied microphone permission.
    static var microphoneSettingsDetail: String {
        Localization.string(
            "guide.microphone_settings_detail",
            table: "Onboarding",
            defaultValue: "In System Settings → Privacy & Security → Microphone, enable FaceNow, then return here."
        )
    }

    /// Explains the explicit microphone permission prompt.
    static var microphoneRequestDetail: String {
        Localization.string(
            "guide.microphone_request_detail",
            table: "Onboarding",
            defaultValue: "Click “Allow Microphone Access”, then choose Allow in the permission dialog."
        )
    }

    /// Confirms permission without claiming audio capture has started.
    static var microphoneStepReady: String {
        Localization.string(
            "guide.microphone_step_ready",
            table: "Onboarding",
            defaultValue: "Microphone access is ready. Continue setup."
        )
    }

    /// Identifies an explicitly deferred optional step for accessibility.
    static var skipped: String {
        Localization.string(
            "step.state.skipped",
            table: "Onboarding",
            defaultValue: "skipped"
        )
    }

    /// Names the optional generated-audio output step.
    static var virtualMicrophone: String {
        Localization.string(
            "guide.virtual_microphone",
            table: "Onboarding",
            defaultValue: "Virtual Microphone"
        )
    }

    /// Introduces explicit installation and enabling of audio output.
    static var setupVirtualMicrophone: String {
        Localization.string(
            "guide.setup_virtual_microphone",
            table: "Onboarding",
            defaultValue: "Set Up Virtual Microphone"
        )
    }

    /// Explains optional synchronized audio output for video calls.
    static var virtualMicrophoneIntroduction: String {
        Localization.string(
            "guide.virtual_microphone_introduction",
            table: "Onboarding",
            defaultValue:
                "Enable Virtual Microphone to keep audio and video in sync during video calls. You can skip this step and set it up later."
        )
    }

    /// Confirms device readiness without claiming audio capture or generation has started.
    static var virtualMicrophoneStepReady: String {
        Localization.string(
            "guide.virtual_microphone_step_ready",
            table: "Onboarding",
            defaultValue: "Virtual Microphone is enabled. Continue setup."
        )
    }

    /// Adds microphone selection only when virtual audio output is enabled.
    static var videoCallsMicrophoneTitle: String {
        Localization.string(
            "guide.video_calls.microphone_title",
            table: "Onboarding",
            defaultValue: "Select FaceNow as your microphone"
        )
    }

    /// Explains the next action using the actual application, camera, or button name.
    static func guideExplanationInstall(
        action: String
    ) -> String {
        Localization.format(
            "guide.explanation.install",
            table: "Onboarding",
            defaultValue:
                "Click “%1$@” in the bottom-right corner to let macOS install and enable Virtual Camera. If macOS asks for approval, follow the system dialog.",
            arguments: [action]
        )
    }

    /// Explains the next action using the actual application, camera, or button name.
    static func guideExplanationRetry(
        action: String
    ) -> String {
        Localization.format(
            "guide.explanation.retry",
            table: "Onboarding",
            defaultValue:
                "Click “%1$@” in the bottom-right corner to retry the operation. FaceNow will update this page with the result or the next required step.",
            arguments: [action]
        )
    }

    /// Localized page text; preserve all placeholders and product names.
    static func stepAccessibility(
        title: String,
        state: String
    ) -> String {
        Localization.format(
            "step.accessibility",
            table: "Onboarding",
            defaultValue: "%1$@, %2$@",
            arguments: [title, state]
        )
    }

    /// Keeps the instruction aligned with the current localized primary action.
    static func clickPrimaryButton(
        _ title: String
    ) -> String {
        Localization.format(
            "guide.click_primary_button",
            table: "Onboarding",
            defaultValue: "Click “%@” in the bottom-right corner.",
            arguments: [title]
        )
    }

    /// Complete message; preserve the camera or application name placeholder.
    static func videoCallsChooseCamera(
        camera: String
    ) -> String {
        Localization.format(
            "guide.video_calls.choose_camera",
            table: "Onboarding",
            defaultValue: "In your video calling app, open the camera menu and choose “%@”.",
            arguments: [camera]
        )
    }

    /// Complete message; preserve the camera or application name placeholder.
    static func videoCallsLarkCaption(
        camera: String
    ) -> String {
        Localization.format(
            "guide.video_calls.lark_caption",
            table: "Onboarding",
            defaultValue: "Open the camera menu beside the video button and select “%@”.",
            arguments: [camera]
        )
    }

    /// Complete message; preserve the camera or application name placeholder.
    static func videoCallsTencentCaption(
        camera: String
    ) -> String {
        Localization.format(
            "guide.video_calls.tencent_caption",
            table: "Onboarding",
            defaultValue: "Click the arrow next to the video button and choose “%@” as your camera.",
            arguments: [camera]
        )
    }

    /// Complete message; preserve the camera or application name placeholder.
    static func videoCallsWeChatCaption(
        camera: String
    ) -> String {
        Localization.format(
            "guide.video_calls.wechat_caption",
            table: "Onboarding",
            defaultValue: "During a video call, open the camera menu and select “%@”.",
            arguments: [camera]
        )
    }

    /// Complete message; preserve the camera or application name placeholder.
    static func videoCallsShowExample(
        app: String
    ) -> String {
        Localization.format(
            "guide.video_calls.show_example",
            table: "Onboarding",
            defaultValue: "Show %@ camera example",
            arguments: [app]
        )
    }

    /// Explains enabling an already published virtual input.
    static func virtualMicrophoneEnableDetail(
        microphone: String
    ) -> String {
        Localization.format(
            "guide.virtual_microphone_enable_detail",
            table: "Onboarding",
            defaultValue: "The device is available. Click Enable to output synchronized audio through %1$@.",
            arguments: [microphone]
        )
    }

    /// Names the stable virtual audio input to select in calling software.
    static func videoCallsMicrophoneDetail(
        microphone: String
    ) -> String {
        Localization.format(
            "guide.video_calls.microphone_detail",
            table: "Onboarding",
            defaultValue:
                "In your calling app’s microphone menu, select “%1$@” to keep audio in sync with your FaceNow video.",
            arguments: [microphone]
        )
    }

}
