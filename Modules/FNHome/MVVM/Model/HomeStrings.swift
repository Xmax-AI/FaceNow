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

    /// The home-toolbar entry and popover title for virtual media devices.
    static var virtualDevices: String {
        Localization.string(
            "home.virtual_devices",
            table: "Home",
            defaultValue: "Virtual Devices"
        )
    }

    /// The shared enabled state for virtual camera and microphone rows.
    static var deviceEnabled: String {
        Localization.string(
            "home.device.enabled",
            table: "Home",
            defaultValue: "Enabled"
        )
    }

    /// A device whose current preparation state is being checked.
    static var deviceChecking: String {
        Localization.string(
            "home.device.checking",
            table: "Home",
            defaultValue: "Checking"
        )
    }

    /// A virtual device whose extension or driver is missing.
    static var deviceNotInstalled: String {
        Localization.string(
            "home.device.not_installed",
            table: "Home",
            defaultValue: "Not Installed"
        )
    }

    /// A device that needs approval or another explicit preparation step.
    static var deviceNeedsSetup: String {
        Localization.string(
            "home.device.needs_setup",
            table: "Home",
            defaultValue: "Needs Setup"
        )
    }

    /// An installed microphone driver awaiting system publication.
    static var devicePending: String {
        Localization.string(
            "home.device.pending",
            table: "Home",
            defaultValue: "Pending"
        )
    }

    /// A virtual microphone with a recoverable output failure.
    static var deviceFailed: String {
        Localization.string(
            "home.device.failed",
            table: "Home",
            defaultValue: "Error"
        )
    }

    /// Opens explicit preparation for a single virtual device.
    static var deviceSetup: String {
        Localization.string(
            "home.device.setup",
            table: "Home",
            defaultValue: "Set Up"
        )
    }

    /// Opens instructions for selecting FaceNow devices in meeting applications.
    static var deviceGuide: String {
        Localization.string(
            "home.device.guide",
            table: "Home",
            defaultValue: "View Integration Guide"
        )
    }

    /// The accessibility label for the audio input selector.
    static var selectMicrophone: String {
        Localization.string(
            "home.select_microphone",
            table: "Home",
            defaultValue: "Select Microphone"
        )
    }

    /// The input option that follows the system default microphone.
    static var systemMicrophone: String {
        Localization.string(
            "home.system_microphone",
            table: "Home",
            defaultValue: "System Default Microphone"
        )
    }

    /// The input option disabling audio capture and permission requests.
    static var microphoneOff: String {
        Localization.string(
            "home.microphone_off",
            table: "Home",
            defaultValue: "Microphone Off"
        )
    }

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

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutUs: String {
        Localization.string(
            "about.title",
            table: "Home",
            defaultValue: "About Us"
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutClose: String {
        Localization.string(
            "about.close",
            table: "Home",
            defaultValue: "Close About Us"
        )
    }


    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutModelTitle: String {
        Localization.string(
            "about.model_title",
            table: "Home",
            defaultValue: "Meet Xmax X2.1"
        )
    }


    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutModelIntroduction: String {
        Localization.string(
            "about.model_introduction",
            table: "Home",
            defaultValue: "Xmax X2.1 is a world-leading general-purpose model for real-time interaction and video editing. A single model supports character swapping, virtual try-on, free-form editing, touch interaction, and interactions between virtual elements and the physical world. It generates 1080P video with approximately 200 ms of end-to-end latency and runs on consumer-grade GPUs, reducing reliance on costly data center GPUs. At approximately $0.001667 per second (about $6 per hour), X2.1 delivers these capabilities at a fraction of the cost of comparable solutions, making large-scale commercial deployment economically viable."
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutAdvantagesTitle: String {
        Localization.string(
            "about.advantages_title",
            table: "Home",
            defaultValue: "Built for real-world interaction"
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutLatencyTitle: String {
        Localization.string(
            "about.latency.title",
            table: "Home",
            defaultValue: "Low Latency"
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutLatencyMetric: String {
        Localization.string(
            "about.latency.metric",
            table: "Home",
            defaultValue: "~200 ms"
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutLatencyDetail: String {
        Localization.string(
            "about.latency.detail",
            table: "Home",
            defaultValue: "End-to-end latency is measured in hundreds of milliseconds, ensuring that updates to generation conditions and interaction controls are reflected instantly."
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutCostTitle: String {
        Localization.string(
            "about.cost.title",
            table: "Home",
            defaultValue: "Cost Efficiency"
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutCostMetric: String {
        Localization.string(
            "about.cost.metric",
            table: "Home",
            defaultValue: "~$6 / hour"
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutCostDetail: String {
        Localization.string(
            "about.cost.detail",
            table: "Home",
            defaultValue: "Runs on consumer-grade GPUs, with costs several to tens of times lower than alternative solutions."
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutFidelityTitle: String {
        Localization.string(
            "about.fidelity.title",
            table: "Home",
            defaultValue: "High Fidelity"
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutFidelityMetric: String {
        Localization.string(
            "about.fidelity.metric",
            table: "Home",
            defaultValue: "1080P (24FPS)"
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutFidelityDetail: String {
        Localization.string(
            "about.fidelity.detail",
            table: "Home",
            defaultValue: "Real-time 1080P output preserves fine details and textures, with greater fidelity to the characters, clothing, and style in your reference images."
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutPartnershipTitle: String {
        Localization.string(
            "about.partnership_title",
            table: "Home",
            defaultValue: "Beyond Video Calls"
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutPartnershipDetail: String {
        Localization.string(
            "about.partnership_detail",
            table: "Home",
            defaultValue: "FaceNow brings your new look into video meetings, live streams, and more through a virtual camera. The same technology also powers other commercial experiences, including virtual try-on and interactive applications. If you are exploring a business use case, contact us to discuss a solution together. We can help you shape the experience and provide technical support."
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutContactUs: String {
        Localization.string(
            "about.contact_us",
            table: "Home",
            defaultValue: "Contact Us"
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutContactDetail: String {
        Localization.string(
            "about.contact_detail",
            table: "Home",
            defaultValue: "Let’s build your next real-time experience."
        )
    }

}
