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
#if canImport(Localization)
    import Localization
#endif

/// Derives the account avatar and credit readout from the shared user state.
@MainActor
final class UserAccountViewModel {

    /// The authenticated profile and server-owned balance.
    @Injected(\.userRepo) private var userRepo: UserRepository

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

    /// Shows full email or phone identities while keeping API-key credentials masked.
    var accountTitle: String {
        if let suffix = userRepo.sessionAPIKeySuffix {
            return String(repeating: "•", count: 12 - suffix.count) + suffix
        }
        if let email = nonempty(userRepo.profile?.email) { return email }
        if let phone = nonempty(userRepo.profile?.phone) { return phone }
        return AccountStrings.accountAccount
    }

    /// Whether a validated account can open the existing credit purchase page.
    var canRecharge: Bool { userRepo.canAccessHome }

    /// Account requests finish before the user can request another session change.
    var canSignOut: Bool { userRepo.canAccessHome && !userRepo.isBusy }

    /// Keeps unknown credit values distinct from a confirmed zero, without abbreviating large balances.
    var creditsText: String {
        guard let remaining = userRepo.remainingCredits else { return "—" }
        return remaining.formatted(.number.precision(.fractionLength(0...6)).locale(Localization.locale))
    }

    /// Warns only when the server-confirmed balance is below 300 credits.
    var showsLowCreditsWarning: Bool {
        guard let remaining = userRepo.remainingCredits else { return false }
        return remaining < 300
    }

    /// Explains the balance state while describing the credit-page destination.
    var creditsHelp: String {
        if let error = userRepo.creditsErrorMessage {
            let state =
                userRepo.remainingCredits == nil
                ? AccountStrings.accountCreditsUnavailable : AccountStrings.accountShowingTheLastKnownBalance
            return AccountStrings.balanceFailure(state: state, message: error)
        }
        if userRepo.isLoadingCredits { return AccountStrings.accountRefreshingRemainingCreditsOpenTheCreditsPage }
        if showsLowCreditsWarning { return AccountStrings.accountLowCreditsTopUpToAvoidInterruptions }
        return AccountStrings.accountOpenTheCreditsPage
    }

    /// Treats empty profile fields as absent when deriving avatar characters.
    private func nonempty(
        _ value: String?
    ) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

}
