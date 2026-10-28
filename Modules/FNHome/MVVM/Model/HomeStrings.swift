//
//  HomeStrings.swift
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
enum HomeStrings {

    /// The footer documentation entry awaiting its destination URL.
    static var troubleshooting: String {
        Localization.string(
            "home.troubleshooting",
            table: "Home",
            defaultValue: "TroubleShooting"
        )
    }

    /// The public version label; the parameter is the app's marketing version.
    static func version(
        _ value: String
    ) -> String {
        Localization.format(
            "home.version",
            table: "Home",
            defaultValue: "V%@",
            arguments: [value]
        )
    }

    /// Displayed text in Modules/FNHome/HomeViewController.swift.
    static var homeCouldnTRestartFaceNowQuitAndReopenTheApp: String {
        Localization.string(
            "home.couldn_t_restart_facenow_quit_and_reopen_the_app",
            table: "Home",
            defaultValue: "Couldn’t restart FaceNow. Quit and reopen the app to continue."
        )
    }

    /// Displayed text in Modules/FNHome/HomeViewController.swift.
    static var homeSignedInSuccessfully: String {
        Localization.string(
            "home.signed_in_successfully",
            table: "Home",
            defaultValue: "Signed in successfully"
        )
    }

    /// Displayed text in Modules/FNHome/MVVM/View/HomeCameraControlsView.swift.
    static var homeHowToUseFaceNowInVideoCalls: String {
        Localization.string(
            "home.how_to_use_facenow_in_video_calls",
            table: "Home",
            defaultValue: "How to use FaceNow in video calls"
        )
    }

    /// Displayed text in Modules/FNHome/MVVM/View/HomeCameraControlsView.swift.
    static var homeOpenFaceNowSetupGuide: String {
        Localization.string(
            "home.open_facenow_setup_guide",
            table: "Home",
            defaultValue: "Open FaceNow setup guide"
        )
    }

    /// Displayed text in Modules/FNHome/MVVM/View/HomeCameraControlsView.swift.
    static var homeSelectCamera: String {
        Localization.string(
            "home.select_camera",
            table: "Home",
            defaultValue: "Select Camera"
        )
    }

    /// Displayed text in Modules/FNHome/MVVM/View/HomeCameraControlsView.swift.
    static var virtualCamera: String {
        Localization.string(
            "camera.virtual_camera",
            table: "Common",
            defaultValue: "Virtual Camera"
        )
    }

    /// Displayed text in Modules/FNHome/MVVM/View/HomeCameraControlsView.swift.
    static var homeNoCamerasFound: String {
        Localization.string(
            "home.no_cameras_found",
            table: "Home",
            defaultValue: "No cameras found"
        )
    }

    /// Displayed text in Modules/FNHome/MVVM/View/HomeFooterView.swift.
    static var homeWebsite: String {
        Localization.string(
            "home.website",
            table: "Home",
            defaultValue: "Website"
        )
    }

    /// Displayed text in Modules/FNHome/MVVM/View/HomeFooterView.swift.
    static var homeFeedback: String {
        Localization.string(
            "home.feedback",
            table: "Home",
            defaultValue: "Feedback"
        )
    }

    /// Displayed text in Modules/FNHome/MVVM/View/HomeFooterView.swift.
    static var homeAPIPlatform: String {
        Localization.string(
            "home.api_platform",
            table: "Home",
            defaultValue: "API Platform"
        )
    }

    /// Displayed text in Modules/FNHome/MVVM/View/HomeFooterView.swift.
    static var homeScanWithWeChatToFollowUs: String {
        Localization.string(
            "home.scan_with_wechat_to_follow_us",
            table: "Home",
            defaultValue: "Scan with WeChat to follow us"
        )
    }

}
