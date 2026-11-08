//
//  AccountModels.cs
//  FaceNow
//

using System.Text.Json.Serialization;

namespace FaceNow.Core.User;

public enum LoginMethod
{
    Sms, Email
}
public enum SessionState
{
    SignedOut, Cached, Verified
}
public enum CredentialKind
{
    AccountToken, ApiKey
}

public sealed class LoginConfiguration
{
    public required string TenantName { get; init; }

    public required bool EnableEmailLogin { get; init; }

    public required bool EnableSmsLogin { get; init; }

    public required bool EnableCaptcha { get; init; }

    public required bool CaptchaRequiredOnLogin { get; init; }

    public string? CaptchaAppId { get; init; }

    public required int EmailCodeLength { get; init; }

    public required int EmailCodeCooldownSeconds { get; init; }

    public required int SmsCodeLength { get; init; }

    public required int SmsCodeCooldownSeconds { get; init; }

    public bool Supports(
        LoginMethod method
    ) => method == LoginMethod.Sms ? EnableSmsLogin : EnableEmailLogin;

    public int CodeLength(
        LoginMethod method
    ) => Math.Clamp(
        method == LoginMethod.Sms ? SmsCodeLength : EmailCodeLength,
        1,
        12
    );

    public int Cooldown(
        LoginMethod method
    ) => Math.Max(
        0,
        method == LoginMethod.Sms ? SmsCodeCooldownSeconds : EmailCodeCooldownSeconds
    );

    public bool NeedsCaptcha(
        LoginMethod method,
        bool login
    ) => login
        ? CaptchaRequiredOnLogin || method == LoginMethod.Sms && EnableCaptcha : EnableCaptcha;
}

public sealed class CaptchaProof(
    string? ticket = null,
    string? randomString = null
)
{
    public string? CaptchaTicket { get; } = ticket;

    public string? CaptchaRandStr { get; } = randomString;
}

public sealed class AccountProfile
{
    public string? Uid { get; init; }

    public string? Id { get; init; }

    public string? Nickname { get; init; }

    public string? Email { get; init; }

    public string? Phone { get; init; }

    [JsonIgnore] public string Identity => !string.IsNullOrWhiteSpace(Uid) ? Uid : Id ?? "";

    [JsonIgnore]
    public string DisplayName => !string.IsNullOrWhiteSpace(Nickname) ? Nickname
        : !string.IsNullOrWhiteSpace(Email) ? Email
        : Phone is { Length: 11 } phone ? phone[..3] + "••••" + phone[^4..] : "Account";
}

// Classes deliberately avoid record-generated ToString methods containing credentials.
public sealed class ApiKeyRecord
{
    public required string Uid { get; init; }

    public required string TenantName { get; init; }

    public required string UserUid { get; init; }

    public required string Name { get; init; }

    public required string ApiKey { get; init; }

    public required string Status { get; init; }

    public bool IsActiveFor(
        string owner
    ) => Status == "active" && TenantName == AccountContract.Tenant
        && UserUid == owner && !string.IsNullOrWhiteSpace(ApiKey) && !string.IsNullOrWhiteSpace(Uid);

    [JsonIgnore] public string Label => $"{Name} · ••••{(ApiKey.Length > 4 ? ApiKey[^4..] : "")}";
}

public sealed class SessionCredential
{
    public required CredentialKind Kind { get; init; }

    public required string Value { get; init; }

    public string? SelectedKeyUid { get; init; }
}

public sealed class CachedAccount
{
    public required string CredentialDigest { get; init; }

    public required AccountProfile Profile { get; init; }
}

public static class AccountContract
{
    public const string Tenant = "open-platform";

    public static Uri ServiceOrigin => FaceNow.Core.Product.ProductProfile.Current.ApiOrigin;
}

public sealed class AccountException(
    string message,
    int? code = null
) : Exception(message)
{
    public int? Code { get; } = code;

    public bool IsUnauthorized => Code is 401 or 46002;
}
