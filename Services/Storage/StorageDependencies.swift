//
//  StorageDependencies.swift
//  FaceNow
//

import Factory
import Foundation

public extension Container {

    /// The preferences store shared by user repositories unless overridden in a test container.
    @MainActor
    var userDefaults: Factory<UserDefaults> {
        Factory(self) { @MainActor in UserDefaults.standard }.singleton
    }

    /// The Keychain capability, independent of business account state.
    @MainActor
    var userTokenStore: Factory<any UserTokenStoring> {
        Factory(self) { @MainActor in UserTokenStore() }.singleton
    }
}
