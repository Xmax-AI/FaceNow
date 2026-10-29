//
//  OnboardingStrings.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
#if canImport(Localization)
    import Localization
#endif

/// Provides module-owned English defaults and stable localization keys for page presentation.
enum OnboardingStrings {

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
    static var guideReinstallVirtualCamera: String {
        Localization.string(
            "guide.reinstall_virtual_camera",
            table: "Onboarding",
            defaultValue: "Reinstall Virtual Camera"
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
                "macOS couldn’t validate the camera extension. If this continues, reinstall the latest signed version of FaceNow."
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
                "Click “Open System Settings” in the bottom-right corner and remove the previous FaceNow camera extension. Follow any macOS request to restart, then reopen FaceNow. Setup will continue after removal is confirmed."
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
                "Click “Open System Settings” in the bottom-right corner. Under General → Login Items & Extensions → Camera Extensions, turn FaceNow off, then back on. Return to FaceNow to check the connection automatically."
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
                "Click “Open System Settings” in the bottom-right corner, then enable the FaceNow camera extension. Return to FaceNow when you are done."
        )
    }

    /// Explains a setup condition and the action needed to continue.
    static var guideExplanationRequestAccess: String {
        Localization.string(
            "guide.explanation.request_access",
            table: "Onboarding",
            defaultValue:
                "Click “Allow Camera Access” in the bottom-right corner, then choose Allow in the macOS permission dialog."
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
                "Click “Show in Finder” to locate FaceNow. Move it to your Applications folder, then reopen it and try again."
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

    /// Explains the next action using the actual application, camera, or button name.
    static func guideExplanationVideoCalls(
        app: String,
        camera: String
    ) -> String {
        Localization.format(
            "guide.explanation.video_calls",
            table: "Onboarding",
            defaultValue:
                "In %1$@, open the camera settings and choose “%2$@” as your video input.\n\nThis lets the app receive your FaceNow look instead of the original camera feed. If the camera is missing from the list, reopen the video calling app after enabling Virtual Camera.",
            arguments: [app, camera]
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
    static var noticeViewHelp: String {
        Localization.string(
            "notice.view_help",
            table: "Onboarding",
            defaultValue: "View Help"
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
    static var noticeUpdateVirtualCameraToUseThisVersionOfFaceNow: String {
        Localization.string(
            "notice.update_virtual_camera_to_use_this_version_of_facenow",
            table: "Onboarding",
            defaultValue: "Update Virtual Camera to use this version of FaceNow."
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
    static var noticeVirtualCameraIsnTReadyYetCheckAgain: String {
        Localization.string(
            "notice.virtual_camera_isn_t_ready_yet_check_again",
            table: "Onboarding",
            defaultValue: "Virtual Camera isn’t ready yet. Check again."
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
            defaultValue: "Move FaceNow to Applications to set up Virtual Camera."
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
            defaultValue: "Allow camera access in the macOS permission dialog."
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
    static var noticeUpdating: String {
        Localization.string(
            "notice.updating",
            table: "Onboarding",
            defaultValue: "Updating…"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeUpdatingVirtualCamera: String {
        Localization.string(
            "notice.updating_virtual_camera",
            table: "Onboarding",
            defaultValue: "Updating Virtual Camera…"
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

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeVirtualCameraCouldnTBeRemovedAutomaticallyRemoveIt: String {
        Localization.string(
            "notice.virtual_camera_couldn_t_be_removed_automatically_remove_it",
            table: "Onboarding",
            defaultValue: "Virtual Camera couldn’t be removed automatically. Remove it in System Settings."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeCouldnTInstallVirtualCameraTryAgain: String {
        Localization.string(
            "notice.couldn_t_install_virtual_camera_try_again",
            table: "Onboarding",
            defaultValue: "Couldn’t install Virtual Camera. Try again."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeCouldnTUpdateVirtualCameraTryAgain: String {
        Localization.string(
            "notice.couldn_t_update_virtual_camera_try_again",
            table: "Onboarding",
            defaultValue: "Couldn’t update Virtual Camera. Try again."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeCouldnTRemoveVirtualCameraTryAgain: String {
        Localization.string(
            "notice.couldn_t_remove_virtual_camera_try_again",
            table: "Onboarding",
            defaultValue: "Couldn’t remove Virtual Camera. Try again."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeCouldnTConnectToVirtualCameraTryAgain: String {
        Localization.string(
            "notice.couldn_t_connect_to_virtual_camera_try_again",
            table: "Onboarding",
            defaultValue: "Couldn’t connect to Virtual Camera. Try again."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeCouldnTCheckAvailableCamerasTryAgain: String {
        Localization.string(
            "notice.couldn_t_check_available_cameras_try_again",
            table: "Onboarding",
            defaultValue: "Couldn’t check available cameras. Try again."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeCouldnTCheckVirtualCameraStatus: String {
        Localization.string(
            "notice.couldn_t_check_virtual_camera_status",
            table: "Onboarding",
            defaultValue: "Couldn’t check Virtual Camera status."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/Model/CameraNoticePresentation.swift.
    static var noticeCouldnTRequestCameraAccessTryAgain: String {
        Localization.string(
            "notice.couldn_t_request_camera_access_try_again",
            table: "Onboarding",
            defaultValue: "Couldn’t request camera access. Try again."
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
    static var guideVideoCallingApp: String {
        Localization.string(
            "guide.video_calling_app",
            table: "Onboarding",
            defaultValue: "Video calling app"
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
    static var guideSetUpLater: String {
        Localization.string(
            "guide.set_up_later",
            table: "Onboarding",
            defaultValue: "Setup Later"
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
            defaultValue: "Choose Allow in the macOS permission dialog."
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
                "Turn on the switch next to FaceNow under Login Items & Extensions → Camera Extensions, then click “Done”."
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
    static var guideClickInstallEnableInTheBottomRightCorner: String {
        Localization.string(
            "guide.click_install_enable_in_the_bottom_right_corner",
            table: "Onboarding",
            defaultValue: "Click “Install & Enable” in the bottom-right corner."
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
    static var guideChooseFaceNowAsYourCameraInYourVideoCalling: String {
        Localization.string(
            "guide.choose_facenow_as_your_camera_in_your_video_calling",
            table: "Onboarding",
            defaultValue: "Choose FaceNow as your camera in your video calling app."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideOpenSettingsVideoInGoogleMeet: String {
        Localization.string(
            "guide.open_settings_video_in_google_meet",
            table: "Onboarding",
            defaultValue: "Open “Settings” → “Video” in Google Meet."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideOpenVideoSettings: String {
        Localization.string(
            "guide.open_video_settings",
            table: "Onboarding",
            defaultValue: "Open Video Settings"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideSelectFaceNowCamera: String {
        Localization.string(
            "guide.select_facenow_camera",
            table: "Onboarding",
            defaultValue: "Select FaceNow Camera"
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
    static var guideFaceNowWouldLikeToAccessTheCamera: String {
        Localization.string(
            "guide.facenow_would_like_to_access_the_camera",
            table: "Onboarding",
            defaultValue: "FaceNow Would Like to Access the Camera"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideFaceNowUsesYourCameraForRealTimeEffects: String {
        Localization.string(
            "guide.facenow_uses_your_camera_for_real_time_effects",
            table: "Onboarding",
            defaultValue: "FaceNow uses your camera for real-time effects."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideChooseAllow: String {
        Localization.string(
            "guide.choose_allow",
            table: "Onboarding",
            defaultValue: "①  Choose Allow"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideCameraPermissionMacOSDialogIllustration: String {
        Localization.string(
            "guide.camera_permission_macos_dialog_illustration",
            table: "Onboarding",
            defaultValue: "Camera permission · macOS dialog illustration"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideSystemSettings: String {
        Localization.string(
            "guide.system_settings",
            table: "Onboarding",
            defaultValue: "System Settings"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideGeneralLoginItemsExtensionsNCameraExtensions: String {
        Localization.string(
            "guide.general_login_items_extensions_ncamera_extensions",
            table: "Onboarding",
            defaultValue: "General → Login Items & Extensions\nCamera Extensions"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guidePrivacySecurityNAllowTheFaceNowSystemExtension: String {
        Localization.string(
            "guide.privacy_security_nallow_the_facenow_system_extension",
            table: "Onboarding",
            defaultValue: "Privacy & Security\nAllow the FaceNow system extension"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideEnableFaceNowDone: String {
        Localization.string(
            "guide.enable_facenow_done",
            table: "Onboarding",
            defaultValue: "②  Enable FaceNow  →  Done"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideReturnToFaceNowReadinessIsCheckedAutomatically: String {
        Localization.string(
            "guide.return_to_facenow_readiness_is_checked_automatically",
            table: "Onboarding",
            defaultValue: "Return to FaceNow. Readiness is checked automatically."
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideCameraNChooseYourVideoInput: String {
        Localization.string(
            "guide.camera_nchoose_your_video_input",
            table: "Onboarding",
            defaultValue: "①  Camera  ⌄\nChoose your video input"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideCameraMenuIllustrationTheLayoutVariesByApp: String {
        Localization.string(
            "guide.camera_menu_illustration_the_layout_varies_by_app",
            table: "Onboarding",
            defaultValue: "Camera-menu illustration · the layout varies by app"
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

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingGuideView.swift.
    static var guideInstallEnable: String {
        Localization.string(
            "guide.install_enable",
            table: "Onboarding",
            defaultValue: "Install & Enable"
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

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingSetupView.swift.
    static var virtualCamera: String {
        Localization.string(
            "camera.virtual_camera",
            table: "Common",
            defaultValue: "Virtual Camera"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingSetupView.swift.
    static var setupRefreshVirtualCamera: String {
        Localization.string(
            "setup.refresh_virtual_camera",
            table: "Onboarding",
            defaultValue: "Refresh Virtual Camera"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingSetupView.swift.
    static var setupRefreshCameraExtensionStatus: String {
        Localization.string(
            "setup.refresh_camera_extension_status",
            table: "Onboarding",
            defaultValue: "Refresh camera extension status"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingSetupView.swift.
    static var remove: String {
        Localization.string(
            "action.remove",
            table: "Common",
            defaultValue: "Remove"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingSetupView.swift.
    static var setupTestVideo: String {
        Localization.string(
            "setup.test_video",
            table: "Onboarding",
            defaultValue: "Test Video"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/View/OnboardingSetupView.swift.
    static var setupStopTestVideo: String {
        Localization.string(
            "setup.stop_test_video",
            table: "Onboarding",
            defaultValue: "Stop Test Video"
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
            defaultValue: "FaceNow turns your movements into your chosen look, in real-time."
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

    /// Displayed text in Modules/FNOnboarding/MVVM/ViewModel/OnboardingFlowViewModel.swift.
    static var guidePreparingVirtualCamera: String {
        Localization.string(
            "guide.preparing_virtual_camera",
            table: "Onboarding",
            defaultValue: "Preparing Virtual Camera…"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/ViewModel/OnboardingFlowViewModel.swift.
    static var guideUpdateVirtualCamera: String {
        Localization.string(
            "guide.update_virtual_camera",
            table: "Onboarding",
            defaultValue: "Update Virtual Camera"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/ViewModel/OnboardingFlowViewModel.swift.
    static var guideDoneLetSGetStarted: String {
        Localization.string(
            "guide.done_let_s_get_started",
            table: "Onboarding",
            defaultValue: "Done, Let's Get Started"
        )
    }

    /// Displayed text in Modules/FNOnboarding/MVVM/ViewModel/OnboardingSetupViewModel.swift.
    static var setupAwaitingApproval: String {
        Localization.string(
            "setup.awaiting_approval",
            table: "Onboarding",
            defaultValue: "Awaiting Approval"
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
            defaultValue: "We access your camera in accordance with our %1$@ and %2$@.",
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

    /// Complete message; preserve all format placeholders.
    static func openVideoSettings(
        app: String
    ) -> String {
        Localization.format(
            "message.open_the_camera_menu_or_video_settings_in_selectedapp",
            table: "Onboarding",
            defaultValue: "Open the camera menu or video settings in %@.",
            arguments: [app]
        )
    }

    /// Complete message; preserve all format placeholders.
    static func chooseCameraNamed(
        name: String
    ) -> String {
        Localization.format(
            "message.choose_virtualcameraconfiguration_devicename_from_the_camera_list",
            table: "Onboarding",
            defaultValue: "Choose “%@” from the camera list.",
            arguments: [name]
        )
    }

    /// Complete message; preserve all format placeholders.
    static func videoSettingsTitle(
        app: String
    ) -> String {
        Localization.format(
            "message.app_video_settings",
            table: "Onboarding",
            defaultValue: "%@ · Video Settings",
            arguments: [app]
        )
    }

    /// Complete message; preserve all format placeholders.
    static func selectedCameraIllustration(
        name: String
    ) -> String {
        Localization.format(
            "message.virtualcameraconfiguration_devicename",
            table: "Onboarding",
            defaultValue: "②  ✓  %@",
            arguments: [name]
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

    /// Explains the completed camera stage during a manual review.
    static var cameraStepReady: String {
        Localization.string(
            "guide.camera_step_ready",
            table: "Onboarding",
            defaultValue: "Camera access is ready. Continue to set up Virtual Camera."
        )
    }

    /// Explains the completed output stage during a manual review.
    static var virtualCameraStepReady: String {
        Localization.string(
            "guide.virtual_camera_step_ready",
            table: "Onboarding",
            defaultValue: "Virtual Camera is ready. Continue to learn how to use FaceNow in video calls."
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

    /// Describes the green virtual-output availability light.
    static var landingVirtualCameraAvailable: String {
        Localization.string(
            "landing.virtual_camera_available",
            table: "Onboarding",
            defaultValue: "Virtual Camera is available."
        )
    }

    /// Describes the amber light during virtual-output preparation.
    static var landingVirtualCameraChecking: String {
        Localization.string(
            "landing.virtual_camera_checking",
            table: "Onboarding",
            defaultValue: "Checking Virtual Camera…"
        )
    }

    /// Describes the neutral light when virtual output is unavailable.
    static var landingVirtualCameraUnavailable: String {
        Localization.string(
            "landing.virtual_camera_unavailable",
            table: "Onboarding",
            defaultValue: "Virtual Camera is unavailable."
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

}
