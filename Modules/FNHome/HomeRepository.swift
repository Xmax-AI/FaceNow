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

/// Supplies product destinations independently of AppKit views and account authentication.
@MainActor
final class HomeRepository: ObservableObject {

    /// The organization's public social profile.
    let socialURL = URL(string: "https://x.com/XmaxAIOfficial")!

    /// The public product website.
    let websiteURL = URL(string: "https://xmaxsi.com")!

    /// The product support destination.
    let contactURL = URL(string: "mailto:contact@xmax.ai")!

    /// The organization's public repositories.
    let githubURL = URL(string: "https://github.com/orgs/Xmax-AI")!

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
