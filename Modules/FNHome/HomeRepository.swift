//
//  HomeRepository.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory
import Combine
import Foundation

/// Supplies product destinations and artwork used by the home page.
@MainActor
final class HomeRepository: ObservableObject {

    /// The organization's public social profile.
    let socialURL = URL(string: "https://x.com/XmaxAIOfficial")!

    /// The public product website.
    let websiteURL = URL(string: "https://xmaxsi.com")!

    /// The product support destination.
    let contactURL = URL(string: "mailto:facenow@xmax.ai")!

    /// The public app version shown in the home footer, independent of the internal build number.
    let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

    /// The domestic API-key management portal.
    let platformURL = URL(string: "https://platform.xmaxai.com")!

    /// The follow-popover artwork loaded on demand by the view.
    let wechatImageURL = URL(string: "https://assets.22duck.fun/image/wechatAccount.jpg")!
}

extension Container {

    /// The shared Home repository registered for this container.
    @MainActor
    var homeRepo: Factory<HomeRepository> {
        Factory(self) { @MainActor in HomeRepository() }.singleton
    }
}
