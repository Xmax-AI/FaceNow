//
//  HomeRepository.swift
//  FaceNow
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
    let websiteURL = NetworkEnvironment.current.websiteURL

    /// The product support destination.
    let contactURL = URL(string: "mailto:facenow@xmax.ai")!

    /// The troubleshooting document opened from the home footer.
    let troubleshootingURL = NetworkEnvironment.current.troubleshootingURL

    /// The public app version shown in the home footer, independent of the internal build number.
    let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

    /// The current edition's API-key management portal.
    let platformURL = NetworkEnvironment.current.platformURL

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
