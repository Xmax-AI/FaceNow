//
//  VideoCallGuide.swift
//  FaceNow
//

import Foundation

/// The fixed original screenshot examples shown in the final preparation step.
enum VideoCallGuide: Int, CaseIterable {
    case lark
    case tencentMeeting
    case weChat

    /// Preserves each application's own brand name rather than translating it.
    var name: String {
        switch self {
        case .lark: "Lark"
        case .tencentMeeting: "Tencent Meeting"
        case .weChat: "WeChat"
        }
    }

    /// Refers to the unmodified screenshot in the onboarding asset catalog.
    var assetName: String {
        switch self {
        case .lark: "OnboardingVideoCallsLark"
        case .tencentMeeting: "OnboardingVideoCallsTencentMeeting"
        case .weChat: "OnboardingVideoCallsWeChat"
        }
    }

    /// Uses the same published device name as installation, output, and home guidance.
    @MainActor
    var caption: String {
        switch self {
        case .lark: OnboardingStrings.videoCallsLarkCaption(camera: VirtualCameraConfiguration.deviceName)
        case .tencentMeeting: OnboardingStrings.videoCallsTencentCaption(camera: VirtualCameraConfiguration.deviceName)
        case .weChat: OnboardingStrings.videoCallsWeChatCaption(camera: VirtualCameraConfiguration.deviceName)
        }
    }
}
