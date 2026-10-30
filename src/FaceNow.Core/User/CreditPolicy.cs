namespace FaceNow.Core.User;

/// <summary>Matches macOS startup checks against the last confirmed, in-memory balance.</summary>
public static class CreditPolicy
{
    public const int InsufficientCode = 43001;
    public const string InsufficientMessage = "Insufficient credits. Please top up on the Xmax Open Platform first.";

    // An unknown balance is not evidence of insufficient credits. Positive balances below
    // the low-credit warning threshold are also allowed to start.
    public static bool IsInsufficient(double? balance) => balance is <= 0;
}
