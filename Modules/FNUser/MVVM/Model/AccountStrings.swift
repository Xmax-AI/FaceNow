//
//  AccountStrings.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
#if canImport(Localization)
    import Localization
#endif

/// Provides module-owned English defaults and stable localization keys for page presentation.
enum AccountStrings {

    /// The shared credit-exhaustion notice for camera startup and active generation.
    static var insufficientCredits: String {
        Localization.string(
            "account.insufficient_credits",
            table: "User",
            defaultValue: "Insufficient credits. Please top up on the Xmax Open Platform first."
        )
    }

    /// Account, credit or header presentation text.
    static var accountGetAnAPIKeyFromTheXmaxOpenPlatform: String {
        Localization.string(
            "account.get_an_api_key_from_the_xmax_open_platform",
            table: "User",
            defaultValue: "Get an API key from the Xmax Open Platform."
        )
    }

    /// Account, credit or header presentation text.
    static var accountSignInToYourAccount: String {
        Localization.string(
            "account.sign_in_to_your_account",
            table: "User",
            defaultValue: "Sign in to your account"
        )
    }

    /// Account, credit or header presentation text.
    static var accountBuyCredits: String {
        Localization.string(
            "account.buy_credits",
            table: "User",
            defaultValue: "Buy Credits"
        )
    }

    /// Account, credit or header presentation text.
    static var accountViewUsage: String {
        Localization.string(
            "account.view_usage",
            table: "User",
            defaultValue: "View Usage"
        )
    }

    /// Shared account-menu label.
    static var privacyPolicy: String {
        Localization.string(
            "legal.privacy_policy",
            table: "Common",
            defaultValue: "Privacy Policy"
        )
    }

    /// Shared account-menu label.
    static var termsOfUse: String {
        Localization.string(
            "legal.terms_of_use",
            table: "Common",
            defaultValue: "Terms of Use"
        )
    }

    /// Account, credit or header presentation text.
    static var accountSignOut: String {
        Localization.string(
            "account.sign_out",
            table: "User",
            defaultValue: "Sign out"
        )
    }

    /// Account, credit or header presentation text.
    static var accountLowCredits: String {
        Localization.string(
            "account.low_credits",
            table: "User",
            defaultValue: "Low credits"
        )
    }

    /// Account, credit or header presentation text.
    static var accountYouReRunningLowOnCreditsTopUpTo: String {
        Localization.string(
            "account.you_re_running_low_on_credits_top_up_to",
            table: "User",
            defaultValue: "You're running low on credits. Top up to avoid interruptions."
        )
    }

    /// Account, credit or header presentation text.
    static var accountAccount: String {
        Localization.string(
            "account.account",
            table: "User",
            defaultValue: "Account"
        )
    }

    /// Account, credit or header presentation text.
    static var accountCreditsUnavailable: String {
        Localization.string(
            "account.credits_unavailable",
            table: "User",
            defaultValue: "Credits unavailable."
        )
    }

    /// Account, credit or header presentation text.
    static var accountShowingTheLastKnownBalance: String {
        Localization.string(
            "account.showing_the_last_known_balance",
            table: "User",
            defaultValue: "Showing the last known balance."
        )
    }

    /// Account, credit or header presentation text.
    static var accountRefreshingRemainingCreditsOpenTheCreditsPage: String {
        Localization.string(
            "account.refreshing_remaining_credits_open_the_credits_page",
            table: "User",
            defaultValue: "Refreshing remaining credits. Open the credits page."
        )
    }

    /// Account, credit or header presentation text.
    static var accountLowCreditsTopUpToAvoidInterruptions: String {
        Localization.string(
            "account.low_credits_top_up_to_avoid_interruptions",
            table: "User",
            defaultValue: "Low credits. Top up to avoid interruptions."
        )
    }

    /// Account, credit or header presentation text.
    static var accountOpenTheCreditsPage: String {
        Localization.string(
            "account.open_the_credits_page",
            table: "User",
            defaultValue: "Open the credits page."
        )
    }

    /// Complete message; preserve all format placeholders.
    static func accountAccessibility(
        name: String
    ) -> String {
        Localization.format(
            "message.account_userrepo_displayname",
            table: "User",
            defaultValue: "Account: %@",
            arguments: [name]
        )
    }

    /// Complete message; preserve all format placeholders.
    static func balanceAccessibility(
        balance: String
    ) -> String {
        Localization.format(
            "message.remaining_credits_viewmodel_creditstext",
            table: "User",
            defaultValue: "Remaining credits: %@",
            arguments: [balance]
        )
    }

    /// Complete message; preserve all format placeholders.
    static func balanceTitle(
        balance: String
    ) -> String {
        Localization.format(
            "message.credits_viewmodel_creditstext",
            table: "User",
            defaultValue: "Credits: %@",
            arguments: [balance]
        )
    }

    /// Complete message; preserve all format placeholders.
    static func balanceFailure(
        state: String,
        message: String
    ) -> String {
        Localization.format(
            "message.state_error_open_the_credits_page",
            table: "User",
            defaultValue: "%1$@ %2$@ Open the credits page.",
            arguments: [state, message]
        )
    }
    /// Account authentication notice shown when entering or leaving home.
    static var sessionExpired: String {
        Localization.string(
            "session.expired",
            table: "User",
            defaultValue: "Your session has expired. Please sign in again."
        )
    }

    /// Account authentication notice shown when entering or leaving home.
    static var sessionUnavailable: String {
        Localization.string(
            "session.unavailable",
            table: "User",
            defaultValue: "Unable to verify your session. Check your connection and sign in again."
        )
    }

    /// Account authentication notice shown when entering or leaving home.
    static var invalidAPIKey: String {
        Localization.string(
            "session.invalid_api_key",
            table: "User",
            defaultValue: "Invalid API key. Check it and try again."
        )
    }

    /// Account authentication notice shown when entering or leaving home.
    static var inactiveAPIKey: String {
        Localization.string(
            "session.inactive_api_key",
            table: "User",
            defaultValue: "This API key is invalid or no longer active."
        )
    }

    /// Account authentication notice shown when entering or leaving home.
    static var ownerMismatch: String {
        Localization.string(
            "session.owner_mismatch",
            table: "User",
            defaultValue: "The account profile does not match this API key."
        )
    }

}
