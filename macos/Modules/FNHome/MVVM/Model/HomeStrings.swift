//
//  HomeStrings.swift
//  FaceNow
//

import Foundation
#if canImport(Localization)
    import Localization
#endif

/// Provides module-owned English defaults and stable localization keys for page presentation.
enum HomeStrings {

    static var cameraRotation: String {
        Localization.string(
            "home.camera_rotation",
            table: "Home",
            defaultValue: "Camera rotation"
        )
    }

    static var referenceImages: String {
        Localization.string(
            "home.reference_images",
            table: "Home",
            defaultValue: "Reference images"
        )
    }

    static var closeReferenceImages: String {
        Localization.string(
            "home.reference_images_close",
            table: "Home",
            defaultValue: "Close reference images"
        )
    }

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

    /// Opens the camera-permission guide before displaying device choices.
    static var authorizeCamera: String {
        Localization.string(
            "home.authorize_camera",
            table: "Home",
            defaultValue: "Allow Camera Access"
        )
    }

    /// Opens the microphone-permission guide before displaying device choices.
    static var authorizeMicrophone: String {
        Localization.string(
            "home.authorize_microphone",
            table: "Home",
            defaultValue: "Allow Microphone Access"
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
            defaultValue:
                "Xmax X2.1 is the real-time video generation model behind FaceNow and one of the world's leading general-purpose video editing models. It can reshape character appearances, outfits, and visual styles in real time, combining high-fidelity visuals with the fastest response and lowest usage costs in its class to make real-time video applications commercially viable at scale."
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutAdvantagesTitle: String {
        Localization.string(
            "about.advantages_title",
            table: "Home",
            defaultValue: "Why Xmax?"
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
            defaultValue: "Millisecond Scale"
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutLatencyDetail: String {
        Localization.string(
            "about.latency.detail",
            table: "Home",
            defaultValue:
                "Ultra-low end-to-end latency brings movements and effects to the screen in real time, with fast startup and smooth effect switching."
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutCostTitle: String {
        Localization.string(
            "about.cost.title",
            table: "Home",
            defaultValue: "Lowest Price"
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
            defaultValue:
                "At a fraction of the price of competing products, it significantly lowers the cost of real-time video generation."
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
            defaultValue:
                "Faithfully reproduces the details and textures of characters and clothing, bringing generated results closer to the intended look and style."
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutPartnershipTitle: String {
        Localization.string(
            "about.partnership_title",
            table: "Home",
            defaultValue: "Bring Real-Time Video to Your App"
        )
    }

    /// About Us product copy, maintained with the Home String Catalog.
    static var aboutPartnershipDetail: String {
        Localization.string(
            "about.partnership_detail",
            table: "Home",
            defaultValue:
                "Beyond video meetings, Xmax X2.1 can power live streaming, virtual try-on for e-commerce, and other interactive video products. Related applications have received positive feedback at industry showcases and from partners. If you would like to integrate real-time video generation into your own app, contact us to learn about integration options and technical support."
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
            defaultValue: "Tell us about your use case and integration needs."
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

}
