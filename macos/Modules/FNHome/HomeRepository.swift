//
//  HomeRepository.swift
//  FaceNow
//

import Factory
import Combine
import Foundation

/// Supplies the app version and product destinations.
@MainActor
final class HomeRepository: ObservableObject {

    /// The product support destination.
    let contactURL = URL(string: "mailto:facenow@xmax.ai")!

    /// The public app version, independent of the internal build number.
    let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

    /// The API platform for this edition.
    let platformURL = NetworkEnvironment.current.platformURL
}

extension Container {

    /// The shared Home repository registered for this container.
    @MainActor
    var homeRepo: Factory<HomeRepository> {
        Factory(self) { @MainActor in HomeRepository() }.singleton
    }
}
