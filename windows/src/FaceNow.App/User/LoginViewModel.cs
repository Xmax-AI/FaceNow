//
//  LoginViewModel.cs
//  FaceNow
//

using System.Text.RegularExpressions;
using FaceNow.Core.User;
using FaceNow.Core.Product;

namespace FaceNow.App.User;

/// <summary>Form drafts and monotonic resend deadlines, independently of WinUI and authentication.</summary>
internal sealed class LoginViewModel
{
    private readonly Dictionary<LoginMethod, (string Account, string Code)> drafts = [];
    private readonly Dictionary<string, long> deadlines = [];
    private readonly Func<long> milliseconds;
    private readonly ProductProfile product;

    public LoginViewModel(
        Func<long>? milliseconds = null,
        ProductProfile? product = null
    )
    {
        this.milliseconds = milliseconds ?? (() => Environment.TickCount64);
        this.product = product ?? ProductProfile.Current;
        Method = DefaultIndex == 0 ? LoginMethod.Sms : LoginMethod.Email;
    }

    public int DefaultIndex => product.ShowsPhoneLogin ? 0 : 1;

    public bool IsChannelVisible(
        int index
    ) => index switch
    {
        0 => product.ShowsPhoneLogin,
        1 => product.ShowsEmailLogin,
        2 => true,
        _ => false
    };

    public LoginConfiguration? Configuration { get; set; }

    public LoginMethod Method { get; private set; } = LoginMethod.Sms;

    public bool UsesApiKey { get; private set; }

    public string Account { get; private set; } = "";

    public string Code { get; private set; } = "";

    public string ApiKey { get; set; } = "";

    public bool IsBusy { get; set; }

    public bool ConfigurationFailed { get; set; }

    public string? Error { get; set; }

    public int CodeLength => Configuration?.CodeLength(Method) ?? 6;

    public bool ValidAccount => Account.Trim().Length <= 254 && Regex.IsMatch(Account.Trim(), Method == LoginMethod.Sms
        ? @"^1[3-9][0-9]{9}$" : @"^[^\s@]+@[^\s@]+\.[^\s@]+$", RegexOptions.CultureInvariant);

    public int Cooldown => deadlines.TryGetValue(DestinationKey(Method, Account), out long deadline)
        ? (int)Math.Max(0, Math.Ceiling((deadline - milliseconds()) / 1000d)) : 0;

    public bool CanSendCode => !IsBusy && !UsesApiKey && IsChannelVisible(Method == LoginMethod.Sms ? 0 : 1)
        && (Configuration?.Supports(Method) == true || ConfigurationFailed) && ValidAccount && Cooldown == 0;

    public bool CanSubmit => !IsBusy && (UsesApiKey ? !string.IsNullOrWhiteSpace(ApiKey)
        : IsChannelVisible(Method == LoginMethod.Sms ? 0 : 1) && (Configuration?.Supports(Method) == true || ConfigurationFailed) && ValidAccount && Code.Length == CodeLength);

    public static string SignInErrorMessage(
        Exception error,
        bool usingApiKey
    )
    {
        if (usingApiKey && error is AccountException failure && failure.Code != 429
            && (failure.IsUnauthorized || failure.Code is >= 400 and <= 499))
            return "Invalid API key. Check it and try again.";
        return error.Message;
    }

    public void SetAccount(
        string value
    )
    {
        if (Account != value)
        {
            Account = value;
            Code = "";
            Error = null;
        }
    }

    public void SetCode(
        string value
    )
    {
        Code = new(value.Where(c => c is >= '0' and <= '9').Take(CodeLength).ToArray());
        Error = null;
    }

    public void Select(
        int index
    )
    {
        if (!IsChannelVisible(index))
            return;
        drafts[Method] = (Account, Code);
        UsesApiKey = index == 2;
        if (!UsesApiKey)
        {
            Method = index == 0 ? LoginMethod.Sms : LoginMethod.Email;
            (Account, Code) = drafts.GetValueOrDefault(Method, ("", ""));
        }
        Error = null;
    }

    public void RecordSent(
        LoginMethod method,
        string account,
        int seconds
    ) =>
        deadlines[DestinationKey(method, account)] = milliseconds() + Math.Max(0, seconds) * 1000L;

    public void ClearSecrets()
    {
        ApiKey = "";
        Code = "";
        foreach (var method in drafts.Keys.ToArray())
            drafts[method] = (drafts[method].Account, "");
    }

    public void ResetAfterSignIn()
    {
        drafts.Clear();
        deadlines.Clear();
        Account = Code = ApiKey = "";
        Error = null;
        ConfigurationFailed = false;
        Method = DefaultIndex == 0 ? LoginMethod.Sms : LoginMethod.Email;
        UsesApiKey = Configuration?.Supports(Method) == false;
        // The in-flight request still owns IsBusy until its finally block completes.
    }

    private static string DestinationKey(
        LoginMethod method,
        string account
    ) => $"{method}:{account.Trim().ToLowerInvariant()}";
}
