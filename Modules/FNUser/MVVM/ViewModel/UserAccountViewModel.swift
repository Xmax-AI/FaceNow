//
//  UserAccountViewModel.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory
import Foundation

/// Derives the account avatar and credit readout from the shared user state.
@MainActor
final class UserAccountViewModel {

    /// The authenticated profile and server-owned balance.
    @Injected(\.userRepo) private var userRepo: UserRepository

    #if DEBUG
        /// Temporarily previews the low-credit pill regardless of the server-confirmed balance.
        private static let forceLowCreditsAppearance = true
    #endif

    /// Resolves the shared repository while permitting an isolated test account.
    init(
        user: UserRepository? = nil
    ) {
        if let user { userRepo = user }
    }

    /// Uses the first two phone characters, falling back to the email's uppercase initials.
    var avatarText: String {
        if let phone = nonempty(userRepo.profile?.phone) { return String(phone.prefix(2)) }
        if let email = nonempty(userRepo.profile?.email) { return String(email.prefix(2)).uppercased() }
        return ""
    }

    /// Uses twelve display characters while revealing only the final four identifier characters.
    var accountTitle: String {
        if let suffix = userRepo.sessionAPIKeySuffix {
            return String(repeating: "•", count: 12 - suffix.count) + suffix
        }
        if let email = nonempty(userRepo.profile?.email) { return "Email · \(masked(email))" }
        if let phone = nonempty(userRepo.profile?.phone) { return "Phone · \(masked(phone))" }
        return "Account"
    }

    /// Whether a validated account can open the existing credit purchase page.
    var canRecharge: Bool { userRepo.canAccessHome }

    /// Account requests finish before the user can request another session change.
    var canSignOut: Bool { userRepo.canAccessHome && !userRepo.isBusy }

    /// Keeps unknown credit values distinct from a confirmed zero, without abbreviating large balances.
    var creditsText: String {
        guard let remaining = userRepo.remainingCredits else { return "—" }
        return remaining.formatted(.number.precision(.fractionLength(0...6)))
    }

    /// Warns below 300 credits while allowing a temporary Debug-only visual preview.
    var showsLowCreditsWarning: Bool {
        #if DEBUG
            if Self.forceLowCreditsAppearance { return true }
        #endif
        guard let remaining = userRepo.remainingCredits else { return false }
        return remaining < 300
    }

    /// Explains the balance state while describing the credit-page destination.
    var creditsHelp: String {
        if let error = userRepo.creditsErrorMessage {
            let state = userRepo.remainingCredits == nil ? "Credits unavailable." : "Showing the last known balance."
            return "\(state) \(error) Open the credits page."
        }
        if userRepo.isLoadingCredits { return "Refreshing remaining credits. Open the credits page." }
        if showsLowCreditsWarning { return "Low credits. Top up to avoid interruptions." }
        return "Open the credits page."
    }

    /// Treats empty profile fields as absent when deriving avatar characters.
    private func nonempty(
        _ value: String?
    ) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    /// Masks the entire prefix and keeps short identifiers fully concealed.
    private func masked(
        _ value: String
    ) -> String {
        let suffix = value.count > 4 ? String(value.suffix(4)) : ""
        return String(repeating: "•", count: 12 - suffix.count) + suffix
    }
}
