//
//  AccountAPI.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
@preconcurrency import Moya

/// Describes domestic account routes as Moya targets, independently of user state.
public enum AccountAPI: APITargetType {

    /// Reads tenant-controlled login methods and security settings.
    case configuration

    /// Sends a verification code after one-use security verification.
    case sendCode(method: LoginMethod, account: String, proof: CaptchaProof)

    /// Exchanges a one-time code for the domestic platform's token string.
    case login(method: LoginMethod, account: String, code: String, proof: CaptchaProof)

    /// Reads the current user's identity and validates a persisted session.
    case profile

    /// Reads the remaining credits from the Open API billing service.
    case balance

    /// Invalidates the current platform session.
    case logout

    /// The tenant shared with the domestic API platform.
    public static let tenant = "open-platform"

    /// The service-relative route, retaining the domestic API prefix.
    public var path: String {
        switch self {
        case .configuration: return "/baas/api/user/login/config"
        case .sendCode(
            let method,
            _,
            _
        ):
            return "/baas/api/message/public/\(method == .sms ? "sms-code" : "email-code")/send"
        case .login: return "/baas/api/user/login"
        case .profile: return "/baas/api/user/info"
        case .balance: return "/open/api/v1/points/balance"
        case .logout: return "/baas/api/user/logout"
        }
    }

    /// Reads public configuration and profiles with GET; mutations use POST.
    public var method: Moya.Method {
        switch self {
        case .configuration, .profile, .balance: return .get
        default: return .post
        }
    }

    /// Maps request DTOs through HandyJSON and chooses Moya's matching encoder.
    public var task: Moya.Task {
        switch self {
        case .configuration:
            return .requestParameters(
                parameters: ["tenantName": Self.tenant],
                encoding: URLEncoding.queryString
            )
        case .sendCode(
            let method,
            let account,
            let proof
        ):
            var request = CodeRequest()
            request.phone = method == .sms ? account : nil
            request.email = method == .email ? account : nil
            request.captchaTicket = proof.captchaTicket
            request.captchaRandStr = proof.captchaRandStr
            return .requestParameters(
                parameters: request.toJSON() ?? [:],
                encoding: JSONEncoding.default
            )
        case .login(
            let method,
            let account,
            let code,
            let proof
        ):
            var request = LoginRequest()
            request.loginMethod = method.rawValue
            request.accountName = account
            request.credential = code
            request.captchaTicket = proof.captchaTicket
            request.captchaRandStr = proof.captchaRandStr
            return .requestParameters(
                parameters: request.toJSON() ?? [:],
                encoding: JSONEncoding.default
            )
        case .profile, .balance, .logout: return .requestPlain
        }
    }

    /// Profile, balance, and logout calls require the current account credential.
    public var requiresAuthorization: Bool {
        switch self {
        case .profile, .balance, .logout: return true
        default: return false
        }
    }
}
