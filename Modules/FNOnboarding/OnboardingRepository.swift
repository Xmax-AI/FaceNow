//
//  OnboardingRepository.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory
import Foundation

/// Supplies first-launch copy and policy destinations to onboarding views.
@MainActor
final class OnboardingRepository {

    /// The headline above the initial camera stage.
    let headline = "Be Different Everyday with FaceNow"

    /// The legal acceptance text displayed beside the Start action.
    let agreement = "By clicking Start, you agree to our Terms of Use and Privacy Policy."

    /// The product's terms of use.
    let termsURL = URL(string: "https://platform.xmaxsi.com/docs/resources/terms")!

    /// The product's privacy policy.
    let privacyURL = URL(string: "https://platform.xmaxsi.com/docs/resources/privacy")!

    /// The ownership line displayed below the stage.
    let copyright = "Copyright © 2026 XMAX.AI PTE.LTD. All rights reserved."
}

extension Container {

    /// The shared Onboarding repository registered for this container.
    @MainActor
    var onboardingRepo: Factory<OnboardingRepository> {
        Factory(self) { @MainActor in OnboardingRepository() }.singleton
    }
}
