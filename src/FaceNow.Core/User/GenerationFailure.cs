using System.Text.RegularExpressions;

namespace FaceNow.Core.User;

/// <summary>Identifies credit exhaustion from platform error codes and explicit messages.</summary>
public static class GenerationFailure
{
    public static bool IsInsufficientCredits(int? apiCode, string message)
    {
        if (apiCode is 43001 or 46017) return true;
        string detail = message.ToLowerInvariant().Replace('_', ' ');
        if (new[] { "积分不足", "余额不足", "积分已用完", "积分已耗尽", "余额已耗尽" }.Any(detail.Contains)) return true;
        return Regex.IsMatch(detail,
            @"\b(insufficient (credits?|points?|balance|funds)|not enough (credits?|points?)|out of (credits?|points?)|no credits?( remaining)?|(credits?|points?|balance|funds) (is |are )?(insufficient|exhausted|depleted)|credits? (have |has )?(run out|been exhausted|been depleted))\b",
            RegexOptions.CultureInvariant);
    }
}
