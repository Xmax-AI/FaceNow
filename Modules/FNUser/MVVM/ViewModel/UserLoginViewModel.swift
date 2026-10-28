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

    /// Isolates channel cooldowns and treats email casing consistently with the existing form.
    private func destinationKey(
        _ value: String,
        method: LoginMethod
    ) -> String { method.rawValue + ":" + destination(from: value).lowercased() }
}
