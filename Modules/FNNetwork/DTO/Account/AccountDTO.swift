//
//  AccountDTO.swift
//  FaceNow
//

import Foundation
import CoreFoundation
import HandyJSON

/// Verification-code methods supported by the domestic platform.
public enum LoginMethod: String, Sendable, CaseIterable {

    /// Mainland mobile-number verification.
    case sms

    /// Email-address verification.
    case email
}

/// The tenant-controlled login capabilities returned by the platform.
public struct LoginConfiguration: ResponseModel {

    /// The account tenant to which these settings belong.
    public var tenantName = ""

    /// Whether email-code login is available.
    public var enableEmailLogin = false

    /// Whether SMS-code login is available.
    public var enableSmsLogin = false

    /// Whether code sending requires a security challenge.
    public var enableCaptcha = false

    /// Whether submitting credentials requires a security challenge.
    public var captchaRequiredOnLogin = false

    /// The Tencent challenge application identifier.
    public var captchaAppId: String? = nil

    /// The required email verification-code length.
    public var emailCodeLength = 0

    /// The resend delay for an email address, in seconds.
    public var emailCodeCooldownSeconds = 0

    /// The required SMS verification-code length.
    public var smsCodeLength = 0

    /// The resend delay for a phone number, in seconds.
    public var smsCodeCooldownSeconds = 0

    /// Creates an empty DTO for HandyJSON's field mapping.
    public init() {}

    /// Requires configuration fields that control security, input validation, and resend behavior.
    public static func isValidJSON(
        _ value: [String: Any]
    ) -> Bool {
        value["tenantName"] is String
            && ["enableEmailLogin", "enableSmsLogin", "enableCaptcha", "captchaRequiredOnLogin"].allSatisfy {
                value[$0] is Bool
            }
            && ["emailCodeLength", "smsCodeLength", "emailCodeCooldownSeconds", "smsCodeCooldownSeconds"].allSatisfy {
                value[$0] is Int
            }
    }

    /// Returns whether the tenant currently permits the chosen method.
    public func supports(
        _ method: LoginMethod
    ) -> Bool {
        method == .sms ? enableSmsLogin : enableEmailLogin
    }

    /// Returns a bounded code length for native input validation.
    public func codeLength(
        for method: LoginMethod
    ) -> Int {
        min(12, max(1, method == .sms ? smsCodeLength : emailCodeLength))
    }

    /// Returns the server-provided resend interval in seconds.
    public func cooldown(
        for method: LoginMethod
    ) -> TimeInterval {
        TimeInterval(max(0, method == .sms ? smsCodeCooldownSeconds : emailCodeCooldownSeconds))
    }
}

/// The security challenge result attached only to the operation it authorizes.
public struct CaptchaProof: Sendable {

    /// The opaque ticket returned by Tencent.
    public let captchaTicket: String?

    /// The opaque random string paired with that ticket.
    public let captchaRandStr: String?

    /// Creates a proof, or an empty value when the tenant disables verification.
    public init(
        ticket: String? = nil,
        randomString: String? = nil
    ) {
        captchaTicket = ticket
        captchaRandStr = randomString
    }
}

/// The profile fields used by the native account menu.
public struct AccountProfile: ResponseModel, Codable {

    /// The optional platform user identifier.
    public var uid: String? = nil

    /// An alternate identifier used by some platform responses.
    public var id: String? = nil

    /// The optional nickname selected by the user.
    public var nickname: String? = nil

    /// The bound email address, when available.
    public var email: String? = nil

    /// The bound mobile number, when available.
    public var phone: String? = nil

    /// Creates an empty DTO for HandyJSON's field mapping.
    public init() {}

    /// Requires an account identity before publishing a validated signed-in profile.
    public static func isValidJSON(
        _ value: [String: Any]
    ) -> Bool {
        [value["uid"] as? String, value["id"] as? String].contains { $0?.isEmpty == false }
    }
}

/// The server-calculated credits remaining for the authenticated account.
public struct AccountBalance: ResponseModel {

    /// The remaining credits; missing or malformed values are rejected before mapping.
    public var currentBalance: Double = 0

    /// Creates an empty DTO for HandyJSON's field mapping.
    public init() {}

    /// Requires a finite number so an unavailable balance can never become a fabricated zero.
    public static func isValidJSON(
        _ value: [String: Any]
    ) -> Bool {
        guard let number = value["currentBalance"] as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return false }
        return number.doubleValue.isFinite && number.doubleValue >= 0
    }
}

/// Encodes a code-send request using the domestic platform's camel-case fields.
struct CodeRequest: HandyJSON {

    /// The tenant governing this request.
    var tenantName = AccountAPI.tenant

    /// The SMS destination, omitted for email requests.
    var phone: String?

    /// The email destination, omitted for SMS requests.
    var email: String?

    /// The one-use security ticket for this operation.
    var captchaTicket: String?

    /// The opaque random value paired with the security ticket.
    var captchaRandStr: String?
}

/// Encodes a credential exchange using the same request mapping as the reference app.
struct LoginRequest: HandyJSON {

    /// The tenant governing this request.
    var tenantName = AccountAPI.tenant

    /// The selected verification channel.
    var loginMethod = "sms"

    /// The phone number or email address being verified.
    var accountName = ""

    /// The one-time verification code.
    var credential = ""

    /// The one-use security ticket for this operation.
    var captchaTicket: String?

    /// The opaque random value paired with the security ticket.
    var captchaRandStr: String?
}
