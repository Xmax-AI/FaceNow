//
//  UserStrings.swift
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

/// Provides typed login text while keeping business keys outside the generic localization service.
enum UserStrings {

    /// Welcome heading on the sign-in page.
    static var welcome: String {
        Localization.string(
            "login.welcome",
            table: "User",
            defaultValue: "Welcome to FaceNow"
        )
    }

    /// Product tagline below the welcome heading.
    static var subtitle: String {
        Localization.string(
            "login.subtitle",
            table: "User",
            defaultValue: "Your new look for every camera moment"
        )
    }

    /// Product slogan over the login demonstration video.
    static var slogan: String {
        Localization.string(
            "login.slogan",
            table: "User",
            defaultValue: "Be Anyone.  Be You."
        )
    }

    /// Model credit beneath the video slogan.
    static var modelCredit: String {
        Localization.string(
            "login.model_credit",
            table: "User",
            defaultValue: "Powered by the world-leading real-time video editing model from Xmax.ai"
        )
    }

    /// Phone verification-code sign-in method.
    static var phone: String {
        Localization.string(
            "login.method.phone",
            table: "User",
            defaultValue: "Phone"
        )
    }

    /// Email verification-code sign-in method.
    static var email: String {
        Localization.string(
            "login.method.email",
            table: "User",
            defaultValue: "Email"
        )
    }

    /// API-key sign-in method and input accessibility label.
    static var apiKey: String {
        Localization.string(
            "login.method.api_key",
            table: "User",
            defaultValue: "API Key"
        )
    }

    /// Accessibility label for the phone input.
    static var phoneLabel: String {
        Localization.string(
            "login.field.phone",
            table: "User",
            defaultValue: "Phone number"
        )
    }

    /// Phone input placeholder; country prefix is separate.
    static var phonePlaceholder: String {
        Localization.string(
            "login.placeholder.phone",
            table: "User",
            defaultValue: "Enter your phone number"
        )
    }

    /// Accessibility label for the email input.
    static var emailLabel: String {
        Localization.string(
            "login.field.email",
            table: "User",
            defaultValue: "Email address"
        )
    }

    /// Email input placeholder.
    static var emailPlaceholder: String {
        Localization.string(
            "login.placeholder.email",
            table: "User",
            defaultValue: "Enter your email address"
        )
    }

    /// Masked API-key input placeholder.
    static var apiKeyPlaceholder: String {
        Localization.string(
            "login.placeholder.api_key",
            table: "User",
            defaultValue: "Enter your active Xmax API key"
        )
    }

    /// Accessibility label for the verification-code input.
    static var codeLabel: String {
        Localization.string(
            "login.field.code",
            table: "User",
            defaultValue: "Verification code"
        )
    }

    /// Verification-code input placeholder.
    static var codePlaceholder: String {
        Localization.string(
            "login.placeholder.code",
            table: "User",
            defaultValue: "Enter verification code"
        )
    }

    /// Action that requests a fresh verification code.
    static var getCode: String {
        Localization.string(
            "login.get_code",
            table: "User",
            defaultValue: "Get Code"
        )
    }

    /// Primary authentication action.
    static var signIn: String {
        Localization.string(
            "login.sign_in",
            table: "User",
            defaultValue: "Sign in"
        )
    }

    /// Label above the supported communication app logos.
    static var scenarios: String {
        Localization.string(
            "login.scenarios",
            table: "User",
            defaultValue: "Scenarios"
        )
    }

    /// Tooltip when verification-code sign-in is disabled by the platform.
    static var loginUnavailable: String {
        Localization.string(
            "login.error.unavailable",
            table: "User",
            defaultValue: "Verification-code login is currently unavailable."
        )
    }

    /// Missing security-verification configuration.
    static var securityUnavailable: String {
        Localization.string(
            "captcha.error.unavailable",
            table: "User",
            defaultValue: "Security verification is unavailable. Please try again."
        )
    }

    /// Security challenge timed out.
    static var securityTimedOut: String {
        Localization.string(
            "captcha.error.timeout",
            table: "User",
            defaultValue: "Security verification timed out. Please try again."
        )
    }

    /// Security challenge failed.
    static var securityFailed: String {
        Localization.string(
            "captcha.error.failed",
            table: "User",
            defaultValue: "Security verification failed. Please try again."
        )
    }

    /// Fallback when authentication does not complete.
    static var retrySignIn: String {
        Localization.string(
            "login.error.retry",
            table: "User",
            defaultValue: "Please try signing in again."
        )
    }

    /// Explains a rejected verification code and offers both recovery paths.
    static var incorrectCode: String {
        Localization.string(
            "login.error.incorrect_code",
            table: "User",
            defaultValue: "Invalid code. Check it and try again."
        )
    }

    /// Directs the user to request a fresh code after an explicit expiry response.
    static var expiredCode: String {
        Localization.string(
            "login.error.expired_code",
            table: "User",
            defaultValue: "This code has expired. Request a new one."
        )
    }

    /// The shared legal document title used both in the sentence and its link range.
    static var termsOfUse: String {
        Localization.string("legal.terms_of_use", table: "Common", defaultValue: "Terms of Use")
    }

    /// The shared privacy document title used both in the sentence and its link range.
    static var privacyPolicy: String {
        Localization.string("legal.privacy_policy", table: "Common", defaultValue: "Privacy Policy")
    }

    /// Formats the remaining resend time as one complete translatable message.
    static func resendCode(
        seconds: Int
    ) -> String {
        Localization.format(
            "login.resend_code",
            table: "User",
            defaultValue: "Resend (%llds)",
            arguments: [Int64(seconds)]
        )
    }

    /// Allows translators to reorder the two legal links within the complete agreement sentence.
    static var agreement: String {
        Localization.format(
            "login.agreement",
            table: "User",
            defaultValue: "By signing in, you are agreeing to the %1$@ and %2$@.",
            arguments: [termsOfUse, privacyPolicy]
        )
    }
}
