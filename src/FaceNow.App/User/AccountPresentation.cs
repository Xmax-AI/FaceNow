//
//  AccountPresentation.cs
//  FaceNow
//

using System.Globalization;
using FaceNow.Core.User;

namespace FaceNow.App.User;

/// <summary>Formats account identity and masks API keys for display.</summary>
internal sealed class AccountPresentation
{
    internal required string AvatarText { get; init; }

    internal required string Title { get; init; }

    internal required string Credits { get; init; }

    internal static AccountPresentation From(
        UserRepository user
    )
    {
        static string? Nonempty(
            string? value
        ) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
        string? phone = Nonempty(user.Profile?.Phone), email = Nonempty(user.Profile?.Email);
        string initials = phone is not null ? phone[..Math.Min(2, phone.Length)]
            : email is not null ? email[..Math.Min(2, email.Length)].ToUpperInvariant() : "";
        return new()
        {
            AvatarText = initials,
            Title = user.SessionApiKeySuffix is { } suffix ? new string(
                '•',
                12 - suffix.Length
            ) + suffix : email ?? phone ?? "Account",
            Credits = user.RemainingCredits?.ToString("#,0.######", CultureInfo.InvariantCulture) ?? "—"
        };
    }
}
