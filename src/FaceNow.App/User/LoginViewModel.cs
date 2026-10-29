using System.Text.RegularExpressions;
using FaceNow.Core.User;

namespace FaceNow.App.User;

/// <summary>Form drafts and monotonic resend deadlines, independently of WinUI and authentication.</summary>
internal sealed class LoginViewModel
{
    private readonly Dictionary<LoginMethod, (string Account, string Code)> drafts = [];
    private readonly Dictionary<string, long> deadlines = [];
    private readonly Func<long> milliseconds;
    public LoginViewModel(Func<long>? milliseconds = null) => this.milliseconds = milliseconds ?? (() => Environment.TickCount64);
    public LoginConfiguration? Configuration { get; set; }
    public LoginMethod Method { get; private set; } = LoginMethod.Sms;
    public bool UsesApiKey { get; private set; }
    public string Account { get; private set; } = "";
    public string Code { get; private set; } = "";
    public string ApiKey { get; set; } = "";
    public bool IsBusy { get; set; }
    public string? Error { get; set; }
    public int CodeLength => Configuration?.CodeLength(Method) ?? 6;
    public bool ValidAccount => Account.Length <= 254 && Regex.IsMatch(Account.Trim(), Method == LoginMethod.Sms
        ? @"^1[3-9][0-9]{9}$" : @"^[^\s@]+@[^\s@]+\.[^\s@]+$", RegexOptions.CultureInvariant);
    public int Cooldown => deadlines.TryGetValue(DestinationKey(Method, Account), out long deadline)
        ? (int)Math.Max(0, Math.Ceiling((deadline - milliseconds()) / 1000d)) : 0;
    public bool CanSendCode => !IsBusy && Configuration?.Supports(Method) == true && ValidAccount && Cooldown == 0;
    public bool CanSubmit => !IsBusy && (UsesApiKey ? ApiKey.Trim().StartsWith("uk-", StringComparison.Ordinal) && ApiKey.Trim().Length > 3
        : Configuration?.Supports(Method) == true && ValidAccount && Code.Length == CodeLength);
    public void SetAccount(string value) { if (Account != value) { Account = value; Code = ""; Error = null; } }
    public void SetCode(string value) { Code = new(value.Where(c => c is >= '0' and <= '9').Take(CodeLength).ToArray()); Error = null; }
    public void Select(int index)
    {
        drafts[Method] = (Account, Code);
        UsesApiKey = index == 2;
        if (!UsesApiKey)
        {
            Method = index == 0 ? LoginMethod.Sms : LoginMethod.Email;
            (Account, Code) = drafts.GetValueOrDefault(Method, ("", ""));
        }
        Error = null;
    }
    public void RecordSent(LoginMethod method, string account, int seconds) =>
        deadlines[DestinationKey(method, account)] = milliseconds() + Math.Max(0, seconds) * 1000L;
    public void ClearSecrets()
    {
        ApiKey = ""; Code = "";
        foreach (var method in drafts.Keys.ToArray()) drafts[method] = (drafts[method].Account, "");
    }
    private static string DestinationKey(LoginMethod method, string account) => $"{method}:{account.Trim().ToLowerInvariant()}";
}
