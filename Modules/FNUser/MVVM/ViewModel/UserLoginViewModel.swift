//
//  UserLoginViewModel.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
#if canImport(FNNetwork)
    import FNNetwork
#endif

/// Owns login presentation state independently of native controls and network tasks.
@MainActor
final class UserLoginViewModel {

    /// The capabilities validated for the domestic open-platform tenant.
    private(set) var configuration: LoginConfiguration?

    /// The selected verification channel, initially mainland mobile numbers.
    private(set) var method = LoginMethod.sms

    /// Selects the API-key input form without changing authenticated account state.
    private(set) var usesAPIKey = false

    /// Records API-key rejection independently of temporary request or focus state.
    private var rejectedAPIKey: String?

    /// Retains each channel's rejected code while its unchanged draft is hidden.
    private var codeRejections: [LoginMethod: RejectedCode] = [:]

    /// Associates validation with the exact submitted code rather than a later filtered edit.
    private struct RejectedCode {
        let value: String
        let reason: SignInRejection
    }

    /// Supplies the shared input with its current credential-validation explanation.
    var apiKeyValidationMessage: String? { rejectedAPIKey != nil ? AccountStrings.invalidAPIKey : nil }

    /// Supplies only the currently selected channel's verification-code error.
    var codeValidationMessage: String? { codeRejections[method]?.reason.message }

    /// Clears API-key validation only when the user edits that field.
    func didEditAPIKey(
        _ value: String
    ) {
        if rejectedAPIKey != value { rejectedAPIKey = nil }
    }

    /// A changed destination also clears its code, invalidating that channel's previous rejection.
    func didEditVerificationCode(
        _ value: String
    ) {
        if codeRejections[method]?.value != value { codeRejections.removeValue(forKey: method) }
    }

    /// Records a recognized field rejection while leaving unrelated errors as request feedback.
    func recordSignInFailure(
        _ error: Error,
        value: String,
        usingAPIKey: Bool = false,
        method: LoginMethod? = nil
    ) -> String {
        guard let rejection = signInRejection(for: error, usingAPIKey: usingAPIKey) else {
            return error.localizedDescription
        }
        switch rejection {
        case .apiKey: rejectedAPIKey = value
        case .incorrectCode, .expiredCode:
            codeRejections[method ?? self.method] = RejectedCode(value: value, reason: rejection)
        case .security: break
        }
        return rejection.message
    }

    /// Changes only the form's input mode; authentication remains owned by the repository.
    func selectAPIKey(
        _ selected: Bool
    ) { usesAPIKey = selected }

    /// Independent channel drafts restored when switching between phone and email.
    private var drafts: [LoginMethod: UserLoginDraft] = [:]

    /// Resend deadlines keyed by normalized channel and destination.
    private var deadlines: [String: TimeInterval] = [:]

    /// The monotonic clock, replaceable in deterministic presentation tests.
    private let uptime: () -> TimeInterval

    /// The tenant-controlled code length, retaining the initial six-digit default.
    var codeLength: Int { configuration?.codeLength(for: method) ?? 6 }

    /// Creates idle form state without reading credentials or issuing a request.
    init(
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.uptime = uptime
    }

    /// Accepts settings only for the domestic open-platform account contract.
    func applyConfiguration(
        _ value: LoginConfiguration
    ) throws {
        guard value.tenantName == AccountAPI.tenant else { throw NetworkError.invalidResponse }
        configuration = value
    }

    /// Trims surrounding whitespace while preserving the destination's entered case.
    func destination(
        from value: String
    ) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Validates the selected channel using the domestic platform's accepted formats.
    func isValidAccount(
        _ value: String
    ) -> Bool {
        let destination = destination(from: value)
        let pattern = method == .sms ? #"^1[3-9][0-9]{9}$"# : #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return destination.count <= 254
            && destination.range(
                of: pattern,
                options: .regularExpression
            ) != nil
    }

    /// Returns only ASCII code digits within the tenant's current length limit.
    func filteredCode(
        _ value: String
    ) -> String { String(value.filter { $0.isASCII && $0.isNumber }.prefix(codeLength)) }

    /// Saves the departing channel's input and restores the newly selected draft.
    func switchMethod(
        _ next: LoginMethod,
        account: String,
        code: String
    ) -> UserLoginDraft {
        usesAPIKey = false
        drafts[method] = UserLoginDraft(
            account: account,
            code: code
        )
        method = next
        return drafts[next] ?? UserLoginDraft()
    }

    /// Records the successful operation's destination and channel, even after a later selection.
    func recordCodeSent(
        to destination: String,
        method: LoginMethod,
        cooldown: TimeInterval
    ) {
        deadlines[
            destinationKey(
                destination,
                method: method
            )
        ] = uptime() + cooldown
    }

    /// Computes the selected destination's resend countdown using monotonic uptime.
    func cooldown(
        for destination: String
    ) -> Int {
        max(
            0,
            Int(
                ceil(
                    (deadlines[
                        destinationKey(
                            destination,
                            method: method
                        )
                    ] ?? 0) - uptime()
                )
            )
        )
    }

    /// Presents recognized credential rejections without confusing transport failures with invalid input.
    func signInErrorMessage(
        for error: Error,
        usingAPIKey: Bool = false
    ) -> String {
        signInRejection(for: error, usingAPIKey: usingAPIKey)?.message ?? error.localizedDescription
    }

    /// Classifies field and security failures once for both toast text and persistent input validation.
    private enum SignInRejection {
        case apiKey
        case incorrectCode
        case expiredCode
        case security

        /// Keeps localization in presentation, without matching translated message strings.
        var message: String {
            switch self {
            case .apiKey: AccountStrings.invalidAPIKey
            case .incorrectCode: UserStrings.incorrectCode
            case .expiredCode: UserStrings.expiredCode
            case .security: UserStrings.securityFailed
            }
        }
    }

    /// Excludes service, rate-limit, and challenge errors from the credential fields.
    private func signInRejection(
        for error: Error,
        usingAPIKey: Bool
    ) -> SignInRejection? {
        guard let failure = error as? NetworkError,
            case .server(let code, let message) = failure,
            code != 429, !(500...599).contains(code)
        else { return nil }
        let detail = message.lowercased()
        if usingAPIKey {
            return (400...499).contains(code) || failure.isUnauthorized ? .apiKey : nil
        }
        if detail.contains("captcha") || detail.contains("图形验证码") || detail.contains("人机验证") {
            return .security
        }
        let codeTerms = [
            "verification code", "verification_code", "sms code", "email code", "one-time code", "otp",
            "invalid code", "incorrect code", "wrong code", "code expired", "code has expired", "code mismatch",
            "验证码", "校验码",
        ]
        guard codeTerms.contains(where: detail.contains) else { return nil }
        let expired = ["expired", "过期", "失效"].contains(where: detail.contains)
        let rejected = [
            "invalid", "incorrect", "wrong", "mismatch", "not match", "failed", "error", "错误", "不正确", "无效", "不匹配", "不对",
            "失败",
        ]
        .contains(where: detail.contains)
        if expired, !rejected { return .expiredCode }
        if rejected { return .incorrectCode }
        return nil
    }

    /// Isolates channel cooldowns and treats email casing consistently with the existing form.
    private func destinationKey(
        _ value: String,
        method: LoginMethod
    ) -> String { method.rawValue + ":" + destination(from: value).lowercased() }
}
